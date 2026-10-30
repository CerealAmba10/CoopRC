// Tells its CoopEventRelay (Owner) that the relay's event already happened, so it isn't fired twice.
class CoopEventSeen extends Info;

function Trigger(Actor Other, Pawn EventInstigator)
{
	if(CoopEventRelay(Owner) != None && Other != Owner)
		CoopEventRelay(Owner).bFired = true;
}

defaultproperties
{
	RemoteRole=ROLE_None
}
