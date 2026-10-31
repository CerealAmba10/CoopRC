// Client-side bootstrap. The console is created at engine startup on every machine, before any map
// loads, so it is the earliest place CoopRC script can install engine fixes.
// Enable with [Engine.Engine] Console=CoopRC.CoopConsole in System.ini.
class CoopConsole extends ExtendedConsole;

var FunctionOverride AIPreBeginPlayOverride;
var FunctionOverride TurretPostBeginPlayOverride;
var FunctionOverride DebriefingOverride;
var FunctionOverride ChangeSquadMemberOverride;
var FunctionOverride TeleporterOverride;
var FunctionOverride TravelOverride;
var FunctionOverride ClientDyingOverride;
var FunctionOverride BriefingOverride;
var FunctionOverride MovieOverride;
var FunctionOverride MovieTickOverride;
var FunctionOverride NewGameOverride;
var FunctionOverride UplinkOverride;
var FunctionOverride MusicOverride, BattleMultiOverride, ForceBattleOverride, SoundMenuOverride, LoadGameOverride, BleedOutOverride;
var CoopArms         Arms;

var bool   bIntroActive, bIntroHost, bReconnecting;
var string IntroHost, IntroSlot;
var int    IntroExpected;
var float  ConsoleTime, ReconnectTime, ReconnectGiveUp;
var string ReunionMap;
var float            ArmsCheckTime;

event Initialized()
{
	Super.Initialized();

	// Placed pawns spawn their AI controller in Pawn.PostBeginPlay without an authority check, so a
	// client would run its own CTBots, which crash in ULocalSituation::Assess. Kill them at spawn.
	AIPreBeginPlayOverride = new class'FunctionOverride';
	AIPreBeginPlayOverride.Init(class'AIController', 'PreBeginPlay', self, 'AIPreBeginPlay');

	// Replicated turrets then run their targeting state code against a None Controller every tick.
	TurretPostBeginPlayOverride = new class'FunctionOverride';
	TurretPostBeginPlayOverride.Init(class'AutoTurret', 'PostBeginPlay', self, 'TurretPostBeginPlay');

	// Hint/bio screens only open for the first CTPlayer; in co-op send them to everyone.
	DebriefingOverride = new class'FunctionOverride';
	DebriefingOverride.Init(class'ACTION_ShowDebriefingScreen', 'InitActionFor', self, 'DebriefingInitActionFor');

	// Meet-up scripts add/remove squad members by tag; leave human-controlled commandos alone.
	ChangeSquadMemberOverride = new class'FunctionOverride';
	ChangeSquadMemberOverride.Init(class'ACTION_ChangeSquadMember', 'InitActionFor', self, 'ChangeSquadMemberInitActionFor');

	// Level exits only move the touching player on a listen server; travel the whole session.
	TeleporterOverride = new class'FunctionOverride';
	TeleporterOverride.Init(class'Teleporter', 'PostTouch', self, 'TeleporterPostTouch');
	// After a level change Boss restores his squad stance; with no AI squadmates travelling along it is
	// None and Squad.SetStance(None) crashes natively.
	TravelOverride = new class'FunctionOverride';
	TravelOverride.Init(class'PlayerCommando', 'TravelPostAccept', self, 'PlayerTravelPostAccept');

	// In network play Pawn.Died also calls Controller.ClientDying for AI pawns (never happens in SP),
	// which plays the death a second time: Dying -> Dying crashes the server natively.
	ClientDyingOverride = new class'FunctionOverride';
	ClientDyingOverride.Init(class'Controller', 'ClientDying', self, 'ControllerClientDying');

	// Briefings (in-level cutscenes) lock "the first PlayerController"; aim them at Boss and let
	// joiners watch. Movies likewise play for everyone.
	BriefingOverride = new class'FunctionOverride';
	BriefingOverride.Init(class'ACTION_Briefing', 'InitActionFor', self, 'BriefingInitActionFor');
	MovieOverride = new class'FunctionOverride';
	MovieOverride.Init(class'ACTION_PlayMovie', 'InitActionFor', self, 'MovieInitActionFor');
	MovieTickOverride = new class'FunctionOverride';
	MovieTickOverride.Init(class'ACTION_PlayMovie', 'StillTicking', self, 'MovieStillTicking');

	// Main menu New Game: the host takes the whole co-op session into the campaign; a joiner waits.
	NewGameOverride = new class'FunctionOverride';
	NewGameOverride.Init(class'CTMenuMain', 'NewGameSelected', self, 'MenuNewGameSelected');

	// The GameSpy uplink turns on CD key checks, and every Steam copy has the same empty key, so the
	// second joiner is kicked as a duplicate (BadCDKey). Co-op servers don't advertise; skip it.
	UplinkOverride = new class'FunctionOverride';
	UplinkOverride.Init(class'MasterServerUplink', 'BeginPlay', self, 'UplinkBeginPlay');

	// Level music is started by scripts on the server, on each PlayerController, so it only ever played
	// on the host. Send it to the joiners too. And the sound menu locks the music slider at 0 in any
	// network game; co-op has music.
	MusicOverride = new class'FunctionOverride';
	MusicOverride.Init(class'ACTION_PlayMusic', 'InitActionFor', self, 'MusicInitActionFor');
	BattleMultiOverride = new class'FunctionOverride';
	BattleMultiOverride.Init(class'ACTION_SetBattleMusicMulti', 'InitActionFor', self, 'BattleMultiInitActionFor');
	ForceBattleOverride = new class'FunctionOverride';
	ForceBattleOverride.Init(class'ACTION_ForceBattleMusic', 'InitActionFor', self, 'ForceBattleInitActionFor');
	// SP bleeds Boss out at once when no AI squadmate can revive him (e.g. geo_01a's start); in co-op a
	// human can, so CoopGame.TickDowned decides when a downed player dies.
	BleedOutOverride = new class'FunctionOverride';
	BleedOutOverride.Init(class'Pawn', 'BleedOut', self, 'PawnBleedOut');

	// Saves are single player only; loading one from the co-op lobby would drop everyone.
	LoadGameOverride = new class'FunctionOverride';
	LoadGameOverride.Init(class'CTMenuMain', 'LoadGameSelected', self, 'MenuLoadGameSelected');
	SoundMenuOverride = new class'FunctionOverride';
	SoundMenuOverride.Init(class'CTSoundOptionsPCMenu', 'Refresh', self, 'SoundMenuRefresh');

	Arms = new class'CoopArms';
	Log("CoopRC: CoopConsole initialized, overrides installed");
}

