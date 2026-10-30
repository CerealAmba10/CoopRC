# Package CoopRC for players: out\CoopRC-<version>.zip containing a CoopRC folder with the compiled
# package, installer, launchers and README. Build first with build.ps1.
# -Publish also creates GitHub release v<Version> with the zip and setup exe (players update with Update-CoopRC.bat).
param([string]$Version = "0.1", [switch]$Publish)

$root = $PSScriptRoot
$pkg = Join-Path $root "..\..\GameData\System\CoopRC.u"
if (-not (Test-Path $pkg)) { throw "CoopRC.u not found, run build.ps1 first" }

$stage = Join-Path $root "out\CoopRC"
Remove-Item (Join-Path $root "out") -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force "$stage\System" | Out-Null

Copy-Item $pkg "$stage\System\CoopRC.u"
Copy-Item "$root\Dist\*" $stage
Set-Content "$stage\VERSION.txt" $Version -Encoding ASCII
New-Item -ItemType Directory -Force "$stage\Source" | Out-Null
Copy-Item "$root\Classes" "$stage\Source\Classes" -Recurse
Copy-Item "$root\Tools\paint_arms.py" "$stage\Source\"

# Steam relay (self-contained, so players don't need .NET). Publish it first if missing:
#   dotnet publish Relay -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true -o Relay\bin\publish
$relay = "$root\Relay\bin\publish"
if (-not (Test-Path "$relay\CoopRelay.exe")) { throw "Relay not published (see comment above)" }
New-Item -ItemType Directory -Force "$stage\Relay", "$stage\Source\Relay" | Out-Null
Copy-Item "$relay\CoopRelay.exe", "$relay\steam_api64.dll", "$relay\steam_appid.txt" "$stage\Relay\"
Copy-Item "$root\Relay\lib\Steamworks.NET-LICENSE.txt" "$stage\Relay\"
Copy-Item "$root\Relay\Program.cs", "$root\Relay\CoopRelay.csproj" "$stage\Source\Relay\"

$zip = Join-Path $root "out\CoopRC-$Version.zip"
Compress-Archive -Path $stage -DestinationPath $zip -Force

# Setup exe: the zip embedded in a small installer, compiled with the .NET Framework csc every Windows has.
$csc = "$env:WINDIR\Microsoft.NET\Framework64\v4.0.30319\csc.exe"
$exe = Join-Path $root "out\CoopRC-Setup-$Version.exe"
& $csc /nologo /target:winexe /out:$exe "/resource:$zip,CoopRC.zip" /r:System.IO.Compression.dll /r:System.IO.Compression.FileSystem.dll /r:System.Windows.Forms.dll "$root\Installer\Setup.cs"
if ($LASTEXITCODE) { throw "csc failed" }
Get-Item $zip, $exe | Select-Object Name, Length

if ($Publish) {
	gh release create "v$Version" $zip $exe --title "CoopRC $Version" --generate-notes
	if ($LASTEXITCODE) { throw "gh release create failed" }
}
