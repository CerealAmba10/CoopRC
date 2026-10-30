# Builds CoopRCArms.u (first-person arms for Sev, Fixer and Scorch) from YOUR game's own textures.
# Only Boss has first-person arms in the game; this recolours his orange trim to each commando's colour.
# Nothing from the game ships with CoopRC, so this runs on each player's PC. Called by Install-CoopRC.ps1.
param([Parameter(Mandatory)] [string]$GameDir)

$ErrorActionPreference = "Stop"
$sys  = "$GameDir\GameData\System"
$ini  = "$sys\System.ini"
$src  = "$GameDir\Code\CoopRCArms"
$tmp  = Join-Path $env:TEMP "CoopRCArms"

Add-Type -TypeDefinition @'
using System;
using System.IO;

public static class ArmsPainter
{
    static void ToHsv(double r, double g, double b, out double h, out double s, out double v)
    {
        double max = Math.Max(r, Math.Max(g, b)), min = Math.Min(r, Math.Min(g, b)), d = max - min;
        v = max;
        s = max == 0 ? 0 : d / max;
        if (d == 0) { h = 0; return; }
        if (max == r) h = ((g - b) / d) % 6;
        else if (max == g) h = (b - r) / d + 2;
        else h = (r - g) / d + 4;
        h /= 6;
        if (h < 0) h += 1;
    }

    static void ToRgb(double h, double s, double v, out double r, out double g, out double b)
    {
        double i = Math.Floor(h * 6), f = h * 6 - i, p = v * (1 - s), q = v * (1 - f * s), t = v * (1 - (1 - f) * s);
        switch (((int)i) % 6)
        {
            case 0: r = v; g = t; b = p; break;
            case 1: r = q; g = v; b = p; break;
            case 2: r = p; g = v; b = t; break;
            case 3: r = p; g = q; b = v; break;
            case 4: r = t; g = p; b = v; break;
            default: r = v; g = p; b = q; break;
        }
    }

    // Boss's trim (orange, hue 0-40 deg) -> target colour, keeping each pixel's shading.
    // Source/target are the mean trim HSV measured from the body textures (Tools/paint_arms.py).
    // darkWhite: also turn the white armour into Scorch's charcoal panels.
    public static void Paint(string inTga, string outTga, double th, double ts, double tv, bool darkWhite)
    {
        const double SS = 0.7093, SV = 0.5496;            // Boss (38) trim saturation/value; hue is replaced
        const double WV = 0.69;                           // mean value of the white armour on the arms
        const double DH = 0.605, DS = 0.209, DV = 0.242;  // Scorch's dark panels
        byte[] d = File.ReadAllBytes(inTga);
        if (d[2] != 2 || d[16] != 32) throw new Exception("expected an uncompressed 32-bit TGA: " + inTga);
        int start = 18 + d[0];

        for (int i = start; i + 3 < d.Length; i += 4)
        {
            double b = d[i] / 255.0, g = d[i + 1] / 255.0, r = d[i + 2] / 255.0, h, s, v;
            ToHsv(r, g, b, out h, out s, out v);

            if (s > 0.3 && v > 0.2 && h * 360 <= 40)
            {
                ToRgb(th, Math.Min(1, s * ts / SS), Math.Min(1, v * tv / SV), out r, out g, out b);
            }
            else if (darkWhite)
            {
                // Soft mask so dirty, greyish whites blend instead of banding.
                double w = Math.Max(0, Math.Min(1, (v - 0.45) / 0.15)) * Math.Max(0, Math.Min(1, (0.25 - s) / 0.1));
                if (w <= 0) continue;
                double dr, dg, db;
                ToRgb(DH, DS, Math.Min(1, v * DV / WV), out dr, out dg, out db);
                r += (dr - r) * w; g += (dg - g) * w; b += (db - b) * w;
            }
            else continue;

            d[i] = (byte)(b * 255); d[i + 1] = (byte)(g * 255); d[i + 2] = (byte)(r * 255);
        }

        File.WriteAllBytes(outTga, d);
    }
}
'@

# 1. Export Boss's arms from the player's own HudArmsTextures.utx.
Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force $tmp | Out-Null
$p = Start-Process "$sys\UCC.exe" -ArgumentList 'batchexport', '..\Textures\HudArmsTextures.utx', 'texture', 'tga', $tmp -WorkingDirectory $sys -PassThru -WindowStyle Hidden
if (-not $p.WaitForExit(120000)) { Stop-Process -Id $p.Id -Force; throw "UCC batchexport timed out" }
if (-not (Test-Path "$tmp\HudArms.tga")) { throw "Could not export HudArms from HudArmsTextures.utx" }

# 2. Recolour: Sev dark red, Fixer sage green, Scorch yellow with charcoal instead of white.
New-Item -ItemType Directory -Force "$src\Classes", "$src\Textures" | Out-Null
[ArmsPainter]::Paint("$tmp\HudArms.tga", "$src\Textures\HudArms07.tga", 0.986, 0.562, 0.305, $false)
[ArmsPainter]::Paint("$tmp\HudArms.tga", "$src\Textures\HudArms40.tga", 0.320, 0.205, 0.314, $false)
[ArmsPainter]::Paint("$tmp\HudArms.tga", "$src\Textures\HudArms62.tga", 0.105, 0.781, 0.653, $true)

# 3. Compile them into CoopRCArms.u (temporarily registered so 'ucc make' builds it).
Set-Content "$src\Classes\CoopRCArms.uc" -Encoding ASCII -Value @'
class CoopRCArms extends Object;

#exec TEXTURE IMPORT NAME=HudArms07 FILE=Textures\HudArms07.tga MIPS=1 DXT=5
#exec TEXTURE IMPORT NAME=HudArms40 FILE=Textures\HudArms40.tga MIPS=1 DXT=5
#exec TEXTURE IMPORT NAME=HudArms62 FILE=Textures\HudArms62.tga MIPS=1 DXT=5
'@

$original = Get-Content $ini -Raw
try {
	Set-Content $ini ($original -replace '(?m)^(EditPackages\+=XInterfaceGamespy\r?\n)', "`$1EditPackages+=CoopRCArms`r`n") -NoNewline -Encoding ASCII
	Remove-Item "$sys\CoopRCArms.u" -ErrorAction SilentlyContinue
	$p = Start-Process "$sys\UCC.exe" -ArgumentList 'make' -WorkingDirectory $sys -PassThru -WindowStyle Hidden
	if (-not $p.WaitForExit(180000)) { Stop-Process -Id $p.Id -Force }
}
finally {
	Set-Content $ini $original -NoNewline -Encoding ASCII
	Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

if (-not (Test-Path "$sys\CoopRCArms.u")) { throw "Building CoopRCArms.u failed, see $sys\UCC.log" }
Write-Host "Built CoopRCArms.u (Sev/Fixer/Scorch first-person arms)"

