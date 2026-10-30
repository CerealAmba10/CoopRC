// Co-op campaign game type: listen server, up to 4 Delta Squad players.
// The host plays Boss (38) as usual; joiners take Sev (07), Fixer (40) and Scorch (62) and play a
// real PlayerCommando (player HUD, health and perks) dressed as that Delta. Unclaimed slots stay AI.
// The squad sticks together while player controlled: joiners and respawns appear next to a teammate,
// stragglers are caught up, and a full wipe restarts the map instead of loading a save (which would
// drop every client).
class CoopGame extends CTGameInfoSP
	config(CoopRC);

const NUM_SLOTS = 3;

var class<Pawn>  SlotClass[NUM_SLOTS];  // 0 = Sev, 1 = Fixer, 2 = Scorch
var string       SlotName[NUM_SLOTS];   // value accepted by ?CoopSlot=
var string       SlotLongName[NUM_SLOTS];
var string       SlotWeapon[NUM_SLOTS]; // role weapon handed out on spawn, '' = none
var string       SlotSkin[NUM_SLOTS];
var string       BossSkin;
var CoopPlayer   SlotOwner[NUM_SLOTS];

var config float RespawnDelay;   // seconds dead before respawning next to a teammate
var config float LeashDistance;  // no teammate within this range ...
var config float LeashTime;      // ... for this many seconds -> caught up to the nearest one
var config float WipeDelay;      // seconds with every player dead before the map restarts

var config float ExitRadius;     // everyone who is up must be this close to the exit to travel

var float CheckTime;
var float WipeTime;
var Teleporter PendingExit;
var bool bInBriefing;
var int WaitForJoiners;
var float WaitDeadline, NextWaitMessage;
var array<Actor> ServerOnlyProps;
var bool bProxiesMade;
var int SlotClaimed[NUM_SLOTS]; // 1 once the map's AI version of that slot has been replaced

// Progression events that a removed AI commando's own map script would have fired. Only relayed when
// that slot is human. Found by tracing every campaign map's ScriptedSequences (see DESIGN.md).
struct MapFix
{
	var string Map;
	var int    Slot;
	var name   OnEvent;
	var float  Delay;
	var name   Fire;
};
var array<MapFix> MapFixes;

event InitGame(string Options, out string Error)
{
	local string MapName;
	local CoopEventRelay R;
	local int i;

	Super.InitGame(Options, Error);

	if(ParseOption(Options, "CoopTest") != "")
		Spawn(class'CoopTest').Mode = int(ParseOption(Options, "CoopTest"));

	// Link-up after the prologue: Boss waits here until this many friends have connected.
	WaitForJoiners = int(ParseOption(Options, "CoopWait"));
	WaitDeadline = Level.TimeSeconds + 120;

	KeepUnreplicableActorsOnServer();
	FixReplicatedLooks();

	MapName = Left(string(Level), InStr(string(Level), "."));

	for(i = 0; i < MapFixes.Length; ++i)
	{
		if(MapFixes[i].Map ~= MapName)
		{
			R = Spawn(class'CoopEventRelay',, MapFixes[i].OnEvent);
			R.Slot = MapFixes[i].Slot;
			R.Delay = MapFixes[i].Delay;
			R.Fire = MapFixes[i].Fire;
		}
	}
}

// Some maps make a static-class actor (e.g. a StaticMeshActor) movable in the editor. A client deletes
// those at load and then can't respawn them from replication (static class), which crashes it on join
// (geo_01c). Keep them server-only; a client may miss that one prop instead.
function KeepUnreplicableActorsOnServer()
{
	local Actor A;
	local int Count;

	ForEach AllActors(class'Actor', A)
	{
		if(!A.bStatic && !A.bNoDelete && A.RemoteRole != ROLE_None && (A.default.bStatic || A.default.bNoDelete))
		{
			A.RemoteRole = ROLE_None;
			ServerOnlyProps[ServerOnlyProps.Length] = A;
			Count++;
		}
	}

	if(Count > 0)
		Log("CoopRC: kept" @ Count @ "static-class actors server-only");
}