// Same as ACTION_Briefing.InitActionFor, but always on Boss (the host), then joiners start/stop watching.
function bool BriefingInitActionFor(ScriptedController C)
{
	local ACTION_Briefing A;
	local PlayerController PC;
	local Pawn PCPawn;
	local Inventory Inv;

	A = ACTION_Briefing(BriefingOverride.CurrentSelf);

	if(CoopGame(C.Level.Game) == None)
		return A.InitActionFor(C);

	PC = C.Level.GetLocalPlayerController();

	if(PC != None && PC.Pawn != None)
	{
		PCPawn = PC.Pawn;

		if(A.bEndBriefing)
		{
			PC.GotoState('PlayerWalking');
		}
		else
		{
			PC.bDuck = 0;
			PC.LimitRotation(A.MaxPitch, A.MinPitch, A.MaxYaw, A.MinYaw);

			if(!PC.IsInState('Briefing'))
				PC.GotoState('Briefing');

			if(A.bSetBriefingWeapon)
			{
				Inv = PCPawn.CreateInventory(A.BriefingWeapon);

				if(Weapon(Inv) != None)
					PC.ForceWeaponSwitch(Weapon(Inv).GetInventoryGroup());
			}
			else if(PCPawn.Weapon != None)
			{
				PCPawn.Weapon.GotoState('');
				PCPawn.Disarm();

				if(A.bOkToChangeWeapon)
					PCPawn.ChangedWeapon();
			}
		}

		PC.DrawHUD(A.bDrawHUD);
	}

	CoopGame(C.Level.Game).BriefingChanged(!A.bEndBriefing);
	return false;
}

// Menu music only plays on the Entry map; the co-op lobby is the main menu on MPCustom, so it was silent.
simulated event ManageMenuBackgroundMusic(Menu NewMenu)
{
	local string Map;

	if(ViewportOwner != None && ViewportOwner.Actor != None)
		ViewportOwner.Actor.GetCurrentMapName(Map);

	if(!(Left(Caps(Map), 8) == "MPCUSTOM") || NewMenu == None)
	{
		Super.ManageMenuBackgroundMusic(NewMenu);
		return;
	}

	if(NewMenu.BackgroundMusic != MenuBackgroundMusic)
	{
		if(MenuBackgroundMusic != None)
			StopMenuBackgroundMusic(MenuBackgroundMusic);

		MenuBackgroundMusic = NewMenu.BackgroundMusic;

		if(MenuBackgroundMusic != None)
		{
			StartMenuBackgroundMusic(MenuBackgroundMusic);
			Log("CoopRC: lobby menu music" @ MenuBackgroundMusic @ "playing" @ IsMenuBackgroundMusicPlaying(MenuBackgroundMusic));
		}
	}
}

