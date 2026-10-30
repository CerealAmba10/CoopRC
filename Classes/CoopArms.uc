// First-person arms that match each Delta's armour. Only Boss has arms in the game; the 07/40/62
// textures are recoloured from his on each player's PC by Build-Arms.ps1 (into CoopRCArms.u), so no
// game-derived art ships with CoopRC. Shaders are copies of Boss's HudArms_Shader with only the
// diffuse texture swapped, so bump/specular look identical. Without CoopRCArms.u the arms stay default.
class CoopArms extends Object;

#exec OBJ LOAD FILE="CloneTextures.utx"
#exec OBJ LOAD FILE="HudArmsTextures.utx"

var Material Body[3];        // armour shader on the pawn (Skins[0])
var string   ArmsDiffuse[3]; // texture in CoopRCArms.u
var Shader   ArmsShader[3];  // built on first use

function Material ArmsFor(Material PawnSkin)
{
	local Material Diffuse;
	local int i;

	for(i = 0; i < ArrayCount(Body); ++i)
	{
		if(PawnSkin == Body[i])
		{
			if(ArmsDiffuse[i] != "") // only try loading once
			{
				Diffuse = Material(DynamicLoadObject(ArmsDiffuse[i], class'Texture', true));
				ArmsDiffuse[i] = "";

				if(Diffuse != None)
					ArmsShader[i] = CopyShader(Shader'HudArmsTextures.HudArms.HudArms_Shader', Diffuse);
			}

			return ArmsShader[i];
		}
	}

	return None; // Boss or unknown armour: keep the weapon's own arms
}

function Shader CopyShader(Shader Src, Material NewDiffuse)
{
	local Shader S;

	S = new class'Shader';
	S.Diffuse = NewDiffuse;
	S.Opacity = Src.Opacity;
	S.Specular = Src.Specular;
	S.SpecularityMask = Src.SpecularityMask;
	S.SelfIllumination = Src.SelfIllumination;
	S.SelfIlluminationMask = Src.SelfIlluminationMask;
	S.Detail = Src.Detail;
	S.DetailScale = Src.DetailScale;
	S.Bumpmap = Src.Bumpmap;
	S.DiffuseEnvMap = Src.DiffuseEnvMap;
	S.BumpMapType = Src.BumpMapType;
	S.BumpSize = Src.BumpSize;
	S.BumpUVScale = Src.BumpUVScale;
	S.DiffuseStrength = Src.DiffuseStrength;
	S.DiffuseMaskStrength = Src.DiffuseMaskStrength;
	S.SpecularSharpness = Src.SpecularSharpness;
	S.SpecularStrength = Src.SpecularStrength;
	S.SpecularMaskStrength = Src.SpecularMaskStrength;
	S.SpecularInTheDark = Src.SpecularInTheDark;
	S.SpecularBumpX2 = Src.SpecularBumpX2;
	S.UseTinting = Src.UseTinting;
	S.DiffuseColorAdd = Src.DiffuseColorAdd;
	S.DiffuseColorMultiplyX2 = Src.DiffuseColorMultiplyX2;
	S.SpecularColorAdd = Src.SpecularColorAdd;
	S.SpecularColorMultiplyX2 = Src.SpecularColorMultiplyX2;
	S.bInvertCubemap = Src.bInvertCubemap;
	S.OutputBlending = Src.OutputBlending;
	S.TwoSided = Src.TwoSided;
	S.ModulateStaticLighting2X = Src.ModulateStaticLighting2X;
	S.PerformLightingOnSpecularPass = Src.PerformLightingOnSpecularPass;
	S.FallbackMaterial = Src.FallbackMaterial;

	return S;
}

defaultproperties
{
	Body(0)=Shader'CloneTextures.CloneTextures.CloneCommando07_Shader'
	Body(1)=Shader'CloneTextures.CloneTextures.CloneCommando40_Shader'
	Body(2)=Shader'CloneTextures.CloneTextures.CloneCommando62_Shader'
	ArmsDiffuse(0)="CoopRCArms.HudArms07"
	ArmsDiffuse(1)="CoopRCArms.HudArms40"
	ArmsDiffuse(2)="CoopRCArms.HudArms62"
}
