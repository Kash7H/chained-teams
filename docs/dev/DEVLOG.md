# DEVLOG — Chained Teams

Resume here. Newest entry on top. (This doubles as the universal-modder MODLOG.)

## Paths
- Game: `C:\Program Files (x86)\Steam\steamapps\common\ChainedTogether` (exe: `chainedtogether\Binaries\Win64\ChainedTogether-Win64-Shipping.exe`)
- Saves: `%LOCALAPPDATA%\chainedtogether\Saved` · backup `~\.universal-modder\backups\saved\20261021-122551.zip` · restore: `python -m um backup restore saved`
- Tools (outside repo, never published): `~\Downloads\CT-tools` (repak, pak listing, extracted BPs)
- Mod source: `~\Downloads\ChainedTeams`
- universal-modder clone: `~\Downloads\universal-modder` (run `python -m um ...` from there; `pip install pyyaml pillow numpy` done)

## 2026-10-21 — Session 3: 3v3 verified with local bots (v0.4)
**Bot method:** `UGameplayStatics::CreatePlayer` (needs `GameViewportClient.MaxSplitscreenPlayers = 8`, default 4) adds local players with real PC_Game + PS_Lobby → lobby/teams/spawn/chain/race logic treats them as players. Dev-only commands (CT.devBots): `!bots N`, `!botsready`, `!play`, `!botsat red|blue x y z`, `!state`, `!gs <prop> [val]`, `!who`; no-input runner: `data/devcmd_run.txt` (polled, deleted after run).
**Verified in real game with 6 players (host + 5 bots):**
- ✅ 6 in race lobby; Play enabled by mod (vanilla requires exactly 4).
- ✅ `!balance` → 3 BLUE / 3 RED.
- ✅ **Real 3v3 bug found + fixed:** only 4 spawn capsules → players 5–6 get no character and the game waits forever ("Not all players are spawned", and `GS.CountSpawnedCharacter` gets switched off). Fix (auto, host): after 6 s stuck, `PC_Game:SumoSpawnCharacter(10 args)` beside the start, `pc:Possess(newPawn)`, set `GS.CountSpawnedCharacter = true` → vanilla attach + race start continue. (Hooking `GS_Game:FindPlayerStart` does NOT fire — called via interface.)
- ✅ Race started: CharactersAreAttached=true, timer counting down from 180 min cap.
- ✅ Chains per team, no cross-team links: each team = A with two attached (B–A–C). Team name tags Blue/Red visible.
- ✅ Team splits in chat per team, "X REACHED THE TOP", "X WINS", per-team split summaries.
- ✅ `!rematch` = `ServerTravel /Game/Levels/L_Game02?listen` → back to race lobby, all 6 still connected. (`GS:SwitchToLobby` is NOT a lobby return.)
- ⚠️ Teleporting a team mid-air triggers the game's fall-rescue, which moved the OTHER team too (rescue points look shared). Teleport/bot artifact most likely; watch in live race. Race end screen after `Timer=-1` not captured (game closed during check) → re-verify.
**Still needs real people:** Steam admitting joiners 5–6 over the network, vanilla clients' view, spectate.
Game folder vanilla again; dev install in `CT-tools\dev-install`. Ship builds have `devBots = false`. Zip: `ChainedTeams-v0.4.zip`.