function bool MusicInitActionFor(ScriptedController C)
{
	local ACTION_PlayMusic A;
	local Controller P;

	A = ACTION_PlayMusic(MusicOverride.CurrentSelf);

	if(CoopGame(C.Level.Game) != None)
		CoopGame(C.Level.Game).CurrentMusic = A.Music;

	for(P = C.Level.ControllerList; P != None; P = P.NextController)
		if(CoopPlayer(P) != None && Viewport(CoopPlayer(P).Player) == None)
			CoopPlayer(P).ClientCoopMusic(A.Music, A.OverrideFadeDefaults, A.FadeInTime, A.FadeInType, A.FadeOutTime, A.FadeOutType);

	return A.InitActionFor(C);
}

function bool BattleMultiInitActionFor(ScriptedController C)
{
	local ACTION_SetBattleMusicMulti A;
	local Controller P;

	A = ACTION_SetBattleMusicMulti(BattleMultiOverride.CurrentSelf);

	for(P = C.Level.ControllerList; P != None; P = P.NextController)
		if(CoopPlayer(P) != None && Viewport(CoopPlayer(P).Player) == None)
			CoopPlayer(P).ClientCoopBattleMusic(A.multiSound, false);

	return A.InitActionFor(C);
}

function bool ForceBattleInitActionFor(ScriptedController C)
{
	local ACTION_ForceBattleMusic A;
	local Controller P;

	A = ACTION_ForceBattleMusic(ForceBattleOverride.CurrentSelf);

	for(P = C.Level.ControllerList; P != None; P = P.NextController)
		if(CoopPlayer(P) != None && Viewport(CoopPlayer(P).Player) == None)
			CoopPlayer(P).ClientCoopBattleMusic(None, true);

	return A.InitActionFor(C);
}

function SoundMenuRefresh()
{
	local CTSoundOptionsPCMenu M;

	M = CTSoundOptionsPCMenu(SoundMenuOverride.CurrentSelf);

	if(CoopPlayer(M.GetPlayerOwner()) != None)
		M.bInMultiplayer = false;

	M.Refresh();
}

function bool MovieInitActionFor(ScriptedController C)
{
	local ACTION_PlayMovie A;
	local PlayerController Host;
	local Controller P;

	A = ACTION_PlayMovie(MovieOverride.CurrentSelf);

	if(CoopGame(C.Level.Game) == None)
		return A.InitActionFor(C);

	Host = C.Level.GetLocalPlayerController();
	C.ScriptedFocus = None;
	C.CurrentAction = A;
	Host.PlayMovie(A.bLooping, A.bInterruptable, A.bPauseLevelMusic, A.bPauseLevelSound, A.MovieName);

	for(P = C.Level.ControllerList; P != None; P = P.NextController)
	{
		if(CoopPlayer(P) != None && P != Host)
			CoopPlayer(P).ClientPlayMovie(A.bLooping, A.bInterruptable, A.bPauseLevelMusic, A.bPauseLevelSound, A.MovieName);
	}

	return A.bWaitForMovieEnd;
}

// The script waits for the host's movie (the original checks "the first CTPlayer").
function bool MovieStillTicking(ScriptedController C, float DeltaTime)
{
	local ACTION_PlayMovie A;

	A = ACTION_PlayMovie(MovieTickOverride.CurrentSelf);

	if(CoopGame(C.Level.Game) == None)
		return A.StillTicking(C, DeltaTime);

	if(!C.Level.GetLocalPlayerController().IsMoviePlaying())
	{
		C.Trigger(None, None);
		return false;
	}

	return true;
}

function MenuNewGameSelected()
{
	local CTMenuMain M;
	local PlayerController PC;

	M = CTMenuMain(NewGameOverride.CurrentSelf);
	PC = M.GetPlayerOwner();

	if(PC != None && CoopGame(PC.Level.Game) != None)
	{
		CoopGame(PC.Level.Game).StartCoop("PRO");
		return;
	}

	if(PC != None && PC.Level.NetMode == NM_Client && CoopPlayer(PC) != None)
	{
		PC.ClientMessage("You're in a co-op session: the host starts the game.");
		return;
	}

	M.NewGameSelected();
}

