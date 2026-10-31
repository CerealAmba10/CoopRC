// Scripted self-test, spawned by CoopGame when the host URL has ?CoopTest=1.
// Needs one joiner. Logs "CoopTest: PASS/FAIL <step>" to the host log.
// Steps: joiner dies -> respawns near a teammate; joiner is moved far away -> caught up;
// everyone dies -> map restarts and the joiner comes back.
class CoopTest extends Info;

var CoopGame Game;
var CoopPlayer Joiner;
var Pawn OldPawn;
var int Step;
var int Mode; // 1 = respawn/catch-up/wipe, 2 = level travel, 3 = spin the joiner's view, 7 = squad orders,
              // 9 = joiner places and fires the geo_01a demolition charge
var int Spin;
var float StepTime;

function PostBeginPlay()
{
	Game = CoopGame(Level.Game);
	SetTimer(1.0, true);
}

function CoopPlayer FindJoiner()
{
	local Controller C;

	for(C = Level.ControllerList; C != None; C = C.NextController)
	{
		if(CoopPlayer(C) != None && CoopPlayer(C).CoopSlot >= 0)
			return CoopPlayer(C);
	}

	return None;
}

function Kill(Pawn P)
{
	if(P == None)
		return;

	P.bCannotDie = false;
	P.Died(None, class'DamageType', P.Location);
}

// Mode 2: wait for the map's relays, then put Boss on the level exit; the next map's log should show
// the joiner logging in again with the same slot.
function TravelTest()
{
	local Teleporter T;
	local Controller C;

	ForEach AllActors(class'Teleporter', T)
	{
		if(InStr(T.URL, "#") >= 0 || InStr(T.URL, "/") >= 0)
			break;
	}

	if(T == None)
		return;

	if(Step == 0 && StepTime >= 30)
	{
		for(C = Level.ControllerList; C != None; C = C.NextController)
		{
			if(CoopPlayer(C) != None && CoopPlayer(C).CoopSlot < 0 && C.Pawn != None)
			{
				Log("CoopTest: moving Boss alone onto exit" @ T.URL);
				C.Pawn.SetLocation(T.Location);
				Step++;
				StepTime = 0;
			}
		}
	}
	else if(Step == 1 && StepTime >= 6)
	{
		// Still here: the exit waited for the joiner.
		Result(true, "exit waits for the squad");
		Log("CoopTest: moving joiner onto exit");
		Joiner.Pawn.SetLocation(T.Location + vect(150, 0, 0));
		Step++;
	}
}

// Same aim as the joiner's, done by Boss on the host, to compare what the targeting code returns.
function HostAimTest(Actor D, vector From)
{
	local CoopPlayer Host;
	local PlayerController.ETargetType T;
	local int i;

	Host = CoopPlayer(Level.GetLocalPlayerController());

	if(Host == None || Host.Pawn == None || !Host.Pawn.SetLocation(From))
		return;

	for(i = 0; i < 6; i++)
	{
		Host.SetRotation(rotator(D.Location + vect(0,0,8) * i - (Host.Pawn.Location + Host.Pawn.EyePosition())));
		T = Host.SelectTargetType();
		Log("CoopTest: host aim" @ i @ "->" @ Host.Target @ T @ "marker" @ Host.TargetMarker);
	}
}

// Mode 9: the joiner uses the squad-only tutorial item of geo_01a (bunker charge, then its plunger),
// geo_01b (shield terminal) or geo_01c (breach door), pressing Use on their own machine
// (CoopPlayer.ClientTestUse) so the real client path runs: client targeting, the forwarded Use, the
// server-side hold. Logs the item's state as it goes.
function SquadItemTest()
{
	local ActivateItem D;
	local string Map;
	local name ItemTag;
	local int i;

	Map = Left(string(Level), InStr(string(Level), "."));
	if(Map ~= "geo_01a")
		ItemTag = 'DemolitionCharge';
	else if(Map ~= "geo_01b")
		ItemTag = 'HackTerminalEntrance';
	else
		ItemTag = 'BreachDoorSunFac';

	ForEach AllActors(class'ActivateItem', D, ItemTag)
		break;

	if(D == None || Joiner.Pawn == None)
		return;

	if(int(StepTime) % 5 == 0)
		Log("CoopTest: t=" $ int(StepTime) @ "step" @ Step @ D @ D.GetStateName() @ "usable" @ D.bIsUsable @ "user" @ D.User @ "joiner (server view) target" @ Joiner.Target @ Joiner.TargetType);

	if(Step == 0 && StepTime >= 10 && StepTime < 11) // reach the meet-up, as if we'd walked there
	{
		if(ItemTag == 'DemolitionCharge')
			TriggerEvent('ActivateDemoCharge', self, None);
		else if(D.IsInState('Disabled'))
			D.GotoState('Standby');
	}

	if(Step == 0 && StepTime >= 12 && D.bIsUsable)
	{
		// Where the level says a user stands (NavPtLocs: in front of the item, facing it); else around it.
		if(!Joiner.Pawn.SetLocation(D.Location + (vect(85,0,0) >> D.Rotation) + vect(0,0,40)))
			for(i = 0; i < 16 && !Joiner.Pawn.SetLocation(D.Location + 110 * vector(rot(0,1,0) * (i * 4096)) + vect(0,0,40)); i++);
		Joiner.ClientSetLocation(Joiner.Pawn.Location, rotator(D.Location - Joiner.Pawn.Location));
		HostAimTest(D, Joiner.Pawn.Location + vect(0,40,0));
		Log("CoopTest: joiner moved next to" @ D @ "state" @ D.GetStateName() @ "dist" @ VSize(Joiner.Pawn.Location - D.Location));
		Step = 1;
		StepTime = 0;
	}
	else if(Step == 1 && StepTime >= 3)
	{
		Joiner.ClientTestUse(true, D.Location);
		Step = 2;
		StepTime = 0;
	}
	else if(Step == 2 && ((StepTime > 2 && !D.bActivating) || StepTime > 25))
	{
		Joiner.ClientTestUse(false, D.Location);
		Log("CoopTest: after holding Use" @ StepTime @ "s:" @ D @ D.GetStateName());
		Step = 3;
		StepTime = 0;
	}
	else if(Step == 3 && StepTime >= 3 && ItemTag == 'DemolitionCharge')
	{
		Joiner.ClientTestUse(true, D.Location); // plunger
		Step = 4;
		StepTime = 0;
	}
	else if(Step == 4 && StepTime >= 6)
	{
		Joiner.ClientTestUse(false, D.Location);
		Log("CoopTest: after plunger:" @ D.GetStateName());
		Step = 5;
	}
}

