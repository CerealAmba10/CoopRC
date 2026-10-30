// Fires a progression event that a removed AI commando's map script would have fired.
// Spawned by CoopGame from its MapFixes table, one per entry for the current map. Listens for OnEvent
// (via Tag) and, if the slot is played by a human, fires Fire after Delay. If the slot is claimed only
// after OnEvent already happened, CoopGame calls SlotClaimed and it fires then. Fires at most once, and
// not at all if the event already happened (e.g. the AI double fired it before the player took over).
class CoopEventRelay extends Info;

var int   Slot;
var name  Fire;
var float Delay;
var bool  bTriggered, bFired;

function PostBeginPlay()
{
	SetTimer(0.01, false); // Fire is set right after Spawn; hook the "already happened" listener next tick
}

function Trigger(Actor Other, Pawn EventInstigator)
{
	bTriggered = true;

	if(CoopGame(Level.Game).SlotOwner[Slot] != None && CoopGame(Level.Game).SlotClaimed[Slot] != 0)
		Schedule();
}

function SlotClaimed()
{
	if(bTriggered)
		Schedule();
}

function Schedule()
{
	if(bFired)
		return;

	bFired = true;
	SetTimer(FMax(Delay, 0.05), false);
}

function Timer()
{
	local CoopEventSeen Seen;

	if(Fire == '')
		return;

	if(!bFired) // first timer: start listening for the event itself
	{
		Seen = Spawn(class'CoopEventSeen', self, Fire);
		return;
	}

	Log("CoopRC: relay" @ Tag @ "->" @ Fire @ "for human slot" @ Slot);
	TriggerEvent(Fire, self, None);
}

defaultproperties
{
	RemoteRole=ROLE_None
}
