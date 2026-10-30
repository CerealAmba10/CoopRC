# CoopRC: 4-player co-op campaign for Star Wars: Republic Commando

The host plays Boss (Delta 38). Up to three friends join as Sev (07), Fixer (40) and Scorch (62),
each in their own armour with matching first-person arms. Any commando nobody is playing stays AI and
follows Boss's squad orders as usual.

## Requirements
- Star Wars: Republic Commando (Steam or GOG), the same version on every PC.
- **Republic Commando Fix 2.15 or newer** on every PC: https://github.com/SWRC-Modding/CT/releases
  (the CoopRC setup installs it for you if it's missing; it sets the game's text language to English)
- Every player installs this same CoopRC zip (the package must match exactly).

## Install (every player)
1. Run `CoopRC-Setup.exe`. It finds your game (or asks for the folder), unpacks to
   `...\Star Wars Republic Commando\CoopRC\` and runs `Install-CoopRC.ps1` from there.
   (Without the exe: unzip into the game folder and run
   `powershell -ExecutionPolicy Bypass -File CoopRC\Install-CoopRC.ps1`.)
   The install copies `CoopRC.u` into `GameData\System`, patches `System.ini` (a backup is kept next to it as
   `System.ini.before-CoopRC`), binds **K** to *catch up* if K is free, and builds the Sev/Fixer/Scorch
   first-person arms from your own game files (`CoopRCArms.u`, takes about a minute).
   It also turns off the game's mouse smoothing and acceleration (every profile) and, if the game is set below
   your monitor's resolution (a fresh install starts at 800x600), sets it to native. Widescreen FOV comes from RC Fix.

Update: close the game and relay, then run `Update-CoopRC.bat` in the CoopRC folder. It downloads the latest
release from https://github.com/CerealAmba10/CoopRC/releases and reinstalls. Everyone in a session needs the
same version.

Uninstall: `powershell -ExecutionPolicy Bypass -File Install-CoopRC.ps1 -Uninstall`.

## Play
Everyone needs Steam running (the Steam relay connects you; no port forwarding or VPN needed).

1. **Host:** run `Host-Coop.bat`. The game opens at the main menu and waits; a relay window shows your
   Steam ID. Keep it open.
2. **Friends:** run `Join-Coop.bat [07|40|62]` (07 = Sev, 40 = Fixer, 62 = Scorch, leave it out for the next
   free commando), then right-click the host in the Steam friends list > **Join Game**, or accept the host's
   **Invite to Game**. The game starts and you land in the host's main menu. Keep the relay window open.
   (By ID instead: `Join-Coop.bat <host Steam ID> [07|40|62]`.)
   **How you know it worked:** the friend's relay window says *Connected*, the host's says *Friend connected*,
   and in game the friend gets "Connected as Sev (07)" while the host gets "Sev (07) joined. Squad 2/4."
   A friend stuck in an empty room or the main menu with no message isn't connected: check both relay windows.
   If a relay hits a problem its window stays open with the reason, also saved as `Relay\CoopRelay-join.log`
   (or `-host.log`). Send that file when asking for help.
3. **Host picks NEW GAME.** Everyone plays the Kamino prologue on their own PC. At Geonosis the squad links
   up automatically (Boss waits until everyone is in, up to 2 minutes), and the campaign continues together.

Other ways in:
- `Host-Coop.bat geo_03a` starts straight at a level (map files are in `GameData\Maps`); friends can join
  mid-mission and appear next to Boss.
- Direct connection instead of Steam: `Join-Coop.bat <host IP> [slot]` (LAN, VPN, or UDP 7777 forwarded).
  Another forwarded port works too: the host runs `Host-Coop.bat 25565`, friends `Join-Coop.bat <host IP>:25565 07`.
  The forward must include **UDP**.

## How co-op works
- **Everyone gets the player kit** (DC-17, DC-15s, bacta, grenades) and can hack, slice, set charges
  and snipe. Sev starts with the sniper attachment and Scorch with the anti-armor attachment.
- **The squad stays together.** Joiners and respawns appear next to a teammate. The opening meet-ups
  are skipped for human-played commandos. If you have no teammate within range for 20 seconds (for
  example, a door closed behind the others) you're moved to the nearest one. Press **K** to do it now.
- **Down and out:** downed players can be revived with bacta as usual. A dead player respawns next to
  a teammate after a few seconds, or press fire. If the whole squad dies, the level restarts and
  everyone stays connected. Save/load is single player only.
- **Cutscenes:** in-level cutscenes (briefings) play for everyone: joiners watch through their own commando when
  it's in the scene (e.g. Sev's intro), otherwise through Boss, then take over where it ends. Movies
  play for everyone.
- Hints and popups show for every player and never pause the game.
- Install also raises the game's 2005-era network rates (5-20 KB/s, 20 Hz) to 100 KB/s and 60 Hz,
  so enemies move smoothly on joiners' screens.
- **Level exits wait for the whole squad:** the level only continues once every player is up and at
  the exit. Players already there see "Waiting for the squad at the exit (n/m)".

Tuning (host only): `GameData\System\CoopRC.ini`, `[CoopRC.CoopGame]`: `RespawnDelay`,
`LeashDistance`, `LeashTime`, `WipeDelay`, `ExitRadius`.

## Known limits
- Only Boss (the host) can give squad orders to the remaining AI.
- Cutscene-only versions of the commandos (Sev on the Prosecutor, the Kashyyyk regroup) still play
  their scenes as AI. Your human commando stays with Boss.
- Joining while the host is in the middle of a cutscene isn't handled; join from the menu or during play.

Built with RC Fix's FunctionOverride (github.com/SWRC-Modding/CT). The Steam relay (`Relay\CoopRelay.exe`)
uses Steamworks.NET (MIT, license included) and Republic Commando's own Steam app ID. CoopRC ships no
game files: the arm textures are recoloured from Boss's arms on your PC by `Build-Arms.ps1`. Source is in
`Source\`.
Built with the help of an AI assistant (Claude).