// Mode 7: every squad order from Boss and from the joiner, with AI squadmates and then with none.
// A crash shows up as the host log stopping before "PASS squad orders".
function OrdersTest()
{
	local PlayerController Host;
	local Pawn P;
	local SquadMarker M, Near;
	local int i, Count;

	if(StepTime < 2)
		return;

	StepTime = 0;
	Host = Level.GetLocalPlayerController();

	if(Host.Pawn == None)
		return;

	if(Mode == 8 && Step != 0 && Step != 16 && Step != 25) // 8: same timeline, but only empty the squad
	{
		Step++;
		return;
	}

	if(Step == 0)
		Log("CoopTest: Boss squad" @ Host.Pawn.Squad @ "alive members" @ Host.Pawn.Squad.CountAliveMembers());
	else if((Step >= 1 && Step <= 7) || (Step >= 17 && Step <= 23))
	{
		i = (Step - 1) % 16;
		Log("CoopTest: host order" @ i);
		CoopPlayer(Host).RunSquadOrder(i);
	}
	else if(Step == 8 || Step == 24)
	{
		// What a player can do: use the one active marker they're looking at (here the nearest).
		ForEach AllActors(class'SquadMarker', M)
		{
			if(M.bMarkerActive && M.bValidSetup && M.CurrentMarkerAction() != MA_None
				&& (Near == None || VSize(M.Location - Host.Pawn.Location) < VSize(Near.Location - Host.Pawn.Location)))
				Near = M;
			Count++;
		}
		Log("CoopTest: nearest usable marker" @ Near @ "of" @ Count);
		if(Near != None)
			Log("CoopTest: marker executed ->" @ Near.ExecuteMarker(Host.Pawn));
	}
	else if(Step >= 9 && Step <= 15)
	{
		Log("CoopTest: joiner order" @ Step - 9);
		Joiner.ClientTestSquadOrder(Step - 9);
	}
	else if(Step == 16)
	{
		ForEach DynamicActors(class'Pawn', P)
		{
			if(P != Host.Pawn && P.Squad != None && P.Squad == Host.Pawn.Squad)
			{
				P.Squad.RemoveFromSquad(P);
				Count++;
			}
		}
		Log("CoopTest: removed" @ Count @ "AI from Boss's squad, alive members now" @ Host.Pawn.Squad.CountAliveMembers());
	}
	else if(Step == 25)
		Log("CoopTest: PASS squad orders (host and joiner still running)");

	Step++;
}

function AimAtNextNPC()
{
	local Pawn P;
	local int i;

	if(Joiner.Pawn == None)
		return;

	ForEach VisibleCollidingActors(class'Pawn', P, 4000, Joiner.Pawn.Location)
	{
		if(P == Joiner.Pawn || P.Health <= 0 || PlayerController(P.Controller) != None)
			continue;

		if(i++ == Spin)
		{
			Joiner.ClientSetRotation(rotator(P.Location - Joiner.Pawn.Location));
			Spin++;
			Log("CoopTest: joiner aiming at" @ P);
			return;
		}
	}

	Spin = 0; // wrap around
}

function bool NearExit(Actor A)
{
	local Teleporter T;

	ForEach AllActors(class'Teleporter', T)
	{
		if(VSize(T.Location - A.Location) < 1500)
			return true;
	}

	return A.IsA('Teleporter');
}

function Result(bool bPass, string What)
{
	if(bPass)
		Log("CoopTest: PASS" @ What);
	else
		Log("CoopTest: FAIL" @ What);
}