// Replicated map actors lose their editor DrawScale3D and skins on clients (only DrawScale and
// RepSkin replicate). Send both along.
function FixReplicatedLooks()
{
	local Actor A;
	local CoopScaleFix F;
	local int Count;

	ForEach AllActors(class'Actor', A)
	{
		if(A.bStatic || A.bNoDelete || A.RemoteRole == ROLE_None || A.IsA('Pawn') || A.IsA('Controller') || A.bHidden && A.DrawType == DT_None)
			continue;

		if(A.Skins.Length > 0 && A.Skins[0] != None && A.RepSkin == None)
			A.RepSkin = A.Skins[0];

		if(A.DrawScale3D != A.default.DrawScale3D)
		{
			F = Spawn(class'CoopScaleFix');
			F.Target = A;
			F.Scale3D = A.DrawScale3D;
			Count++;
		}
	}

	if(Count > 0)
		Log("CoopRC: sending editor scale for" @ Count @ "replicated actors");
}

// Clients get a replicated stand-in for each server-only prop that has a mesh (once the host's
// PlayerController exists: it owns them so the host doesn't see them twice).
function MakeProxies()
{
	local PlayerController Host;
	local CoopMeshProxy P;
	local int i;

	Host = Level.GetLocalPlayerController();

	if(Host == None)
		return;

	bProxiesMade = true;

	for(i = 0; i < ServerOnlyProps.Length; ++i)
	{
		if(ServerOnlyProps[i] == None || ServerOnlyProps[i].DrawType != DT_StaticMesh || ServerOnlyProps[i].StaticMesh == None)
			continue;

		P = Spawn(class'CoopMeshProxy', Host,, ServerOnlyProps[i].Location, ServerOnlyProps[i].Rotation);

		if(P != None)
		{
			P.Copy(ServerOnlyProps[i]);
			Log("CoopRC: client stand-in for" @ ServerOnlyProps[i] @ ServerOnlyProps[i].StaticMesh);
		}
	}
}

event PlayerController Login(string Portal, string Options, out string Error)
{
	local PlayerController PC;

	PC = Super.Login(Portal, Options, Error);

	if(CoopPlayer(PC) == None)
		return PC;

	// Host or joiner is only known in PostLogin (local viewport vs network connection).
	CoopPlayer(PC).RequestedSlot = ParseOption(Options, "CoopSlot");

	if(Level.GetLocalPlayerController() != None && PickSlot(CoopPlayer(PC).RequestedSlot) < 0)
	{
		Error = "Co-op squad is full";
		PC.Destroy();
		return None;
	}

	return PC;
}

event PostLogin(PlayerController NewPlayer)
{
	local CoopPlayer CP;
	local int Slot;

	CP = CoopPlayer(NewPlayer);

	// The host (Boss) is the player on this machine's viewport; everyone else takes a Delta slot.
	if(CP != None && Viewport(NewPlayer.Player) == None)
	{
		Slot = PickSlot(CP.RequestedSlot);

		if(Slot >= 0)
		{
			SlotOwner[Slot] = CP;
			CP.CoopSlot = Slot;
			Log("CoopRC: player joined as" @ SlotName[Slot]);

			// The map's AI squad version of this commando goes away now and the events its script would
			// have fired are relayed instead. During a briefing (rappel intros etc.) the AI double plays
			// its part first while the player watches through its eyes; the player takes over after.
			if(!bInBriefing)
				ClaimSlot(Slot);
		}
	}

	Super.PostLogin(NewPlayer);

	if(bInBriefing && CoopPlayer(NewPlayer) != None && CoopPlayer(NewPlayer).CoopSlot >= 0)
		WatchBriefing(CoopPlayer(NewPlayer));
}

