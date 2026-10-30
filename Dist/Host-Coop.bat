@echo off
rem Host a co-op game.
rem   Host-Coop.bat          lobby: friends join from their main menu, then you pick NEW GAME
rem   Host-Coop.bat geo_03a  start straight at a level (map files are in GameData\Maps)
rem Also starts the Steam relay (needs Steam running) so friends can join with your Steam ID.
setlocal
if "%GAME%"=="" set GAME=%~dp0..
if not exist "%GAME%\GameData\System\CT.exe" (echo Set GAME to your Star Wars Republic Commando folder & pause & exit /b 1)

start "CoopRC Steam relay - give friends the Steam ID shown here" "%~dp0Relay\CoopRelay.exe" host

cd /d "%GAME%\GameData\System"
if "%1"=="" (start "" CT.exe "MPCustom?Listen?game=CoopRC.CoopLobby") else (start "" CT.exe "%1?Listen?game=CoopRC.CoopGame")
