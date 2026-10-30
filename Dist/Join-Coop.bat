@echo off
rem Join a co-op game.
rem   Join-Coop.bat [07^|40^|62]                    then right-click the host in Steam > Join Game (or accept their invite)
rem   Join-Coop.bat <host Steam ID> [07^|40^|62]    through Steam by ID (no port forwarding; needs Steam running)
rem   Join-Coop.bat <host IP address> [07^|40^|62]  direct (LAN, VPN, or a forwarded UDP 7777)
rem   07 = Sev, 40 = Fixer, 62 = Scorch. Leave it out to take the next free commando.
setlocal
set HOST=%1
set SLOT=%2
if "%GAME%"=="" set GAME=%~dp0..
if not exist "%GAME%\GameData\System\CT.exe" (echo Set GAME to your Star Wars Republic Commando folder & pause & exit /b 1)

rem An IP address contains a dot; a Steam ID or a slot is just digits (the relay tells them apart).
echo %HOST% | find "." >nul
if errorlevel 1 (
	start "CoopRC Steam relay - keep open while playing" "%~dp0Relay\CoopRelay.exe" join %HOST% %SLOT%
	exit /b 0
)

cd /d "%GAME%\GameData\System"
if "%SLOT%"=="" (start "" CT.exe "%HOST%") else (start "" CT.exe "%HOST%?CoopSlot=%SLOT%")
