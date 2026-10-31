// Player controller for co-op: adds client-side versions of the SP-only screens.
class CoopPlayer extends CTPlayer;

var int CoopSlot; // -1 = host (Boss), otherwise index into CoopGame's slots
var string RequestedSlot;     // ?CoopSlot= from the join URL
var float LobbyMenuTime;      // CoopLobby: when to open the main menu for this player
var float DeadTime, AloneTime; // server-side, see CoopGame.Tick
var Squad LocalSquad;          // client-side only, see PlayerTick
var ActivateItem ServerPanel;  // server-side: the charge/panel a joiner is holding Use on, see ServerCoopUse
var ETargetType ServerPanelType;
var bool bItemsUnlocked;       // UnlockSquadItems ran for this level
var Actor LoggedTarget;        // client: last usable item reported in the log
var ETargetType LoggedTargetType;


replication
{
	reliable if(Role == ROLE_Authority)
		ClientShowMenu, ClientPlayMovie, ClientStartIntro, ClientLobbyNotice, ClientTestSquadOrder, ClientEnsureProfile, ClientTestUse, ClientCoopMusic, ClientCoopBattleMusic;
	reliable if(Role < ROLE_Authority)
		ServerCatchUp, ServerCoopUse, ServerCoopStopUse;
}

// The targeting/marker code (native, runs on the client every tick) assumes the pawn has a squad.
// Pawn.Squad isn't replicated, so on a client it's always None and looking at a squad marker (e.g. the
// balcony snipe marker in geo_01c) crashes the client. Give the client's own pawn a local squad.
event PlayerTick(float DeltaTime)
{
	if(!bItemsUnlocked)
		UnlockSquadItems();

	if(Role < ROLE_Authority && Pawn != None && Pawn.Squad == None)
	{
		if(LocalSquad == None)
			LocalSquad = Spawn(class'CTSquad');

		if(LocalSquad != None)
		{
			LocalSquad.SquadLeader = Pawn;
			Pawn.Squad = LocalSquad;
		}
	}

	if(Role < ROLE_Authority && GameReplicationInfo != None && GameReplicationInfo.Teams[0] == None)
		ClientCreateTeams();

	if(Role < ROLE_Authority)
	{
		ClientTargetTick(DeltaTime);
		ClientUsableTarget();

		if(Target != LoggedTarget || (ActivateItem(Target) != None && TargetType != LoggedTargetType))
		{
			LoggedTarget = Target;
			LoggedTargetType = TargetType;
			if(ActivateItem(Target) != None)
				Log("CoopRC: aiming at" @ Target @ "target type" @ TargetType @ "state" @ Target.GetStateName() @ "usable" @ ActivateItem(Target).bIsUsable
					@ ActivateItem(Target).bIsUsableByPlayer @ "activating" @ ActivateItem(Target).bActivating @ "role" @ Target.Role
					@ "dist" @ VSize(Target.Location - Pawn.Location) @ "marker" @ TargetMarker);
		}
	}
	else
	{
		Super.PlayerTick(DeltaTime);

		// Keep the joiner aimed at what they're working on: the item only progresses while its user is
		// holding Use on a panel (ActivateItem.BeginActivating).
		if(ServerPanel != None && bUse)
		{
			Target = ServerPanel;
			TargetType = ServerPanelType;
		}
		else
			ServerPanel = None;
	}
}

// A few tutorial items are squad-only (bIsUsableByPlayer=False): the geo_01a bunker charge (Scorch), the
// geo_01b shield terminal (Fixer) and the geo_01c breach door. With that commando played by a human,
// Boss can have nobody left to order and the level stalls, so in co-op anyone can do them. Both ends need
// it: the client's targeting decides whether Use goes to the item.
simulated function UnlockSquadItems()
{
	local ActivateItem A;
	local int Count;

	bItemsUnlocked = true;

	ForEach AllActors(class'ActivateItem', A)
	{
		if(!A.bIsUsableByPlayer)
		{
			A.bIsUsableByPlayer = true;
			Count++;
		}
	}

	if(Count > 0)
		Log("CoopRC: made" @ Count @ "squad-only items usable by players");
}

// The native targeting never offers an item to a client as usable (the host gets TGT_Panel for the same
// charge, the client TGT_Default), and the client's copy never learns the item's state (placed, armed,
// used) anyway. So any item in reach counts as usable here and the server, which knows its real state,
// decides what Use does (ServerCoopUse).
simulated function ClientUsableTarget()
{
	if(TargetType == TGT_Default && ActivateItem(Target) != None && Pawn != None
		&& VSize(Target.Location - Pawn.Location) <= ActivateItem(Target).PlayerRange)
		TargetType = TGT_Panel;
}

