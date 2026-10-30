# Co-op test on one PC: host with ?CoopTest=<Mode>, one client per slot in -Slot (e.g. -Slot 07,40).
# Prints the CoopRC/CoopTest lines from all logs. Usage: run-test.ps1 -Map geo_01c -Mode 2 -Slot 07 -Seconds 120
# Lobby modes (4-6): -Map MPCustom -Game CoopRC.CoopLobby
param([string]$Map = "geo_01a", [int]$Mode = 1, [string[]]$Slot = @("62"), [int]$Seconds = 120, [string]$Shot = "", [string]$Game = "CoopRC.CoopGame")

$sys = Join-Path $PSScriptRoot "..\..\..\GameData\System"
$h = Start-Process "$sys\CT.exe" -ArgumentList "${Map}?Listen?game=${Game}?CoopTest=${Mode}", "LOG=coop_host.log", "-windowed" -WorkingDirectory $sys -PassThru
Start-Sleep 25
$cs = for ($i = 0; $i -lt $Slot.Count; $i++) {
	Start-Process "$sys\CT.exe" -ArgumentList "127.0.0.1?CoopSlot=$($Slot[$i])", "LOG=coop_client$i.log", "-windowed" -WorkingDirectory $sys -PassThru
	Start-Sleep 5
}
Start-Sleep $Seconds
if ($Shot) { & "$PSScriptRoot\winshot.ps1" $cs[0].Id $Shot }
"alive: host=$(!$h.HasExited) clients=$(($cs | ForEach-Object { !$_.HasExited }) -join ',')"
$cs | ForEach-Object { $_.CloseMainWindow() | Out-Null }; Start-Sleep 4; $h.CloseMainWindow() | Out-Null; Start-Sleep 6
Get-Process CT -ErrorAction SilentlyContinue | Stop-Process -Force
"--- host"
Get-Content "$sys\coop_host.log" | Select-String 'CoopTest|CoopRC: (player|squad|relay|could|.*caught)|LoadMap:|Critical' | ForEach-Object { $_.Line }
for ($i = 0; $i -lt $Slot.Count; $i++) {
	"--- client $($Slot[$i])"
	Get-Content "$sys\coop_client$i.log" | Select-String 'LoadMap:|Critical|Welcomed|CoopRC' | ForEach-Object { $_.Line }
}

