// Player controller for co-op: adds client-side versions of the SP-only screens.
class CoopPlayer extends CTPlayer;

var int CoopSlot; // -1 = host (Boss), otherwise index into CoopGame's slots
var string RequestedSlot;     // ?CoopSlot= from the join URL
var float LobbyMenuTime;      // CoopLobby: when to open the main menu for this player
var float DeadTime, AloneTime; // server-side, see CoopGame.Tick
var Squad LocalSquad;          // client-side only, see PlayerTick


replication
{
	reliable if(Role == ROLE_Authority)
		ClientShowMenu, ClientPlayMovie, ClientStartIntro, ClientLobbyNotice, ClientTestSquadOrder, ClientEnsureProfile;
	reliable if(Role < ROLE_Authority)
		ServerCatchUp;
}

// The targeting/marker code (native, runs on the client every tick) assumes the pawn has a squad.
// Pawn.Squad isn't replicated, so on a client it's always None and looking at a squad marker (e.g. the
// balcony snipe marker in geo_01c) crashes the client. Give the client's own pawn a local squad.
event PlayerTick(float DeltaTime)
{
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
		ClientTargetTick(DeltaTime);
	else
		Super.PlayerTick(DeltaTime);
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