// CoopTest mode 9: look at AimAt and press (or release) Use on the joiner's own machine, as the player would.
simulated function ClientTestUse(bool bDown, vector AimAt)
{
	local int i;

	if(bDown && Pawn != None)
	{
		for(i = 0; i < 16; i++) // a range of heights: items sit on crates and desks
		{
			SetRotation(rotator(AimAt + vect(0,0,8) * (i - 3) - (Pawn.Location + Pawn.EyePosition())));
			TargetLastUpdated = 0;
			ClientTargetTick(0);
			ClientUsableTarget();

			Log("CoopRC: test aim" @ i @ "from" @ Pawn.Location @ "dist" @ VSize(AimAt - Pawn.Location) @ "->" @ Target @ TargetType);

			if(TargetType == TGT_Panel || TargetType == TGT_DemolitionReady)
				break;
		}
	}

	Log("CoopRC: test Use" @ bDown @ "target" @ Target @ TargetType);

	if(bDown)
		Use();
	else
		StopUse();
}

// Charges, hack panels and plungers (ActivateItems) are used in CTPlayer.Use, which only runs where the
// button was pressed: on a client it sets the item's flags locally and never reaches the server, so a
// joiner could see "hold Use to place charge" but nothing happened. Send it to the server and run the
// same Use there, aimed at the same item (sent as a reference; an item the client only has a local copy
// of arrives as None, so it's also found by position).
exec function Use()
{
	if(Role < ROLE_Authority && ActivateItem(Target) != None && (TargetType == TGT_Panel || TargetType == TGT_DemolitionReady))
		ServerCoopUse(ActivateItem(Target), Target.Location, TargetType);

	Super.Use();
}

exec function StopUse()
{
	if(Role < ROLE_Authority)
		ServerCoopStopUse();

	Super.StopUse();
}

function ServerCoopUse(ActivateItem Item, vector ItemLocation, ETargetType Type)
{
	local ActivateItem A, Found;

	if(Pawn == None)
		return;

	Found = Item;

	if(Found == None)
	{
		ForEach AllActors(class'ActivateItem', A)
		{
			if(VSize(A.Location - ItemLocation) < 64)
				Found = A;
		}
	}

	if(Found == None || VSize(Found.Location - Pawn.Location) > 400)
		return;

	if(Found.ActivateItemType == AIT_Plunger) // an armed charge: the client can't tell it from an unplaced one
		Type = TGT_DemolitionReady;

	ServerPanel = Found;
	ServerPanelType = Type;
	Target = Found;
	TargetType = Type;
	Use();

	// Locally the hand signal animation starts the item (HandSignal.HolsterAttachment) or fires the plunger
	// (HandSignal.FireWeapon); the server doesn't animate a remote player's hands, so do it here.
	if(Type == TGT_Panel && Found.bIsUsable && !Found.bActivating)
		Found.StartSetup(self);
	else if(Type == TGT_DemolitionReady && Found.ActivateItemType == AIT_Plunger)
		Found.GotoState('Explode');
}

function ServerCoopStopUse()
{
	ServerPanel = None;
	StopUse();
}

// The friend/foe check the crosshair runs on whatever you aim at (native Pawn.GetRelationTowards)
// reads GameReplicationInfo.Teams, which the server creates (CTGameInfoSP.PostBeginPlay) but never
// sends to clients: aiming at an NPC crashed them. Build the same teams locally; their relations
// come from class defaults, so they match the server's.
function ClientCreateTeams()
{
	local GameReplicationInfo GRI;
	local int i;

	GRI = GameReplicationInfo;
	Log("CoopRC: client has no teams, creating them locally");

	AddClientTeam(GRI, 0, class'TeamNeutral');
	for(i = 1; i <= 2; ++i)
		AddClientTeam(GRI, i, class'TeamPlayer');
	AddClientTeam(GRI, 3, class'TeamWookiee');
	AddClientTeam(GRI, 4, class'TeamAttachedScav');
	AddClientTeam(GRI, 5, class'TeamHostile');
	for(i = 6; i <= 8; ++i)
		AddClientTeam(GRI, i, class'TeamMP');
	AddClientTeam(GRI, 9, class'TeamBerserker');
}

function AddClientTeam(GameReplicationInfo GRI, int Index, class<TeamInfo> TeamClass)
{
	local TeamInfo T;

	T = Spawn(TeamClass);

	if(T == None)
		return;

	T.TeamIndex = Index;
	GRI.Teams[Index] = T;
	GRI.TeamSize++;
}

