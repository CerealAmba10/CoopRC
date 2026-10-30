// Scripted self-test, spawned by CoopGame when the host URL has ?CoopTest=1.
// Needs one joiner. Logs "CoopTest: PASS/FAIL <step>" to the host log.
// Steps: joiner dies -> respawns near a teammate; joiner is moved far away -> caught up;
// everyone dies -> map restarts and the joiner comes back.
class CoopTest extends Info;

var CoopGame Game;
var CoopPlayer Joiner;
var Pawn OldPawn;
var int Step;
var int Mode; // 1 = respawn/catch-up/wipe, 2 = level travel, 3 = spin the joiner's view, 7 = squad orders
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