function Timer()
{
	local NavigationPoint N, Far;
	local Controller C;

	StepTime += 1.0;

	if(Joiner == None)
	{
		Joiner = FindJoiner();
		StepTime = 0;

		if(Joiner != None)
			Log("CoopTest: joiner found" @ Joiner.PlayerReplicationInfo.PlayerName);

		return;
	}

	if(Mode == 2)
	{
		TravelTest();
		return;
	}

	if(Mode == 13) // like 12 over a laggy connection, and the first joiner dies once
	{
		if(Step == 0)
		{
			Log("CoopTest: server lag ->" @ Level.GetLocalPlayerController().ConsoleCommand("PKTLAG 250")
				@ Level.GetLocalPlayerController().ConsoleCommand("PKTLOSS 5"));
			Step = 1;
		}
		if(Step == 1 && StepTime >= 60 && Joiner.Pawn != None)
		{
			Log("CoopTest: killing" @ Joiner.CoopSlot);
			Kill(Joiner.Pawn);
			Step = 2;
		}
	}

	if(Mode == 12 || Mode == 13) // idle: just play the level, reporting every player's state
	{
		if(int(StepTime) % 10 == 0)
			for(C = Level.ControllerList; C != None; C = C.NextController)
				if(CoopPlayer(C) != None)
					Log("CoopTest: player slot" @ CoopPlayer(C).CoopSlot @ "state" @ C.GetStateName() @ "pawn" @ C.Pawn
						@ "class" @ C.Pawn.Class @ "weapon" @ C.Pawn.Weapon @ "pending" @ C.Pawn.PendingWeapon @ "inv" @ C.Pawn.Inventory
						@ "view" @ CoopPlayer(C).ViewTarget @ "health" @ C.Pawn.Health);
		return;
	}

	if(Mode == 10 || Mode == 11) // lobby, as if the host picked a level from the Campaign Map (10: the drop, 11: geo_03a)
	{
		if(StepTime >= 25 && Step == 0 && CoopLobby(Game) != None)
		{
			Step++;
			if(Mode == 10)
				Level.GetLocalPlayerController().ConsoleCommand("open GEO_01Briefing");
			else
				Level.GetLocalPlayerController().ConsoleCommand("open geo_03a");
		}
		return;
	}

	if(Mode >= 4 && Mode <= 6) // lobby: once the joiners are in, start New Game like the host's menu does
	{                         // (5: skip to geo_01a, 6: start at the Geonosis briefing that follows the prologue)
		if(StepTime >= 25 && Step == 0 && CoopLobby(Game) != None)
		{
			Step++;
			if(Mode == 5)
				Game.StartCoop("geo_01a");
			else if(Mode == 6)
				Game.StartCoop("geo_01briefing");
			else
				Game.StartCoop("PRO");
		}
		return;
	}

	if(Mode == 9)
	{
		SquadItemTest();
		return;
	}

	if(Mode == 7 || Mode == 8)
	{
		OrdersTest();
		return;
	}

	if(Mode == 3) // aim the joiner straight at each nearby NPC in turn (targeting crash)
	{
		AimAtNextNPC();
		return;
	}

	switch(Step)
	{
	case 0: // let the joiner settle, then kill them
		if(StepTime < 8)
			return;

		OldPawn = Joiner.Pawn;
		Kill(Joiner.Pawn);
		Step++;
		StepTime = 0;
		return;

	case 1: // respawned with a new pawn near someone
		if(StepTime < Game.RespawnDelay + 3)
			return;

		Result(Joiner.Pawn != None && Joiner.Pawn != OldPawn && Joiner.Pawn.Health > 0 &&
		       Game.NearestTeammate(Joiner) != None &&
		       VSize(Game.NearestTeammate(Joiner).Location - Joiner.Pawn.Location) < 400, "respawn next to teammate");
		Result(Joiner.Pawn != None && Joiner.Pawn.FindInventoryType(class<Inventory>(DynamicLoadObject("CTInventory.DC15s", class'Class'))) != None, "joiner has DC-15s");

		// Move the joiner to the farthest navigation point that isn't a level exit.
		ForEach AllActors(class'NavigationPoint', N)
		{
			if(NearExit(N))
				continue;

			if(Far == None || VSize(N.Location - Joiner.Pawn.Location) > VSize(Far.Location - Joiner.Pawn.Location))
				Far = N;
		}

		if(Far != None)
			Joiner.Pawn.SetLocation(Far.Location + vect(0, 0, 60));

		Log("CoopTest: moved joiner" @ VSize(Game.NearestTeammate(Joiner).Location - Joiner.Pawn.Location) @ "units away");
		Step++;
		StepTime = 0;
		return;

	case 2: // caught up after LeashTime
		if(StepTime < Game.LeashTime + 3)
			return;

		Result(VSize(Game.NearestTeammate(Joiner).Location - Joiner.Pawn.Location) < 400, "catch-up to teammate");

		for(C = Level.ControllerList; C != None; C = C.NextController)
		{
			if(CoopPlayer(C) != None)
				Kill(C.Pawn);
		}

		Log("CoopTest: killed everyone, expecting a map restart");
		Step++;
		return;
	}
}

defaultproperties
{
	RemoteRole=ROLE_None
}