// CTPlayer.PlayerTick for clients: same targeting, minus the AI enemy bookkeeping (SetEnemy,
// IsValidEnemy), which is native, assumes server-side AI state and crashed clients when their
// crosshair crossed an NPC. Enemy only matters to the server's AI.
function ClientTargetTick(float DeltaTime)
{
	local Actor OldTarget;
	local ETargetType OldTargetType;

	OldTarget = Target;
	OldTargetType = TargetType;

	if(Pawn != None)
	{
		if(Level.TimeSeconds > Pawn.NextFootstepTime && VSizeSq(Pawn.Velocity) > 1 && Pawn.Visibility != 0)
		{
			if(Pawn.bIsCrouched || Pawn.bIsWalking)
			{
				if(Pawn.WalkStimulus != ST_Invalid)
					Pawn.PostStimulusToWorld(Pawn.WalkStimulus);
			}
			else if(Pawn.RunStimulus != ST_Invalid)
				Pawn.PostStimulusToWorld(Pawn.RunStimulus);
			Pawn.NextFootstepTime = Level.TimeSeconds + 0.25f;
		}

		if(TargetLastUpdated + 0.1 <= Level.TimeSeconds)
		{
			TargetType = SelectTargetType();
			TargetLastUpdated = Level.TimeSeconds;
			ReturnToWeapon();
		}

		if(OldTarget != Target || OldTargetType != TargetType)
		{
			if(OldTarget != None)
			{
				OldTarget.NotifyUnTargeted(self);
				if(OldTarget.IsA('Pawn'))
					Pawn(OldTarget).bBeingRevivedByPlayer = false;
			}
			if(Target != None)
				Target.NotifyTargeted(self);
			if(OldTargetMarker != None)
				OldTargetMarker.NotifyUnTargeted(self);
			if(TargetMarker != None)
				TargetMarker.NotifyTargeted(self);
			OldTargetMarker = TargetMarker;
			TargetDuration = 0;
			ReturnToWeapon();
		}
		else
		{
			if(TargetMarker != None)
			{
				TargetMarker.UpdateIcons(self);
			}
			TargetDuration += DeltaTime;
		}
	}

	Super(PlayerController).PlayerTick(DeltaTime);
}

// The host started New Game: play the prologue locally, then link up with the host at Geonosis.
simulated function ClientStartIntro(string Slot, string MapName)
{
	if(CoopConsole(Player.Console) != None)
		CoopConsole(Player.Console).BeginIntro(false, Level.GetAddressURL(), Slot, 0);

	ConsoleCommand("start " $ MapName); // "start" = fresh URL: no server, no options from this session
}

simulated function ClientPlayMovie(bool bLoop, bool bInterruptable, bool bPauseMusic, bool bPauseSound, string MovieName)
{
	PlayMovie(bLoop, bInterruptable, bPauseMusic, bPauseSound, MovieName);
}

// The main menu sends a player with no profile loaded to profile select (and one with no profiles to
// typing a new name), on top of the lobby. Joiners just get one: their first profile, or a new one.
simulated function ClientEnsureProfile()
{
	local string Current, List, Name;

	Current = ConsoleCommand("PROFILE GETCURRENTPROFILE DEVICE=0");

	if(Current != "" && Current != "<Default>")
		return;

	List = ConsoleCommand("PROFILE LIST DEVICE=0 UNIQUE=0");

	if(List == "")
	{
		Name = "Commando";
		ConsoleCommand("PROFILE NEW DEVICE=0 NAME=" $ Name $ " CHARACTER=Player FACE=NONE");
	}
	else if(InStr(List, ",") >= 0)
		Name = Left(List, InStr(List, ","));
	else
		Name = List;

	ConsoleCommand("PROFILE LOAD DEVICE=0 NAME=" $ Name);
	Log("CoopRC: no profile loaded, using" @ Name @ "->" @ ConsoleCommand("PROFILE GETCURRENTPROFILE DEVICE=0"));
}

// Lobby popup over the main menu (who joined / that you're in); closing it returns to the menu.
simulated function ClientLobbyNotice(string Title, string Text)
{
	local MenuMessageBox Box;

	if(Player == None || Player.Console == None)
		return;

	// Filled in before opening: MenuCall swaps menus a frame later, so CurMenu is still the old one.
	Box = Spawn(class'MenuMessageBox', self);

	if(Box == None)
		return;

	Box.SetText(Text, Title);
	Player.Console.MenuCallExisting(Box, "");
}

