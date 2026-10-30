# CoopRC: 4-player Republic Commando co-op campaign

Source: `<install>\Code\CoopRC\Classes` → `ucc make` → `GameData\System\CoopRC.u`
(registered as `EditPackages+=Mod`, `EditPackages+=CoopRC` in `GameData\System\System.ini`).
Exported stock scripts (reference, never ship): a folder outside the game and this repo (`ucc batchexport`)
(class source + `maps\<map>\myLevel.t3d`). Depends on RC Fix 2.15 (`Mod.u`: FunctionOverride, PropertyOverrides).

## Status (2026-10-28)
Working, tested host + 1 client on geo_01a (same PC, `?CoopSlot=62`):
- Client joins and plays; no client AI (CoopConsole destroys AIControllers on clients at spawn).
- Client turrets don't run AI states (cosmetic: no local search/aim anim).
- Hint/bio popups open on every player, never pause (`bPauseable=False`, `CoopPlayer.ClientShowMenu`).
- Joiner = `PlayerCommando` next to Boss with the Delta's tag, voice, armour (`RepSkin`), player kit
  + role weapon (Sev sniper, Scorch anti-armor). The map's AI copy of that Delta is removed.
- Boss wears `CloneCommando38_Shader` instead of the white placeholder.
- `ChangeSquadMember` ignores human pawns; Teleporter exits `ServerTravel` the whole session (untested).
- Build: `Code\CoopRC\build.ps1` (UCC hangs on exit after a failed compile, so it has a timeout).
- Test: launch with `LOG=file`, not `-log=file` (the console window steals the main window handle).

## Next up
1. Per-character first-person arms: only Boss's `HudArms` exists. Paint 07/40/62 variants from it, and
   swap `Weapon.Skins[HudArmsShaderIndex[0]]` on bring-up (RC Fix only does this for MPPawn).
2. Squad sticks together at the scripted split-ups (later maps): per-map table that teleports humans
   to Boss / skips split sequences.
3. Death: joiner death currently calls SP RestartGame (no-op on server). Respawn next to Boss.
4. Cutscene/briefing relays (ScreenFade, PlayMovie, Briefing camera) for clients.
5. Verify level exit travel with 2 players; carry joiner inventory across maps.

## Decisions
| Topic | Decision | Why |
|---|---|---|
| Netcode | UE2 listen server, host = Boss (38). Clients join by IP; Steam relay later as a UDP sidecar. | Engine join path already works. |
| Who you play | Joiner N takes slot 07 (Sev) → 40 (Fixer) → 62 (Scorch), or `?CoopSlot=`; unfilled slots stay AI. A joiner gets a **`PlayerCommando` dressed as that Delta** (tag, voice, armour) next to Boss; the map's AI copy is removed. | Possessing the AI Delta pawn kept AI-only state (native 400 HP buff, HUD showed CRITICAL). PlayerCommando gets the real player HUD and perks. |
| "Bonuses" | Every human gets the player perks: `bCanPickupInventory`, PlayerCommando gear (DC15s, bacta, grenades, hand signal), `HealthAffectsGameplay=False`, friendly-fire ×0.2 (FunctionOverride on TakeDamage), and can use **every** marker (hack, demo, snipe, anti-armor). | Squad specialties are only AI marker preferences (`SquadMarker.PreferredPawnClass`, `bAutoSnipe` …); no stat bonuses exist in script. |
| Squad orders | Only Boss (host, local) commands the remaining AI. Human members are removed from `CTSquad` so native squad AI never orders them. | Orders run client-side (`CTPlayer.uc:231-305`) and only the leader may issue them. |
| Weapons | Role kits: Sev starts with `DC17mSniper`, Scorch with `DC17mAntiArmor`; any player can grab any pickup; weapon pickups become per-player (`bWeaponStay`). Inventory persisted per player name server-side across ServerTravel. | No script assumes acquisition order (no `bHasSniper` flags); only first-use tutorial events, which are harmless. |
| Meet-ups (geo_01a/b/c) | Per-map fix table run at level start: drop each `ChangeSquadMember bAddMember=False` effect and fire the meet-up chain early: 01a `Add62ToSquad` (→ `DialogDemolition` → demo charge), 01b `DoorTo40Destroyed`/`ShieldDialog` (→ shield hack), 01c `ActivateSquad` (+ Sev snipe gate `InSnipePosition`). | Meet-ups are pure ScriptedSequence chains (no movies); the only real locks are those events. |
| Cutscenes / screens | FunctionOverride the "first PlayerController" ScriptedActions (PlayMovie, ScreenFade, ShowPrompt, Briefing, ShowDebriefing/TitleCard, AddAmmo, ShakeView) to loop all PCs via a replicated per-player `CoopRelay` with client functions. Briefing camera locks are skipped for clients. | Those natives aren't replicated, so clients currently see nothing. |
| Level end | Teleporter / ChangeLevel → always `ServerTravel` (Teleporter only does it on dedicated servers today). | Listen server currently sends only the touching player. |
| Death / saves | No save games in co-op. Downed players are revived by anyone (bacta). If every human is down → restart the map at the last reached Checkpoint (server remembers it). | SP save/load is Standalone-only (`PlayerController.uc:3156`). |

## Vertical slice (definition of done)
Host + 1 client on geo_01a: client is Scorch (next to Boss, in Scorch's armour), meet-up skipped,
demo charge usable, both reach the exit and ServerTravel to geo_01b together.

## Test commands
```
cd "<install>\GameData\System"
powershell -File ..\..\Code\CoopRC\build.ps1
.\CT.exe "geo_01a?Listen?game=CoopRC.CoopGame" LOG=coop_host.log -windowed
.\CT.exe "127.0.0.1?CoopSlot=62" LOG=coop_client.log -windowed
```