function bool WaitingForSquad()
{
	local Controller C;
	local int Joined;

	if(WaitForJoiners <= 0)
		return false;

	for(C = Level.ControllerList; C != None; C = C.NextController)
	{
		if(CoopPlayer(C) != None && CoopPlayer(C).CoopSlot >= 0)
			Joined++;
	}

	if(Joined >= WaitForJoiners || Level.TimeSeconds > WaitDeadline)
	{
		Log("CoopRC: squad linked up (" $ Joined $ "/" $ WaitForJoiners $ ")");
		WaitForJoiners = 0;
		return false;
	}

	if(Level.TimeSeconds >= NextWaitMessage)
	{
		NextWaitMessage = Level.TimeSeconds + 5;
		BroadcastCoop("Waiting for the squad to link up (" $ Joined $ "/" $ WaitForJoiners $ ")");
	}

	return true;
}

// Host picked New Game (or a level) from the menu: take the whole session there.
function StartCoop(string MapName)
{
	Log("CoopRC: starting co-op at" @ MapName);
	BroadcastCoop("Starting...");
	Level.ServerTravel(MapName $ "?game=CoopRC.CoopGame", false);
}

function BroadcastCoop(string Msg)
{
	local Controller C;

	for(C = Level.ControllerList; C != None; C = C.NextController)
	{
		if(PlayerController(C) != None)
			PlayerController(C).ClientMessage(Msg);
	}
}

//=============================================================================
// Briefings: in-level cutscenes (camera lock + scripted anims on Boss, e.g. the rappel intros).
// Called from CoopConsole's ACTION_Briefing override.

function BriefingChanged(bool bStart)
{
	local Controller C;
	local CoopPlayer CP;

	if(bStart == bInBriefing)
		return;

	bInBriefing = bStart;
	if(bStart)
		Log("CoopRC: briefing started");
	else
		Log("CoopRC: briefing ended");

	for(C = Level.ControllerList; C != None; C = C.NextController)
	{
		CP = CoopPlayer(C);

		if(CP == None || CP.CoopSlot < 0)
			continue;

		if(bStart)
		{
			WatchBriefing(CP);
		}
		else if(CP.Pawn != None)
		{
			CP.SetViewTarget(CP.Pawn);
			CP.ClientSetViewTarget(CP.Pawn);
		}
		else
		{
			RestartPlayer(CP); // takes over the AI double where it landed; Tick retries if not ready yet
		}
	}
}

// Watch through your own commando's AI double if it's in the scene, otherwise through Boss.
function WatchBriefing(CoopPlayer CP)
{
	local Actor Target;
	local Controller C;

	if(SlotClaimed[CP.CoopSlot] == 0)
		Target = FindSlotAI(CP.CoopSlot);

	if(Target == None)
	{
		for(C = Level.ControllerList; C != None; C = C.NextController)
		{
			if(CoopPlayer(C) != None && CoopPlayer(C).CoopSlot < 0 && C.Pawn != None)
				Target = C.Pawn;
		}
	}

	if(Target == None)
		return;

	CP.SetViewTarget(Target);
	CP.ClientSetViewTarget(Target);
	CP.ClientSetBehindView(false);
}

function Pawn FindSlotAI(int Slot)
{
	local Actor A;
	local Pawn P;

	ForEach DynamicActors(SlotClass[Slot], A)
	{
		P = Pawn(A);

		if(P.Health > 0 && PlayerController(P.Controller) == None && P.Tag == SlotClass[Slot].Name && P.bCanBeSquadMember)
			return P;
	}

	return None;
}

function int PickSlot(string Requested)
{
	local int i;

	for(i = 0; i < NUM_SLOTS; ++i)
	{
		if(SlotOwner[i] == None && Requested == SlotName[i])
			return i;
	}

	for(i = 0; i < NUM_SLOTS; ++i)
	{
		if(SlotOwner[i] == None)
			return i;
	}

	return -1;
}

function Logout(Controller Exiting)
{
	local int i;
	local Pawn P;

	for(i = 0; i < NUM_SLOTS; ++i)
	{
		if(SlotOwner[i] == Exiting)
			SlotOwner[i] = None;
	}

	// The engine kills a leaving player's pawn ("Suicided"), and on a server that death path plays
	// Dying twice and crashes the host. Remove the pawn quietly instead.
	if(Exiting.Pawn != None)
	{
		P = Exiting.Pawn;
		Exiting.UnPossess();
		P.Destroy();
	}

	Super.Logout(Exiting);
}

