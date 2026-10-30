// Gives clients the editor scale of one replicated map actor. Clients delete their map copy of
// non-static actors at load and get a fresh replicated one, but DrawScale3D isn't replicated, so props
// resized in the editor arrive at 1x1x1 (e.g. the window in front of Sun Fac's room in geo_01c).
// Spawned by CoopGame.FixReplicatedScales; keeps re-applying on the client until the target exists.
class CoopScaleFix extends Info;

var Actor  Target;
var vector Scale3D;

replication
{
	reliable if(Role == ROLE_Authority)
		Target, Scale3D;
}

simulated function Tick(float Delta)
{
	if(Role == ROLE_Authority)
	{
		if(Target == None || Target.bDeleteMe)
			Destroy();

		return;
	}

	if(Target != None && Target.DrawScale3D != Scale3D)
		Target.SetDrawScale3D(Scale3D);
}

defaultproperties
{
	RemoteRole=ROLE_SimulatedProxy
	bAlwaysRelevant=True
	bHidden=True
}
