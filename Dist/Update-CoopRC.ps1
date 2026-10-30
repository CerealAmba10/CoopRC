# Updates CoopRC to the latest GitHub release and reinstalls it. Run Update-CoopRC.bat from the CoopRC folder.
param([string]$Repo = "CerealAmba10/CoopRC")

$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

function Done($msg, $color = "Gray") { Write-Host $msg -ForegroundColor $color; Read-Host "Press Enter to close" | Out-Null; exit }

try {
	$here = $PSScriptRoot
	$current = if (Test-Path "$here\VERSION.txt") { (Get-Content "$here\VERSION.txt" -Raw).Trim() } else { "?" }

	$release = Invoke-RestMethod "https://api.github.com/repos/$Repo/releases/latest" -Headers @{ "User-Agent" = "CoopRC-Updater" }
	$latest = $release.tag_name.TrimStart("v")
	$asset = $release.assets | Where-Object { $_.name -like "CoopRC-*.zip" } | Select-Object -First 1

	if (-not $asset) { Done "The latest release ($latest) has no CoopRC zip attached." Yellow }
	if ($latest -eq $current) { Done "CoopRC $current is up to date." Green }

	if (Get-Process CT, CoopRelay -ErrorAction SilentlyContinue) {
		Done "Close Republic Commando and the CoopRC relay window, then run the update again." Yellow
	}

	Write-Host "Updating CoopRC $current -> $latest..."
	$tmp = Join-Path $env:TEMP "CoopRC-update"
	Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
	New-Item -ItemType Directory $tmp | Out-Null
	Invoke-WebRequest $asset.browser_download_url -OutFile "$tmp\CoopRC.zip" -UseBasicParsing
	Expand-Archive "$tmp\CoopRC.zip" $tmp

	# The zip holds a CoopRC folder laid out exactly like this one.
	Copy-Item "$tmp\CoopRC\*" $here -Recurse -Force
	Remove-Item $tmp -Recurse -Force

	& "$here\Install-CoopRC.ps1" -GameDir (Split-Path $here -Parent)
	Done "CoopRC updated to $latest." Green
}
catch {
	Done "Update failed: $_" Red
}
