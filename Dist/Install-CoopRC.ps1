# Installs CoopRC into a Star Wars Republic Commando install. Run from the unzipped CoopRC folder:
#   powershell -ExecutionPolicy Bypass -File Install-CoopRC.ps1 [-GameDir "<...>\Star Wars Republic Commando"] [-Uninstall]
param(
	[string]$GameDir = "",
	[switch]$Uninstall
)

$ErrorActionPreference = "Stop"

if (-not $GameDir) {
	$candidates = @(
		"${env:ProgramFiles(x86)}\Steam\steamapps\common\Star Wars Republic Commando",
		"$PSScriptRoot\.."
	)
	# Steam libraries on other drives
	$vdf = "${env:ProgramFiles(x86)}\Steam\steamapps\libraryfolders.vdf"
	if (Test-Path $vdf) {
		Select-String -Path $vdf -Pattern '"path"\s+"([^"]+)"' | ForEach-Object {
			$candidates += (($_.Matches[0].Groups[1].Value -replace '\\\\', '\') + "\steamapps\common\Star Wars Republic Commando")
		}
	}
	$GameDir = $candidates | Where-Object { Test-Path "$_\GameData\System\System.ini" } | Select-Object -First 1
}

if (-not $GameDir -or -not (Test-Path "$GameDir\GameData\System\System.ini")) {
	throw "Republic Commando not found. Pass -GameDir `"<path>\Star Wars Republic Commando`"."
}

$sys = "$GameDir\GameData\System"
$ini = "$sys\System.ini"
$userIni = "$GameDir\GameData\Save\User.ini"

if ($Uninstall) {
	$text = Get-Content $ini -Raw
	$text = $text -replace '(?m)^Console=CoopRC\.CoopConsole', 'Console=Engine.ExtendedConsole'
	$text = $text -replace '(?m)^ServerPackages\+=CoopRC\r?\n', ''
	Set-Content $ini $text -NoNewline -Encoding ASCII
	Remove-Item "$sys\CoopRC.u", "$sys\CoopRCArms.u" -ErrorAction SilentlyContinue
	Remove-Item "$GameDir\Code\CoopRCArms" -Recurse -Force -ErrorAction SilentlyContinue
	Write-Host "CoopRC removed from $GameDir"
	return
}

# CoopRC needs Republic Commando Fix 2.15+ (FunctionOverride lives in its Mod.u / Mod.dll). If it's missing,
# fetch the official release (it has no license to redistribute, so it isn't bundled) and install it the way
# its README says: everything into GameData\System. The files it replaces are kept as *.before-RCFix.
if (-not (Test-Path "$sys\Mod.dll")) {
	$fixUrl = "https://github.com/SWRC-Modding/CT/releases/download/SWRC_Fix_v2.15/SWRCFix2.15.zip"
	$fixHash = "DA0AFA607B751C17EBEC2E584387C7F440D665F038D66B2F6DDAA2A96A028B53"
	Write-Host "Republic Commando Fix not found, installing 2.15 from github.com/SWRC-Modding/CT..."
	[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
	$fixZip = Join-Path $env:TEMP "SWRCFix2.15.zip"
	Invoke-WebRequest $fixUrl -OutFile $fixZip -UseBasicParsing
	if ((Get-FileHash $fixZip -Algorithm SHA256).Hash -ne $fixHash) {
		Remove-Item $fixZip
		throw "The Republic Commando Fix download didn't match the expected file. Install it by hand: https://github.com/SWRC-Modding/CT/releases"
	}

	Add-Type -AssemblyName System.IO.Compression.FileSystem
	$archive = [IO.Compression.ZipFile]::OpenRead($fixZip)
	try {
		foreach ($e in $archive.Entries | Where-Object { $_.Name -ne "" }) {
			$dest = Join-Path $sys ($e.FullName -replace '/', '\')
			if ((Test-Path $dest) -and -not (Test-Path "$dest.before-RCFix")) { Copy-Item $dest "$dest.before-RCFix" }
			New-Item -ItemType Directory -Force (Split-Path $dest) | Out-Null
			[IO.Compression.ZipFileExtensions]::ExtractToFile($e, $dest, $true)
		}
	}
	finally { $archive.Dispose(); Remove-Item $fixZip }
	Write-Host "Republic Commando Fix 2.15 installed."
}

if (-not (Test-Path "$sys\Mod.dll") -or -not (Test-Path "$sys\CT.exe")) {
	throw "Install Republic Commando Fix 2.15 first: https://github.com/SWRC-Modding/CT/releases"
}

Copy-Item "$PSScriptRoot\System\CoopRC.u" "$sys\CoopRC.u" -Force

$backup = "$ini.before-CoopRC"
if (-not (Test-Path $backup)) { Copy-Item $ini $backup }

$text = Get-Content $ini -Raw
$text = $text -replace '(?m)^Console=Engine\.ExtendedConsole', 'Console=CoopRC.CoopConsole'
if ($text -notmatch '(?m)^ServerPackages\+=CoopRC') {
	$text = $text -replace '(?m)^(ServerPackages\+=VoicePacks\r?\n)', "`$1ServerPackages+=CoopRC`r`n"
}
# Network rates: RC ships with 5-20 KB/s per client and a 20 Hz server tick (tuned for 2005 deathmatch),
# which makes a level full of AI stutter on clients. Both sides need this (client speed caps the rate).
$text = $text -replace '(?m)^ConfiguredInternetSpeed=\d+', 'ConfiguredInternetSpeed=100000'
$text = $text -replace '(?m)^ConfiguredLanSpeed=\d+', 'ConfiguredLanSpeed=100000'
$text = $text -replace '(?m)^MaxClientRate=\d+', 'MaxClientRate=100000'
$text = $text -replace '(?m)^NetServerMaxTickRate=\d+', 'NetServerMaxTickRate=60'
$text = $text -replace '(?m)^LanServerMaxTickRate=\d+', 'LanServerMaxTickRate=60'
Set-Content $ini $text -NoNewline -Encoding ASCII

if ($text -notmatch '(?m)^Console=CoopRC\.CoopConsole' -or $text -notmatch '(?m)^ServerPackages\+=CoopRC') {
	throw "Could not patch $ini (unexpected format). Restore from $backup."
}

# Catch-up key: K, if it isn't bound to anything yet.
if (Test-Path $userIni) {
	$user = Get-Content $userIni -Raw
	if ($user -notmatch '(?m)^K=\S') {
		$user = $user -replace '(?m)^\[Engine\.Input\]\r?\n', "[Engine.Input]`r`nK=CatchUp`r`n"
		Set-Content $userIni $user -NoNewline -Encoding ASCII
	}
}

# Mouse: RC ships with mouse smoothing and acceleration on, which makes aim floaty and inconsistent.
# Every profile has its own User.ini (Save\Profile_*), and new profiles start from the other two.
$userInis = @("$sys\User.ini", $userIni) + (Get-ChildItem "$GameDir\GameData\Save\Profile_*\User.ini" -ErrorAction SilentlyContinue | ForEach-Object FullName)
foreach ($f in $userInis | Where-Object { Test-Path $_ }) {
	$user = Get-Content $f -Raw
	if ($user -notmatch '(?m)^\[Engine\.PlayerInput\]') { $user += "`r`n[Engine.PlayerInput]`r`n" }
	foreach ($key in 'MouseSmoothingMode', 'MouseAccelThreshold') {
		if ($user -match "(?m)^$key=") { $user = $user -replace "(?m)^$key=.*$", "$key=0" }
		else { $user = $user -replace '(?m)^\[Engine\.PlayerInput\]\r?\n', "`$0$key=0`r`n" }
	}
	Set-Content $f $user -NoNewline -Encoding ASCII
}

# Resolution: a fresh install starts at 800x600. Raise it to the monitor's native resolution (RC Fix
# handles widescreen FOV and HUD); a resolution that's already at least native stays.
$screen = Get-CimInstance Win32_VideoController | Where-Object CurrentHorizontalResolution | Select-Object -First 1
if ($screen) {
	$w = $screen.CurrentHorizontalResolution; $h = $screen.CurrentVerticalResolution
	$section = '(?m)(\[WinDrv\.WindowsClient\][^\[]*?^)'
	foreach ($f in @($ini, "$GameDir\GameData\Save\System.ini") | Where-Object { Test-Path $_ }) {
		$text = Get-Content $f -Raw
		if ($text -match "${section}FullscreenViewportX=(\d+)" -and [int]$Matches[2] -lt $w) {
			foreach ($m in 'Fullscreen', 'Windowed') {
				$text = $text -replace "${section}${m}ViewportX=\d+", "`${1}${m}ViewportX=$w"
				$text = $text -replace "${section}${m}ViewportY=\d+", "`${1}${m}ViewportY=$h"
			}
			Set-Content $f $text -NoNewline -Encoding ASCII
			Write-Host "Resolution set to ${w}x${h} in $f"
		}
	}
}

try { & "$PSScriptRoot\Build-Arms.ps1" -GameDir $GameDir }
catch { Write-Warning "Could not build the Sev/Fixer/Scorch arms ($_). Co-op works; everyone keeps Boss's arms." }

Write-Host "CoopRC installed into $GameDir"
Write-Host "System.ini backup: $backup"
