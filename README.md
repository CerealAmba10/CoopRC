# CoopRC

4-player co-op campaign for **Star Wars: Republic Commando** (PC). The host plays Boss; up to three friends
join as Sev, Fixer and Scorch. A Steam relay connects players without port forwarding.

**Players:** download `CoopRC-Setup-<version>.exe` from [Releases](../../releases), run it, and read
[the player README](Dist/README.md). Later versions: run `Update-CoopRC.bat` in the installed CoopRC folder.

Requires [Republic Commando Fix 2.15+](https://github.com/SWRC-Modding/CT/releases) and the Steam version of the game
(for the relay).

## Layout
- `Classes/`: UnrealScript (`CoopRC.u`), built with RC Fix's `UCC make` via `build.ps1`
- `Relay/`: Steam P2P relay (.NET 6, Steamworks.NET)
- `Dist/`: what players get: launchers, installer and updater scripts, README
- `Installer/`: the setup exe (embeds the release zip)
- `Tools/`: arm texture recolouring and test scripts
- `DESIGN.md`: how it works and what's been verified

## Build and release
Clone into `<game>\Code\CoopRC`, then:
```
powershell -File build.ps1
dotnet publish Relay -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true -o Relay\bin\publish
powershell -File make_dist.ps1 -Version 0.6 -Publish
```

No game files are in this repository. The Sev/Fixer/Scorch arm textures are recoloured from each player's own
game files at install time (`Dist/Build-Arms.ps1`). Built with the help of an AI assistant (Claude).
MIT licensed, see `LICENSE`.
