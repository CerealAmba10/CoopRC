// Client-side stand-in for a map prop that can't replicate (a static-class actor made movable in the
// editor, e.g. the glass in front of Sun Fac's room in geo_01c). The original stays server-only (see
// CoopGame.KeepUnreplicableActorsOnServer); this copies its mesh, placement and skin to clients and
// follows it when it is hidden, moved or destroyed. Owned by the host's PlayerController with
// bOwnerNoSee, so the host (who still has the original) doesn't see it twice.
class CoopMeshProxy extends Actor;

var Actor Original;
var vector RepScale3D; // DrawScale3D isn't replicated by the engine

replication
{
	reliable if(Role == ROLE_Authority)
		RepScale3D;
}

simulated event PostNetReceive()
{
	if(DrawScale3D != RepScale3D)
		SetDrawScale3D(RepScale3D);
}

function Copy(Actor A)
{
	Original = A;
	SetStaticMesh(A.StaticMesh);
	SetDrawScale(A.DrawScale);
	SetDrawScale3D(A.DrawScale3D);
	RepScale3D = A.DrawScale3D;
	SetRotation(A.Rotation);
	Style = A.Style;

	if(A.Skins.Length > 0)
		RepSkin = A.Skins[0];

	bHidden = A.bHidden;
}

function Tick(float Delta)
{
	if(Original == None || Original.bDeleteMe)
	{
		Destroy();
		return;
	}

	if(bHidden != Original.bHidden)
		bHidden = Original.bHidden;

	if(Location != Original.Location)
		SetLocation(Original.Location);

	if(Rotation != Original.Rotation)
		SetRotation(Original.Rotation);
}

defaultproperties
{
	DrawType=DT_StaticMesh
	bNetNotify=True
	bOwnerNoSee=True
	bAlwaysRelevant=True
	RemoteRole=ROLE_DumbProxy
	bCollideActors=False
	bBlockActors=False
	bBlockPlayers=False
	bCollideWorld=False
	bStatic=False
	bNoDelete=False
}
