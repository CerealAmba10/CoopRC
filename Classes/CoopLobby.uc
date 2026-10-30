// Main-menu lobby: the host runs a small map (MPCustom) as a listen server with the main menu open,
// so friends can connect before the campaign starts (Host-Coop.bat). Nobody spawns here. When the
// host picks New Game, CoopConsole calls StartCoop and everyone travels into the campaign together,
// keeping their commando slot.
class CoopLobby extends CoopGame;

var float  IntroOpenTime;
var string IntroMap;

function RestartPlayer(Controller aPlayer); // stay in the menu

event PostLogin(PlayerController NewPlayer)
{
	Super.PostLogin(NewPlayer);

	if(CoopPlayer(NewPlayer) != None)
		CoopPlayer(NewPlayer).LobbyMenuTime = Level.TimeSeconds + 2; // menus aren't ready at login

	if(CoopPlayer(NewPlayer) != None && CoopPlayer(NewPlayer).CoopSlot >= 0 && CoopPlayer(Level.GetLocalPlayerController()) != None)
		CoopPlayer(Level.GetLocalPlayerController()).ClientLobbyNotice("", // this box shows one line; no title
			SlotLongName[CoopPlayer(NewPlayer).CoopSlot] @ "joined. Squad" @ (CountJoiners() + 1) $ "/4.");
}

function int CountJoiners()
{
	local Controller C;
	local int N;

	for(C = Level.ControllerList; C != None; C = C.NextController)
		if(CoopPlayer(C) != None && CoopPlayer(C).CoopSlot >= 0)
			N++;

	return N;
}

// New Game: everyone plays the prologue on their own machine (a shared remote cutscene can't stay in
// sync), then the squad links up at Geonosis (CoopConsole.TickIntro, CoopGame "CoopWait").
function StartCoop(string MapName)
{
	local Controller C;
	local CoopPlayer CP;
	local int Joiners;

	for(C = Level.ControllerList; C != None; C = C.NextController)
	{
		CP = CoopPlayer(C);

		if(CP != None && CP.CoopSlot >= 0)
		{
			CP.ClientStartIntro(SlotName[CP.CoopSlot], MapName);
			Joiners++;
		}
	}

	if(CoopConsole(Level.GetLocalPlayerController().Player.Console) != None)
		CoopConsole(Level.GetLocalPlayerController().Player.Console).BeginIntro(true, "", "", Joiners);

	Log("CoopRC: New Game for host +" @ Joiners @ "joiners; link-up at Geonosis");
	IntroMap = MapName;
	IntroOpenTime = Level.TimeSeconds + 2; // let the joiners get their message before the server closes
}

// No respawn/wipe/exit checks in the menu; just open the main menu for new arrivals.
event Tick(float Delta)
{
	local Controller C;
	local CoopPlayer CP;

	if(IntroOpenTime > 0 && Level.TimeSeconds >= IntroOpenTime)
	{
		IntroOpenTime = 0;
		Level.GetLocalPlayerController().ConsoleCommand("start " $ IntroMap); // fresh URL: single player
		return;
	}

	for(C = Level.ControllerList; C != None; C = C.NextController)
	{
		CP = CoopPlayer(C);

		if(CP != None && CP.LobbyMenuTime > 0 && Level.TimeSeconds >= CP.LobbyMenuTime)
		{
			CP.LobbyMenuTime = 0;
			if(CP.CoopSlot >= 0)
				CP.ClientEnsureProfile();
			CP.ClientOpenMenu("XInterfaceCTMenus.CTMenuMain");
			if(CP.CoopSlot >= 0) // a joiner: confirm they made it (one short line fits the box)
				CP.ClientLobbyNotice("", "Connected as" @ SlotLongName[CP.CoopSlot] $ ". Wait for the host.");
		}
	}
}

defaultproperties
{
	bProxiesMade=True
}