function RestartPlayer(Controller aPlayer)
{
	local CoopPlayer CP;
	local Pawn P, Anchor, Double;
	local bool bRespawn;

	CP = CoopPlayer(aPlayer);

	if(CP == None)
	{
		Super.RestartPlayer(aPlayer);
		return;
	}

	bRespawn = aPlayer.IsInState('Dead');
	Anchor = FindAnchor(aPlayer);

	// Nobody up to spawn next to (the wipe check restarts the map), or they're mid-air (rappel intro,
	// rope, fall): CoopGame.Tick retries every second.
	if((bRespawn || CP.CoopSlot >= 0) && (Anchor == None || Anchor.Physics != PHYS_Walking))
		return;

	if(CP.CoopSlot < 0 && !bRespawn && WaitingForSquad())
		return; // Tick retries; the level (and its intro) starts once the squad has linked up

	if(CP.CoopSlot < 0)
	{
		// Boss: CTGameInfoSP would load a save when dead, so spawn like a plain GameInfo instead.
		Super(GameInfo).RestartPlayer(aPlayer);

		if(aPlayer.Pawn == None)
			return;

		if(bRespawn)
			MoveNear(aPlayer.Pawn, Anchor);

		SetArmor(aPlayer.Pawn, BossSkin);
		return;
	}

	if(bInBriefing && !bRespawn)
		return; // watching the scene; spawned when it ends

	// First spawn after a briefing: take over where the AI double ended up (e.g. where Scorch landed),
	// then remove it.
	if(SlotClaimed[CP.CoopSlot] == 0)
	{
		Double = FindSlotAI(CP.CoopSlot);

		if(Double != None && Double.Physics == PHYS_Walking)
			P = SpawnNear(class'PlayerCommando', Double);

		ClaimSlot(CP.CoopSlot);
	}

	if(P == None && Anchor != None)
		P = SpawnNear(class'PlayerCommando', Anchor);

	if(P == None)
	{
		Log("CoopRC: could not place" @ SlotName[CP.CoopSlot] @ "near a teammate, using the start spot");
		Super(GameInfo).RestartPlayer(aPlayer);
		P = aPlayer.Pawn;

		if(P == None)
			return;
	}
	else
	{
		CP.Possess(P);
		CP.ClientSetRotation(P.Rotation);
	}

	// No Delta tag on the player: scripts DestroyActor/HurtActor squad members by tag (yyy_06d, geo_01c).
	P.AudioTable = SlotClass[CP.CoopSlot].default.AudioTable;
	SetArmor(P, SlotSkin[CP.CoopSlot]);

	// Kit after Possess: Weapon.GiveTo needs the owning controller to tell the client which weapon is up.
	GivePlayerKit(P, CP.CoopSlot);
	CP.SwitchToBestWeapon();
}

// Only the squad version (standard Commando##Delta tag, bCanBeSquadMember) is removed. Cinematic-only
// copies (the prologue) keep playing their scenes. Story pawns with other tags
// (captive "Seven", "Delta07" in the execution scene, briefing holo throwers) stay AI because their
// scripts drive progression.
function ClaimSlot(int Slot)
{
	local Actor A;
	local Pawn P;
	local CoopEventRelay R;

	SlotClaimed[Slot] = 1;

	ForEach DynamicActors(SlotClass[Slot], A)
	{
		P = Pawn(A);

		if(PlayerController(P.Controller) != None || P.Tag != SlotClass[Slot].Name || !P.bCanBeSquadMember)
			continue;

		if(P.Controller != None)
		{
			P.Controller.UnPossess();
			P.Controller.Destroy();
		}

		P.Destroy();
	}

	ForEach DynamicActors(class'CoopEventRelay', R)
	{
		if(R.Slot == Slot)
			R.SlotClaimed();
	}
}