// The main menu's Campaign Map (and anything else that does "open <map>") would take the host out of the
// co-op lobby alone, dropping everyone and running the level with the lobby rules (nobody spawns). Start
// it as co-op instead. A joiner's own "open" from the lobby would just leave the session.
function string ConsoleCommand(string Command)
{
	local string Map;

	if(Left(Caps(Command), 5) == "OPEN " && Left(Caps(string(Level)), 9) == "MPCUSTOM.")
	{
		if(CoopLobby(Level.Game) != None)
		{
			Map = Mid(Command, 5);
			if(InStr(Map, "?") >= 0)
				Map = Left(Map, InStr(Map, "?"));
			CoopLobby(Level.Game).StartCoop(Map);
			return "";
		}

		if(Level.NetMode == NM_Client)
		{
			ClientLobbyNotice("", "In co-op the host picks the level.");
			return "";
		}
	}

	return Super.ConsoleCommand(Command);
}

// Level music, sent from the server's scripts (CoopConsole.MusicInitActionFor and the battle music ones).
simulated function ClientCoopMusic(Sound Song, bool bOverride, float FadeIn, EMusicFadeType InType, float FadeOut, EMusicFadeType OutType)
{
	PlayMusic(Song, bOverride, FadeIn, InType, FadeOut, OutType);
}

simulated function ClientCoopBattleMusic(Sound Multi, bool bForce)
{
	if(ViewTarget == None)
		return;

	if(bForce)
		ViewTarget.ForceBattleMusic();
	else
		ViewTarget.SetBattleMusicMulti(Multi);
}

// With every commando played by a human Boss's squad is empty, and these three orders (the ones CTPlayer
// doesn't check for live members) crash the helmet HUD on an empty squad. Nothing to order anyway.
function bool SquadHasAI()
{
	return Pawn != None && Pawn.Squad != None && Pawn.Squad.CountAliveMembers() > 0;
}

exec function SetStanceHold()
{
	if(SquadHasAI())
		Super.SetStanceHold();
}

exec function CancelAllOrders()
{
	if(SquadHasAI())
		Super.CancelAllOrders();
}

exec function SquadRecall()
{
	if(SquadHasAI())
		Super.SquadRecall();
}

// CoopTest mode 7: the squad order keys, by index.
function RunSquadOrder(int i)
{
	switch(i)
	{
	case 0: SetStanceOffensive(); break;
	case 1: SetStanceDefensive(); break;
	case 2: SetStanceHold(); break;
	case 3: SquadEngage(); break;
	case 4: CancelAllMarkers(); break;
	case 5: CancelAllOrders(); break;
	case 6: SquadRecall(); break;
	}
}

simulated function ClientTestSquadOrder(int i)
{
	Log("CoopRC: test squad order" @ i);
	RunSquadOrder(i);
}

// Bound to a key by the installer. Brings you to the nearest teammate who is up.
exec function CatchUp()
{
	ServerCatchUp();
}

function ServerCatchUp()
{
	if(CoopGame(Level.Game) != None)
		CoopGame(Level.Game).CatchUp(self);
}

// The SP death screen offers load/restart/quit, which would drop a client from the session.
// In co-op you respawn next to a teammate (CoopGame) or press fire to do it right away.
state Dead
{
	function Timer()
	{
		if(bFrozen)
		{
			bFrozen = false;
			bPressedJump = false;
		}
	}
}

// A joiner must not build its own squad (CTPlayer.Possess would pull every AI commando into it)
// and must stay out of Boss's squad so the squad AI never orders it.
function Possess(Pawn APawn)
{
	if(CoopSlot < 0)
	{
		Super.Possess(APawn);
		return;
	}

	Super(PlayerController).Possess(APawn);
	APawn.bCanPickupInventory = true;

	if(APawn.Squad != None)
		APawn.Squad.RemoveFromSquad(APawn);

	if(APawn.bIncapacitated)
		GotoState('CtrlIncapacitated');
}

// Runs on the owning client so the menu opens on that player's own console with its text filled in.
// SetPause is refused by CoopGame (bPauseable=False), so nobody freezes the session.
simulated function ClientShowMenu(string MenuClass, string Title, string Text, string PicName, string NewLevel, bool bIsForHintText)
{
	if(!bIsForHintText || bKeepHintMenusAwfulHack)
		ShowMenu(MenuClass, Title, Text, PicName, NewLevel);
}

defaultproperties
{
	CoopSlot=-1
}