function PawnBleedOut()
{
	local Pawn P;

	P = Pawn(BleedOutOverride.CurrentSelf);

	if(CoopGame(P.Level.Game) != None && CoopPlayer(P.Controller) != None && CoopGame(P.Level.Game).SomeoneElseUp(P.Controller))
		return;

	P.BleedOut();
}

function MenuLoadGameSelected()
{
	local CTMenuMain M;
	local PlayerController PC;

	M = CTMenuMain(LoadGameOverride.CurrentSelf);
	PC = M.GetPlayerOwner();

	// Co-op progress is the start of the last co-op level (CoopGame.LastCoopMap): continue there together.
	if(CoopLobby(PC.Level.Game) != None)
	{
		if(CoopLobby(PC.Level.Game).LastCoopMap == "")
			CoopPlayer(PC).ClientLobbyNotice("", "No co-op progress yet: use NEW GAME or CAMPAIGN MAP.");
		else
			CoopLobby(PC.Level.Game).StartCoop(CoopLobby(PC.Level.Game).LastCoopMap);
		return;
	}

	if(CoopPlayer(PC) != None && PC.Level.NetMode != NM_Standalone)
	{
		CoopPlayer(PC).ClientLobbyNotice("", "In co-op the host picks the level.");
		return;
	}

	M.LoadGameSelected();
}

function ControllerClientDying(class<DamageType> DamageType, vector HitLocation)
{
	local Controller C;

	C = Controller(ClientDyingOverride.CurrentSelf);

	// Already dying here: playing it again crashes natively (seen for AI and player pawns on the
	// server). Clients still get the death through the pawn's own replication (bTearOff).
	if(C.Pawn != None && C.Pawn.IsInState('Dying'))
		return;

	C.ClientDying(DamageType, HitLocation);
}

function PlayerTravelPostAccept()
{
	local PlayerCommando P;

	P = PlayerCommando(TravelOverride.CurrentSelf);

	if(P.CurrentStance == None)
		P.CurrentStance = class'StanceFormUp';

	P.TravelPostAccept();
}

//=============================================================================
// New Game from the co-op lobby: everyone plays the prologue locally (single player), then the squad
// links up at ReunionMap. This console survives level loads, so it remembers the session.

function BeginIntro(bool bHost, string HostAddress, string Slot, int Expected)
{
	bIntroActive = true;
	bIntroHost = bHost;
	IntroHost = HostAddress;
	IntroSlot = Slot;
	IntroExpected = Expected;
	Log("CoopRC: intro started, host=" $ bHost @ HostAddress @ "slot" @ Slot @ "expected" @ Expected);
}

function TickIntro(float Delta)
{
	local LevelInfo L;
	local string MapName;

	ConsoleTime += Delta;

	if(ViewportOwner == None || ViewportOwner.Actor == None)
		return;

	L = ViewportOwner.Actor.Level;
	MapName = Left(string(L), InStr(string(L), "."));

	// Reached Geonosis on our own: the host turns it into the co-op server, friends connect to it.
	if(bIntroActive && L.NetMode == NM_Standalone && MapName ~= ReunionMap)
	{
		bIntroActive = false;

		if(bIntroHost)
		{
			ConsoleCommand("start " $ ReunionMap $ "?Listen?game=CoopRC.CoopGame?CoopWait=" $ IntroExpected);
			return;
		}

		bReconnecting = true;
		ReconnectGiveUp = ConsoleTime + 600; // the host may load much slower than us
		ReconnectTime = ConsoleTime + 10; // give the host time to leave the lobby and load Geonosis
	}

	// Keep trying until the host's server is up (they may still be in the prologue).
	if(bReconnecting)
	{
		if(L.NetMode == NM_Client && MapName ~= ReunionMap) // on the host's Geonosis server (not an old lobby)
		{
			bReconnecting = false;
		}
		else if(ConsoleTime > ReconnectGiveUp)
		{
			bReconnecting = false;
			Log("CoopRC: gave up reconnecting to" @ IntroHost);
		}
		else if(ConsoleTime >= ReconnectTime)
		{
			ReconnectTime = ConsoleTime + 8;
			Log("CoopRC: linking up with host" @ IntroHost);
			ConsoleCommand("start " $ IntroHost $ "?CoopSlot=" $ IntroSlot);
		}
	}
}

