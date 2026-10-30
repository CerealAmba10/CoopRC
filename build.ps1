# Rebuild CoopRC.u. UCC hangs on exit after a failed compile, so it gets a timeout.
$sys = Join-Path $PSScriptRoot "..\..\GameData\System"
Remove-Item "$sys\CoopRC.u" -ErrorAction SilentlyContinue
$p = Start-Process "$sys\UCC.exe" -ArgumentList 'make' -WorkingDirectory $sys -PassThru -WindowStyle Hidden
if (-not $p.WaitForExit(120000)) { Stop-Process -Id $p.Id -Force }
Get-Content "$sys\UCC.log" | Select-String '^(Error|.*Error,|.*Warning,|Log: (Success|Failure))' | ForEach-Object { $_.Line }
if (-not (Test-Path "$sys\CoopRC.u")) { exit 1 }