function Killed(Controller Killer, Controller Killed, Pawn KilledPawn, class<DamageType> DamageType)
{
	if(PlayerCommando(KilledPawn) != None)
		Log("CoopRC: player pawn killed" @ KilledPawn @ "by" @ Killer @ "with" @ DamageType @ "state" @ KilledPawn.GetStateName() @ "physics" @ KilledPawn.Physics);

	Super.Killed(Killer, Killed, KilledPawn, DamageType);
}

//=============================================================================
// Squad cohesion: respawn, catch-up, wipe

function bool IsUp(Controller C)
{
	return C.Pawn != None && C.Pawn.Health > 0 && !C.Pawn.bIncapacitated;
}

// Where to put a player: Boss if he's up, otherwise any teammate who is.
function Pawn FindAnchor(Controller Exclude)
{
	local Controller C;
	local Pawn Best;

	for(C = Level.ControllerList; C != None; C = C.NextController)
	{
		if(C == Exclude || CoopPlayer(C) == None || !IsUp(C))
			continue;

		if(CoopPlayer(C).CoopSlot < 0)
			return C.Pawn;

		if(Best == None)
			Best = C.Pawn;
	}

	return Best;
}

function Pawn NearestTeammate(Controller Of)
{
	local Controller C;
	local Pawn Best;

	for(C = Level.ControllerList; C != None; C = C.NextController)
	{
		if(C == Of || CoopPlayer(C) == None || !IsUp(C))
			continue;

		if(Best == None || VSize(C.Pawn.Location - Of.Pawn.Location) < VSize(Best.Location - Of.Pawn.Location))
			Best = C.Pawn;
	}

	return Best;
}

//=============================================================================
// Level exits: wait for the whole squad

function ExitReached(Teleporter T)
{
	if(PendingExit == None)
		Log("CoopRC: level exit reached ->" @ T.URL);

	PendingExit = T;
	CheckExit();
}

// Travels once every player is up and standing in the exit area. Downed or dead players hold it until
// they're revived or respawn (next to a teammate, i.e. at the exit). Cleared if everyone walks away.
function CheckExit()
{
	local Controller C;
	local PlayerController Host;
	local int Total, AtExit;

	if(PendingExit == None)
		return;

	for(C = Level.ControllerList; C != None; C = C.NextController)
	{
		if(CoopPlayer(C) == None)
			continue;

		Total++;

		if(IsUp(C) && VSize(C.Pawn.Location - PendingExit.Location) <= ExitRadius)
			AtExit++;
	}

	if(AtExit == 0)
	{
		PendingExit = None;
		return;
	}

	if(AtExit < Total)
	{
		for(C = Level.ControllerList; C != None; C = C.NextController)
		{
			if(CoopPlayer(C) != None)
				PlayerController(C).ClientMessage("Waiting for the squad at the exit (" $ AtExit $ "/" $ Total $ ")");
		}

		return;
	}

	Host = Level.GetLocalPlayerController();

	if(Host.Pawn != None && Host.Pawn.Squad != None)
		Host.Pawn.SaveSquadTravelInfo();

	Log("CoopRC: whole squad at the exit, travelling to" @ PendingExit.URL);
	Level.ServerTravel(PendingExit.URL, true);
	PendingExit = None;
}

// Manual (CatchUp key) and automatic catch-up both land here.
function CatchUp(CoopPlayer CP)
{
	local Pawn To;

	if(!IsUp(CP))
		return;

	To = NearestTeammate(CP);

	if(To != None && MoveNear(CP.Pawn, To))
		Log("CoopRC:" @ CP.PlayerReplicationInfo.PlayerName @ "caught up to" @ To);
}

