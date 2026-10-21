# Chained Teams — Modding Plan

> 3v3 live race + speedrun splits + a 1–3 player Practice mode for **Chained Together**.
> Private lobbies with friends only. No leaderboards, no public matchmaking.

## TL;DR (read this first)

- 🟢 **Big win:** the game already ships an official **2v2 Race mode**. Teams, per-team chains, team collision, a 3-2-1 countdown, team heights and an end screen all exist. We **stretch it to 3v3** and add splits, instead of building racing from scratch.
- 🟢 **No anti-cheat, no pak encryption, plain UE 5.3.** UE4SS (Lua) is the route.
- 🟡 **Host-only is realistic for the gameplay.** Everything that decides *who is chained to whom, where you spawn, who wins* runs on the host and replicates to vanilla clients.
- 🟠 **The pretty UI needs a tiny client install.** A vanilla client can't draw a widget class it doesn't have. Without it, friends get splits as **chat messages** (the game's own chat) and the vanilla end screen (which only shows 4 names).
- ❓ **Not proven yet:** UE4SS has never been run on this game (no prior art anywhere). That's step 1.

## Status snapshot (2026-10-21, end of session 2)

| Feature | Status |
|---|---|
| UE4SS on this game | ✅ verified (proxy + launcher injection) |
| Version check / safe-disable | ✅ verified |
| Lobby cap 4 → 6 | 🟡 hook verified in log; real joiners 5–6 untested |
| Splits (15 sections, height-based) in chat, left side | ✅ verified solo |
| % to top | ✅ formula verified (`!pos`), periodic race ticker untested |
| Finish / split summary | ✅ verified solo |
| Practice: save/load/mark/tp/skips/top | ✅ verified solo |
| Launcher + 3-step friend guide + zip | ✅ verified (`ChainedTeams-v0.2.zip`) |
| 3v3 teams, 2 chains of 3, collision, race Play gate, countdown clock, race end screen, spectate, rematch | ⏳ code written / needs online players |
| Corner LiveSplit overlay (client) | ⬜ not started (chat covers it host-only) |

## Recon facts (2026-10-21)

| Thing | Value |
|---|---|
| Steam app | 2567870, `C:\Program Files (x86)\Steam\steamapps\common\ChainedTogether` |
| Engine | UE **5.3** (`UE5+Release-5.3`), project `ChainedTogether`, ProjectVersion **1.0.5** |
| Packaging | one `ChainedTogether-Windows.pak`, **v11, Oodle, index not encrypted, no AES**, no IoStore |
| Anti-cheat | none |
| Networking | `SteamCoreSockets` net driver, OnlineSubsystem `SteamCore`, AdvancedSessions + SteamCorePro plugins |
| Native code | small C++ module `/Script/ChainedTogether` (`ChainedTogetherBFL`); **gameplay is Blueprint** → UE4SS can hook/override it |
| Saves | `%LOCALAPPDATA%\chainedtogether\Saved` — backed up: `~\.universal-modder\backups\saved\20261021-122551.zip` |
| Prior art | none in the KB for this game; no UE4SS mods found online |

### What the game already has (from the pak's asset names/strings)

- **Game modes** (`E_Gamemodes`): Beginner, Normal, Lava, **Race**, Mod_Play, Mod_Test.
- **Teams** (`E_TeamCodes`): 2 teams (Red/Blue). `PC_Game.RequestTeamServer`, `PS_Lobby.ChosenTeamID`, `CustomGI.TeamRedCounter/TeamBlueCounter`, `W_TeamSelectWidget` (host/client team buttons).
- **Chains**: `GS_Game.AttachToTeamMember`, `AttachToNext/PreviousCharacter`, `BP_NewChain`. Normal mode chains 4 people in a line, so a 3-person chain is a supported shape.
- **Inter-team collision**: `TeamCollisionCapsule` on the character → race mode already handles teams passing through each other (to verify).
- **Start**: `GS_Game.321Server / 321All`, `CountdownTimerServer`, `W_321Go`, `InitialCountdown`.
- **Progress**: `GS_Game.CalculateTeamHeight`, `CustomGI.TeamHeights`, `RaceModeSnapshot`, `BP_Height0/1` (height references).
- **Win**: `GM_Game.RaceModeCalculateWinnerCreateEndGameScreenSRV`, `E_RaceWinReason` = TimesUp / Disconnect, `W_RaceEndGameScreen` (**hard-coded 4 name slots**).
- **Hard 2v2 limits found**: `W_ConfirmPlayRace` → "Can't start the game 2v2", `Versus_W` "Player 1 + Player 2 / Player 3 + Player 4", 4-slot end screen, `MaxPlayers` in `GM_Game` + `CustomGI`.
- **Sections**: `BiomeText_BP` trigger boxes in the level carry a `BiomeName` and fire a banner + `SaveBiomeProgress`. Sub-levels: Lobby, Underworld, HellHorizon, Warehouse, Chantier (construction), CityHole, Near/FarCityHorizon, RoofTops, Port, PassingTrain, CarRace, Asia, Greece, AncientTemple, GoblinCave, MysteriousCave, PostMysteriousCave, Heaven. Exact in-game names to be read live.
- **Practice helpers**: `BP_Teleporter` (internally `BP_2v2Teleporter`), `CheatManager_CT`, `W_FlyMode` / dev fly mode, `Checkpoint_BP`, `BP_RescuePoint`, game chat (`AddChatElemAll`).

## Route

1. **UE4SS** (RE-UE4SS, Lua mods) on the **host**. Hooks Blueprint UFunctions, reads/writes properties, spawns nothing new that needs replicating.
2. Everything gameplay-related is **server-side** → replicates to vanilla clients through the game's existing classes.
3. **Optional client add-on** = same UE4SS Lua mod in "client mode" for the overlay UI. Delivered by a **launcher .exe that injects UE4SS** at launch, so the game folder is untouched and Steam's normal Play button stays 100% vanilla.

Why not pak mods: new Blueprint classes in a pak would have to exist on every client to replicate. Lua on top of existing classes doesn't change the network layout, so vanilla clients stay compatible.

## Feasibility verdict per feature

Legend: 🟢 likely, 🟡 likely with work, 🟠 needs client install for full version, 🔴 blocked (none so far). **H** = host-only works, **C** = needs client add-on.

| # | Feature | Verdict | Host-only? | How |
|---|---|---|---|---|
| 1 | 6-player lobby | 🟡 | **H** | Raise session `MaxPlayers` (CustomGI/GM_Game) before the host creates the session. Add 2 extra spawn transforms if the lobby only has 4 player starts. Risk: client-side lobby widgets assume ≤4. |
| 2 | Team select | 🟡 | **H** (vanilla widget) | Game's own `W_TeamSelectWidget` already lets each player pick Red/Blue. Lift the "2 per team" cap on the host (`RequestTeamServer` / counters). Fallback: chat command `!red` / `!blue`. |
| 3 | Host settings (difficulty) | 🟡 | **H** | Race is its own mode; host also sets Beginner/Normal/Lava rules flags (e.g. `LavaMode`) on top. Chat command `!diff normal` or a host-only panel. Need live test of which rules Race respects. |
| 4 | Host-only Start + countdown | 🟢 | **H** | Already host-only in race. Bypass the "2v2 only" confirm check; reuse `321Server`. |
| 5 | Two 3-person chains, colored | 🟢 / 🟠 | **H** chains, **C** for custom colors beyond vanilla | `AttachToTeamMember` already chains per team. Race mode already tints red/blue (`GetSkinByID_TeamID`). Name-tag color: vanilla `PseudoTeam_Widget`. |
| 6 | Teams pass through each other | 🟢 | **H** | `TeamCollisionCapsule` exists; verify with 3 per team. Fallback: set collision channels on the host (movement is client-predicted, so verify for jitter). |
| 7 | Autosplits + LiveSplit-style corner UI | 🟡 / 🟠 | **H** timing + chat splits, **C** overlay | Host hooks `BiomeText_BP` overlap per team → host clock → broadcasts `"🔴 RED  City  12:34.5"` via game chat. Corner widget drawn by the client add-on (from replicated chat/state). |
| 8 | Height meter / % to top | 🟡 / 🟠 | **H** via chat ticker, **C** overlay | `CalculateTeamHeight` + top Z from the Heaven end trigger. |
| 9 | First to top wins + result screen | 🟡 / 🟠 | **H** win, **C** for 6-name result screen | Detect the end trigger (`BP_EndCinematic` / Heaven) per team → call the game's own end-game screen with our winner. Vanilla screen shows 4 names; full 3v3 splits table needs client add-on (chat summary for vanilla). |
| 10 | Spectate after finishing | 🟡 | **H** | Server calls `SetViewTargetWithBlend` on a finished player's controller (engine RPC, works on vanilla). Cycle with a chat command. |
| 11 | Rematch | 🟡 | **H** | Host server-travels / reloads the race map; everyone stays connected. |
| 12 | 🆕 Practice mode (1–3 players) | 🟢 | **H** | Co-op normal mode + chat commands: `!tp <skip>`, `!save` / `!load` position (whole chain), `!skips` list, retry loop, timer per attempt. Skip list stored as named coordinates (we record them in game). |
| 13 | Version check / safe-disable | 🟢 | both | On start, check `ProjectVersion` 1.0.5 + the exe size/hash + that every hooked function exists. If anything is off → do nothing, show "Chained Teams: game updated, mod disabled". |

**Overall: GO.** Nothing is blocked on paper. The one real unknown is whether UE4SS runs cleanly on this build, and how vanilla clients behave with 5–6 players in a lobby built for 4.

### Host-only vs client: exactly which parts need client code

Host-only (friends install nothing): 6-player lobby, teams, 3-person chains, collision, countdown, host-only start, difficulty, win detection, spectate, rematch, practice teleports, **splits as chat lines**.

Needs the client add-on (optional): the left-corner LiveSplit panel, the live height bars, a 3v3 result screen with all 6 names and split tables, custom team colors on name tags beyond what race mode already does.

## Test plan

**Hardware on this PC:** Ryzen 7 5800XT, RTX 4060 Ti, 32 GB RAM. **Three Steam accounts** have logged in here (`50percentmeme`, `seraphimtheflash`, `monkey04084`).

| What | Solo? | How |
|---|---|---|
| UE4SS loads, dump classes, read section names | ✅ solo | offline/solo run |
| Teleports, save/load, splits from section triggers, version check | ✅ solo | solo Normal mode |
| Team + chain logic, collision with 2 pawns | 🟡 solo-ish | the game has **local split-screen** (`LocalMultiplayer_W`, `AddLocalMP_Players`) → several pawns on one PC |
| Real online join, 6-player cap, vanilla-client behaviour | 🟡 mostly solo | **2nd Steam instance**: run a second copy under a different Windows user / sandbox (Sandboxie-Plus) logged into account #2. Or a 2nd PC/laptop if available. |
| Full 3v3 live | ❌ needs friends | final test with 5 friends; I'll tell you when |

## Optional toggles (backlog, all OFF by default, host flips before Start)

H = host-only, C = needs client add-on.
- Race: catch-up handicap (H), rising lava (H), time-penalty falls (H), rival-team marker (C), chaos events (H), chain length slider (H, untested).
- Practice: skip library `!tp`/`!mark` (H), save/load chain state (H), auto-retry loop (H), slow-mo (H), free-fly scouting (H), PB ghost (C), split deltas vs PB (C).
- Speedrun QoL: `.lss`/CSV split export (H), category presets (H), split sounds (C).
- Party: custom chain colors/team names (C), tag mode (H), photo mode (C).

## Build order (slices, each verified in game)

0. Install UE4SS → launch solo → hello-world Lua + dump → read biome names + heights. *(next)*
1. 6-player cap (host) → join test with 2nd account.
2. Teams 3v3 (lift caps).
3. Two chains of 3 (local split-screen test).
4. Collision rules.
5. Host start + countdown + difficulty.
6. Splits (chat) → overlay (client add-on).
7. Win / spectate / rematch.
8. Practice mode.
9. Launcher .exe + 3-step friend guide.
10. Field note + examples/ source for universal-modder (no PR until you OK it).