## 2026-10-21 — Session 2b: v0.3 from bytecode findings
Decompile (custom Kismet disassembler, outputs in `CT-tools\decomp\`, never in repo) answered the open problems:
- Only hard 2v2 rule: W_Lobby race `Ready` needs NumPlayers == 4 exactly → mod re-sets `Ready` + Play opacity every 250 ms when 5–6 players and ≥4 chars picked.
- No team cap. Default lobby split = slots 0–1 vs rest → `!balance` (host) alternates teams 0/1.
- 3/team chains = B–A–C line (first teammate in middle) via vanilla `AttachToTeamMember` → no change.
- Collision per team for any size → no change. Team 0 = BLUE confirmed.
- Race end: mod sets `GS.Timer = -1` after a team tops out → vanilla timeout path picks highest team (= winner) + vanilla end screen. Race timer raised to 180 min (safety cap) before start.
- v0.3 loads clean via launcher. Zip: `ChainedTeams-v0.3.zip`. Examples + field note updated, checks pass.
**Still needs live players:** everything race-side listed above.
**Live test script:** host via launcher → Race → password → friends join (4 first) → late joiners 5–6 → `!balance` or `!team` → Play → watch chat splits → someone `!top`? (practice disabled in live race) → winner screen → `!rematch`.

## 2026-10-21 — Session 2: mod v0.2 + launcher
**Verified in the real game (solo, host, Normal mode 1 player):**
- ✅ Version check: reads `CustomGI.Version` = `1.10.19` + checks hooked functions exist → else logs "DISABLED" and does nothing.
- ✅ Session cap hook: `SteamCoreProCreateSession(MaxPlayers)` pre-hook rewrote **4 → 6** (log). Only bumps when 4 (1–3 player lobbies untouched). *Steam actually admitting players 5–6: NOT tested (needs real joiners).*
- ✅ Host → everyone chat via `GS_Game:SendToChatSRV(name, msg, color)` — shows in the game's own chat panel, **left side** of the screen. Chat key is **T**.
- ✅ Commands (parsed from `PC_Game:SendMessageSRV` on host; tested through the F11 dev runner): !help !pos !save !load !mark !tp !skips !top !tpxyz !splits !time !start !reset.
- ✅ Teleport: `K2_TeleportTo` works (RescueTeleport / SetActorLocation silently no-op). Teleports don't fire overlap triggers.
- ✅ Autosplits are **height-based**: 15 sections read live from `BiomeText_BP.BiomeNameText` + Z (The underworld@10075 … The Final Trials@338200). Overlap hook kept as backup.
- ✅ Finish: top reached at Z ≥ 367760 → "TOP REACHED <time>" + full split summary in chat.
- ✅ % to top: (Z − 2790) / (368160 − 2790).
- ✅ **Launcher** (`launcher\ChainedTeams.exe`): starts via steam://rungameid, injects UE4SS.dll from its own folder (CreateRemoteThread/LoadLibraryW ~100 ms after process appears). Mod loads + works end to end. Game folder left clean → normal Steam launch = vanilla.

**Dev install removed from game folder** (backed up in `CT-tools\dev-install\`). To go back to dev mode: copy `dwmapi.dll` + `ue4ss\` from there into Win64.

**NOT verified (needs real online players):** players 5–6 joining, 3v3 team select caps, two 3-person chains, team collision with 3/side, race Play gate with 3v3, race countdown → clock start (`CheckCountdownOver` hook), race win → end screen, !team, !spectate, !rematch.

**Solo dead end (circuit breaker hit):** a 1-player *race* lobby can't be started — Play stays disabled (W_Lobby Tick re-disables; `CheatActivatePlayButton` is dev-build only; forcing `AttachPlayersAndBeginGame` did nothing). Irrelevant with 4+ real players, but the same gate may block 3v3 → see open problems.

**Open problems / next**
1. Race lobby UI has exactly 4 character selectors (`W_Sumo_CharacterSelector_P1..P4`) and 4 lobby pedestals → players 5–6 likely have no lobby slot. Plan: they join *after* the host presses Play (vanilla late-join: "players who join later will not have the option to select their skin"), then `!team red|blue`.
2. Race Play gate likely requires 2 per team ("Can't start the game 2v2"). Plan: start with 4 in lobby (2v2), 2 more late-join → !team. If the gate itself breaks, decompile W_Lobby/W_ConfirmPlayRace bytecode (kismet-analyzer) to find the exact check and hook it.
3. `AttachToTeamMember(Character, Index)` with 3 per team — unknown whether it chains A-B-C or leaves the third loose. If loose: call `BP_Character:Add Chain(other)` / `AttachToNextCharacter` from the host.
4. Team colour mapping (0 = BLUE?) from the lobby banner only.
5. Overlay UI (LiveSplit-style panel / 6-name result screen) not built; chat covers it host-only.

## 2026-10-21 — Session 1b: UE4SS
**Verified in real game:** RE-UE4SS `experimental-latest` (v3.0.1-1181-g83330635) loads via `dwmapi.dll` next to the shipping exe; all Lua mods start; CTRecon loaded (main menu).
- Installed files (to undo: delete these): `Win64\dwmapi.dll`, `Win64\ue4ss\`. Vanilla listing in `dev\win64_vanilla_listing.txt`.
- Settings changed: ConsoleEnabled=1, GraphicsAPI=dx11.
- Auto-dump didn't fire in the main menu (ClientRestart probably only in-level; io.open path relative to process cwd — check `Win64\` and game root).
**Next:** get into a solo Normal run (needs menu clicks) → F6 dump → biome names/heights.

## 2026-10-21 — Session 1: recon
**Done**
- KB search: no prior art for this game. Unreal notes exist (Ghostrunner, Hogwarts, Dishonored).
- `um scan`: UE 5.3, no anti-cheat, no loader, 1 pak (v11, Oodle, unencrypted index, no AES).
- Saves backed up.
- Listed 72,259 pak entries; extracted ~600 key BPs/configs to CT-tools\extract.
- **Found official 2v2 Race mode** (30-min timer, highest team wins). See MODDING_PLAN.md.
- Hardware: Ryzen 7 5800XT / RTX 4060 Ti / 32 GB; 3 Steam accounts on this PC.

**Verified**: only static facts (file listing, strings). Nothing in-game yet.

**Next**
1. Install RE-UE4SS (latest release, dwmapi proxy) → solo launch → confirm UE4SS.log loads, dump objects.
2. Read live: BiomeText_BP names + Z, BP_Height0/1, top Z, GS_Game team functions, MaxPlayers values.

**Open problems**
- UE4SS untested on this build.
- How vanilla clients' lobby/end widgets behave with 5–6 players.
- Distribution: launcher must inject UE4SS without leaving a proxy dll (so Steam Play stays vanilla).