event Tick(float Delta)
{
	local Controller C;
	local CoopPlayer CP;
	local Pawn Mate;
	local bool bAnyAlive, bAnyPlayer;

	Super.Tick(Delta);

	CheckTime -= Delta;

	if(CheckTime > 0)
		return;

	CheckTime = 1.0;
	CheckExit();

	if(!bProxiesMade)
		MakeProxies();

	for(C = Level.ControllerList; C != None; C = C.NextController)
	{
		CP = CoopPlayer(C);

		if(CP == None)
			continue;

		bAnyPlayer = true;

		if(C.Pawn != None && C.Pawn.Health > 0)
			bAnyAlive = true;

		// Respawn next to a teammate instead of the SP "load last save". Also retries joiners whose
		// first spawn had to wait for a teammate on the ground.
		if(C.IsInState('Dead') || C.Pawn == None)
		{
			CP.DeadTime += 1.0;

			if(CP.DeadTime >= RespawnDelay || !C.IsInState('Dead'))
			{
				CP.DeadTime = 0;
				RestartPlayer(CP);
			}
		}
		else
		{
			CP.DeadTime = 0;
		}

		// Left behind (a backtrack got cut off, or they just wandered): bring them to the nearest teammate.
		if(IsUp(C))
		{
			// Empty hands: briefings only bring back the *last* weapon, and pawns spawned around a
			// briefing (link-up, Boss's first spawn) have none, so equip the best one.
			if(C.Pawn.Weapon == None && C.Pawn.Inventory != None && !bInBriefing && !C.IsInState('Briefing'))
			{
				C.Pawn.PendingWeapon = None;
				C.SwitchToBestWeapon();
			}

			Mate = NearestTeammate(C);

			if(Mate != None && VSize(Mate.Location - C.Pawn.Location) > LeashDistance)
			{
				CP.AloneTime += 1.0;

				if(CP.AloneTime >= LeashTime)
				{
					CP.AloneTime = 0;
					CatchUp(CP);
				}
			}
			else
			{
				CP.AloneTime = 0;
			}
		}
	}

	// Everyone dead: restart the map with ServerTravel so all clients come along.
	if(bAnyPlayer && !bAnyAlive && WaitForJoiners <= 0) // not while Boss waits for the squad to link up
	{
		WipeTime += 1.0;

		if(WipeTime >= WipeDelay)
		{
			Log("CoopRC: squad wiped, restarting" @ Left(string(Level), InStr(string(Level), ".")));
			Level.ServerTravel("?restart", false);
			WipeTime = -1000; // once
		}
	}
	else if(WipeTime >= 0)
	{
		WipeTime = 0;
	}
}

//=============================================================================
// Placement helpers

// Spots in a ring around the anchor so nobody lands inside anyone.
function vector RingSpot(Actor Anchor, int i)
{
	local vector Offset;

	Offset.X = 120 * Cos(i * 0.785398);
	Offset.Y = 120 * Sin(i * 0.785398);

	return Anchor.Location + Offset;
}

function Pawn SpawnNear(class<Pawn> PawnClass, Actor Anchor)
{
	local Pawn P;
	local int i;

	for(i = 0; i < 8; ++i)
	{
		P = Spawn(PawnClass,,, RingSpot(Anchor, i), Anchor.Rotation);

		if(P != None)
			return P;
	}

	return None;
}

function bool MoveNear(Pawn P, Actor Anchor)
{
	local int i;

	for(i = 0; i < 8; ++i)
	{
		if(P.SetLocation(RingSpot(Anchor, i)))
		{
			P.SetRotation(Anchor.Rotation);

			if(P.Controller != None)
				P.Controller.ClientSetRotation(Anchor.Rotation);

			return true;
		}
	}

	return false;
}

//=============================================================================
// Looks and kit

// RepSkin replicates to every client and sets Skins[0] there.
function SetArmor(Pawn P, string SkinName)
{
	local Material M;

	M = Material(DynamicLoadObject(SkinName, class'Material'));

	if(M == None)
		return;

	P.Skins[0] = M;
	P.RepSkin = M;
}

