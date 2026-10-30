@echo off
rem Host a co-op game.
rem   Host-Coop.bat                lobby: friends join from their main menu, then you pick NEW GAME
rem   Host-Coop.bat geo_03a        start straight at a level (map files are in GameData\Maps)
rem   Host-Coop.bat 25565 [map]    listen on another port (one you've forwarded for UDP); friends join with
rem                                Join-Coop.bat <your public IP>:25565 [07^|40^|62]
rem Also starts the Steam relay (needs Steam running) so friends can join through Steam.
setlocal
if "%GAME%"=="" set GAME=%~dp0..
if not exist "%GAME%\GameData\System\CT.exe" (echo Set GAME to your Star Wars Republic Commando folder & pause & exit /b 1)

set PORTARG=
set MAP=%1
echo %1| findstr /r "^[0-9][0-9]*$" >nul && (set PORTARG=PORT=%1& set MAP=%2)

start "CoopRC Steam relay - give friends the Steam ID shown here" "%~dp0Relay\CoopRelay.exe" host

cd /d "%GAME%\GameData\System"
if "%MAP%"=="" (start "" CT.exe "MPCustom?Listen?game=CoopRC.CoopLobby" %PORTARG%) else (start "" CT.exe "%MAP%?Listen?game=CoopRC.CoopGame" %PORTARG%)