// Keep the local player's first-person arms matching their armour (checked a few times a second,
// which also covers weapon switches and pickups).
event Tick(float Delta)
{
	local Pawn P;
	local Weapon W;
	local Material Want;
	local int Index;

	Super.Tick(Delta);
	TickIntro(Delta);

	ArmsCheckTime -= Delta;

	if(ArmsCheckTime > 0 || ViewportOwner == None || ViewportOwner.Actor == None)
		return;

	ArmsCheckTime = 0.25;
	P = ViewportOwner.Actor.Pawn;

	if(P == None || P.Weapon == None || P.Skins.Length == 0)
		return;

	W = P.Weapon;
	Index = W.HudArmsShaderIndex[0];
	Want = Arms.ArmsFor(P.Skins[0]);

	if(Index < 0 || Want == None)
		return;

	if(W.Skins.Length <= Index)
		W.CopyMaterialsToSkins();

	if(W.Skins.Length > Index && W.Skins[Index] != Want)
		W.Skins[Index] = Want;
}

function bool ChangeSquadMemberInitActionFor(ScriptedController C)
{
	local ACTION_ChangeSquadMember A;
	local Squad Squad;
	local Pawn P;

	A = ACTION_ChangeSquadMember(ChangeSquadMemberOverride.CurrentSelf);

	if(CoopGame(C.Level.Game) == None)
		return A.InitActionFor(C);

	if(A.SquadTag != '')
	{
		ForEach C.AllActors(class'Squad', Squad, A.SquadTag)
			break;
	}

	if(Squad == None && C.Level.GetLocalPlayerController().Pawn != None)
		Squad = C.Level.GetLocalPlayerController().Pawn.Squad;

	if(Squad == None || A.MemberTag == '')
		return false;

	ForEach C.AllActors(class'Pawn', P, A.MemberTag)
	{
		if(PlayerController(P.Controller) != None)
			continue;

		if(P.Squad != None && !A.bAddMember)
			Squad.RemoveFromSquad(P);
		else if(P.Squad == None && A.bAddMember)
			Squad.AddToSquad(P);
	}

	return false;
}

// The exit only fires once the whole squad is there (CoopGame.Tick checks and travels).
function TeleporterPostTouch(Actor Other)
{
	local Teleporter T;

	T = Teleporter(TeleporterOverride.CurrentSelf);

	if(CoopGame(T.Level.Game) == None || T.Level.NetMode != NM_ListenServer ||
	   (InStr(T.URL, "/") < 0 && InStr(T.URL, "#") < 0) ||
	   Pawn(Other) == None || !Pawn(Other).IsHumanControlled())
	{
		T.PostTouch(Other);
		return;
	}

	CoopGame(T.Level.Game).ExitReached(T);
}

// ponytail: client turrets skip their AI states entirely, so they don't animate their search/aim
// locally; rotation still replicates from the server.
function TurretPostBeginPlay()
{
	local AutoTurret T;

	T = AutoTurret(TurretPostBeginPlayOverride.CurrentSelf);
	T.PostBeginPlay();

	if(T.Level.NetMode == NM_Client)
		T.InitialState = 'CoopClientIdle'; // no such state: SetInitialState leaves it stateless
}

function bool DebriefingInitActionFor(ScriptedController C)
{
	local ACTION_ShowDebriefingScreen A;
	local CTPlayer PC;

	A = ACTION_ShowDebriefingScreen(DebriefingOverride.CurrentSelf);

	if(CoopGame(C.Level.Game) == None)
		return A.InitActionFor(C);

	ForEach C.AllActors(class'CTPlayer', PC)
	{
		if(Viewport(PC.Player) == None && CoopPlayer(PC) != None)
			CoopPlayer(PC).ClientShowMenu(A.MenuClass, A.Title, A.Text, A.PicName, A.NewLevel, A.bIsForHintText);
		else if(!A.bIsForHintText || PC.bKeepHintMenusAwfulHack)
			PC.ShowMenu(A.MenuClass, A.Title, A.Text, A.PicName, A.NewLevel);
	}

	return false;
}

// ponytail: re-dispatches virtually; fine while no AIController subclass overrides PreBeginPlay.
function UplinkBeginPlay()
{
	local MasterServerUplink U;

	U = MasterServerUplink(UplinkOverride.CurrentSelf);

	if(CoopGame(U.Level.Game) != None)
	{
		U.Destroy();
		return;
	}

	U.BeginPlay();
}

function AIPreBeginPlay()
{
	local AIController C;

	C = AIController(AIPreBeginPlayOverride.CurrentSelf);

	if(C.Level.NetMode == NM_Client)
	{
		C.Destroy();
		return;
	}

	C.PreBeginPlay();
}

defaultproperties
{
	ReunionMap="geo_01a"
}