// Joiners get exactly what Boss gets on this map (PlayerCommando's default kit plus the map's
// PlayerStart.StartInventory, which is where the DC-15s comes from), plus their role weapon.
function GivePlayerKit(Pawn P, int Slot)
{
	P.AddDefaultInventory();

	if(SlotWeapon[Slot] != "")
		P.CreateInventory(SlotWeapon[Slot]);

	LogInventory(P);
}

function LogInventory(Pawn P)
{
	local Inventory Inv;
	local string S;

	for(Inv = P.Inventory; Inv != None; Inv = Inv.Inventory)
		S = S @ Inv.Class.Name;

	Log("CoopRC:" @ P.Class.Name @ "at" @ P.Location @ "inventory:" $ S);
}

defaultproperties
{
	MaxPlayers=4
	bPauseable=False
	PlayerControllerClassName="CoopRC.CoopPlayer"
	RespawnDelay=4
	LeashDistance=3000
	LeashTime=20
	WipeDelay=3
	ExitRadius=500
	SlotClass(0)=Class'CTCharacters.Commando07Delta'
	SlotClass(1)=Class'CTCharacters.Commando40Delta'
	SlotClass(2)=Class'CTCharacters.Commando62Delta'
	SlotName(0)="07"
	SlotName(1)="40"
	SlotName(2)="62"
	SlotLongName(0)="Sev (07)"
	SlotLongName(1)="Fixer (40)"
	SlotLongName(2)="Scorch (62)"
	SlotSkin(0)="CloneTextures.CloneTextures.CloneCommando07_Shader"
	SlotSkin(1)="CloneTextures.CloneTextures.CloneCommando40_Shader"
	SlotSkin(2)="CloneTextures.CloneTextures.CloneCommando62_Shader"
	BossSkin="CloneTextures.CloneTextures.CloneCommando38_Shader"
	SlotWeapon(0)="CTInventory.DC17mSniper"
	SlotWeapon(2)="CTInventory.DC17mAntiArmor"
	MapFixes(0)=(Map="geo_01b",Slot=1,OnEvent="DoorTo40Destroyed",Delay=5,Fire="PopUp40Intro")
	MapFixes(1)=(Map="geo_01b",Slot=1,OnEvent="DoorTo40Destroyed",Delay=6,Fire="ShieldDialog")
	MapFixes(2)=(Map="geo_01c",Slot=0,OnEvent="07Intro",Delay=6,Fire="PopUp07Intro")
	MapFixes(3)=(Map="geo_01c",Slot=0,OnEvent="07Intro",Delay=7,Fire="ActivateSquad")
	MapFixes(4)=(Map="geo_01c",Slot=0,OnEvent="StartSunFacRunning",Delay=0,Fire="InSnipePosition")
	MapFixes(5)=(Map="geo_03a",Slot=2,OnEvent="levelstart",Delay=0.1,Fire="HoloProjector")
	MapFixes(6)=(Map="geo_05b",Slot=0,OnEvent="MoveToElevator",Delay=3,Fire="MemberArrived")
	MapFixes(7)=(Map="geo_05b",Slot=1,OnEvent="MoveToElevator",Delay=3,Fire="MemberArrived")
	MapFixes(8)=(Map="geo_05b",Slot=2,OnEvent="MoveToElevator",Delay=3,Fire="MemberArrived")
	MapFixes(9)=(Map="geo_05c",Slot=0,OnEvent="Evacuate",Delay=3,Fire="MemberArrived00")
	MapFixes(10)=(Map="geo_05c",Slot=1,OnEvent="Evacuate",Delay=3,Fire="MemberArrived00")
	MapFixes(11)=(Map="geo_05c",Slot=2,OnEvent="Evacuate",Delay=3,Fire="MemberArrived00")
	MapFixes(12)=(Map="geo_05c",Slot=0,OnEvent="GunshipReached",Delay=3,Fire="MemberArrived01")
	MapFixes(13)=(Map="geo_05c",Slot=1,OnEvent="GunshipReached",Delay=3,Fire="MemberArrived01")
	MapFixes(14)=(Map="geo_05c",Slot=2,OnEvent="GunshipReached",Delay=3,Fire="MemberArrived01")
}
