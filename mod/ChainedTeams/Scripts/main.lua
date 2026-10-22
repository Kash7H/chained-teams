-- Chained Teams - host-side UE4SS Lua mod for Chained Together.
-- 3v3 race on top of the official Race mode, autosplits, practice tools. Private lobbies only.
-- Everything here runs on the HOST; clients can stay vanilla (they see results through the game's own chat).

local CT = { devBots = false,  -- set true for solo bot testing (!bots, !play, devcmd_run.txt)
    debug = false, VERSION = "0.5.2", SUPPORTED_GAME = { ["1.10.19"] = true } }
local MAX_PLAYERS = 6
local TAG = "Chained Teams"
-- data folder next to Scripts/, derived from this file's path (works for proxy installs and launcher injection)
local DATA_DIR = (function()
    local src = debug.getinfo(1, "S").source or ""
    src = src:gsub("^@", ""):gsub("\\", "/")
    local base = src:match("^(.*)/Scripts/[^/]+$")
    return base and (base .. "/data/") or "ue4ss/Mods/ChainedTeams/data/"
end)()

local state = {
    enabled = nil,        -- nil = not checked yet, false = disabled by version check
    raceStart = nil,      -- server world time when the countdown finished
    splits = { [0] = {}, [1] = {} },  -- team -> list of {name, t}
    seenBiome = { [0] = {}, [1] = {} },
    finished = {},        -- team -> time
    bestZ = { [0] = 0, [1] = 0 },
    saved = {},           -- practice save per team
    skips = {},
}
-- E_TeamCodes: 0 = blue side of the lobby banner (host defaulted there in race lobby), 1 = red. Verify with real players.
local TEAM_NAME = { [0] = "BLUE", [1] = "RED" }
local BOTTOM_Z, TOP_Z = 2790, 368160            -- BP_Height0 / BP_Height1 (measured 2026-10-21, game 1.10.19)

local function log(s) print("[ChainedTeams] " .. tostring(s)) end

-- ---------- helpers ----------
local function valid(o) return o ~= nil and o:IsValid() end
-- Hooks on game Blueprints only work once the game has loaded that Blueprint (often not until a level or
-- menu opens). hookLater retries every second until the function exists, then registers the hook.
local pendingHooks = {}
function CT.hookLater(path, pre, post)
    pendingHooks[#pendingHooks + 1] = { path = path, pre = pre, post = post }
end
LoopAsync(1000, function()
    if #pendingHooks == 0 then return false end
    ExecuteInGameThread(function()
        for i = #pendingHooks, 1, -1 do
            local h = pendingHooks[i]
            local fn = StaticFindObject(h.path)
            if fn ~= nil and fn:IsValid() then
                local ok, err = pcall(function()
                    if h.post then RegisterHook(h.path, h.pre, h.post) else RegisterHook(h.path, h.pre) end
                end)
                table.remove(pendingHooks, i)
                log((ok and "hooked " or "hook failed ") .. h.path:match("[^:]+$") .. (ok and "" or (": " .. tostring(err))))
            end
        end
    end)
    return false
end)

local function GI() local a = FindFirstOf("CustomGI_C"); if valid(a) then return a end end
local function GS() local a = FindFirstOf("GS_Game_C"); if valid(a) then return a end end
local function now()
    local gs = GS(); if not gs then return 0 end
    local ok, t = pcall(function() return gs:GetServerWorldTimeSeconds() end)
    return ok and t or 0
end
local function fmt(t)
    if not t then return "--:--" end
    local m = math.floor(t / 60); local s = t - m * 60
    if m >= 60 then return string.format("%d:%02d:%04.1f", math.floor(m / 60), m % 60, s) end
    return string.format("%d:%04.1f", m, s)
end
-- "host" = this game runs the session: hosting online OR playing solo / training / local.
-- Only a client that joined someone else's game is not the host.
local function isHost()
    local gs = FindFirstOf("GS_Game_C")
    if valid(gs) then
        local ok, auth = pcall(function() return gs:HasAuthority() end)
        if ok and auth ~= nil then return auth == true end
        local ksl = StaticFindObject("/Script/Engine.Default__KismetSystemLibrary")
        local ok2, srv = pcall(function() return ksl:IsServer(gs) end)
        if ok2 and srv ~= nil then return srv == true end
    end
    local gi = GI(); if not gi then return false end
    local ok, v = pcall(function() return gi.HostingOnlineSession end)
    return ok and v
end
local function say(msg, team)
    local gs = GS(); if not gs then return end
    local col = { R = 1, G = 0.85, B = 0.2, A = 1 }
    -- team 0 = BLUE, team 1 = RED
    if team == 0 then col = { R = 0.3, G = 0.55, B = 1, A = 1 } elseif team == 1 then col = { R = 1, G = 0.25, B = 0.25, A = 1 } end
    pcall(function() gs:SendToChatSRV(TAG, msg, col) end)
    log("chat: " .. msg)
    CT.chatLog = CT.chatLog or {}
    table.insert(CT.chatLog, msg)
    while #CT.chatLog > 8 do table.remove(CT.chatLog, 1) end
end
local function chars()
    local out = {}
    for _, c in ipairs(FindAllOf("BP_Character_C") or {}) do if valid(c) then out[#out + 1] = c end end
    return out
end
local function teamOf(c) local ok, t = pcall(function() return c.TeamID end); return ok and t or 0 end
local function z(c) local ok, l = pcall(function() return c:K2_GetActorLocation() end); return ok and l and l.Z or 0 end
local function pct(zv) return math.max(0, math.min(100, (zv - BOTTOM_Z) / (TOP_Z - BOTTOM_Z) * 100)) end
local function isRace()
    local gs = GS(); if not gs then return false end
    local ok, m = pcall(function() return gs["Selected Game Mode"] end)
    return ok and m == 5   -- E_Gamemodes: 0 Beginner,1 Normal,2 Lava,? ... Race = 5 (seen live)
end

-- ---------- version check (fail safe) ----------
local function versionCheck()
    if state.enabled ~= nil then return state.enabled end
    local gi = GI(); if not gi then return nil end
    local ok, v = pcall(function() return gi.Version:ToString() end)
    if not ok then ok, v = pcall(function() return tostring(gi.Version) end) end
    local needed = {
        "/Game/Blueprint/Gameplay/GS_Game.GS_Game_C:SendToChatSRV",
        "/Game/Blueprint/Gameplay/PC_Game.PC_Game_C:SendMessageSRV",
        "/Game/Blueprint/BiomeText/BiomeText_BP.BiomeText_BP_C:BndEvt__BiomeText_BP_Box_K2Node_ComponentBoundEvent_0_ComponentBeginOverlapSignature__DelegateSignature",
    }
    local missing = {}
    for _, f in ipairs(needed) do local o = StaticFindObject(f); if not valid(o) then missing[#missing + 1] = f end end
    if not CT.SUPPORTED_GAME[v] or #missing > 0 then
        state.enabled = false
        log("DISABLED: game version '" .. tostring(v) .. "' not tested, or missing: " .. table.concat(missing, ", "))
        log("Chained Teams turned itself off so the game runs normally. Update the mod for this game version.")
        return false
    end
    state.enabled = true
    log("game " .. v .. " OK, mod " .. CT.VERSION .. " active")
    return true
end

-- ---------- 6-player lobby ----------
local function bumpMax(p)
    if state.enabled == false then return end
    local ok, cur = pcall(function() return p:get() end)
    -- only full 4-player / race lobbies become 6; 1-3 player lobbies keep their size
    if ok and cur == 4 then
        p:set(MAX_PLAYERS); log("session MaxPlayers " .. cur .. " -> " .. MAX_PLAYERS)
        local gi = GI(); if gi then pcall(function() gi.MaxPlayers = MAX_PLAYERS end) end
    end
end
pcall(function()
    RegisterHook("/Script/SteamCorePro.SteamCoreProCreateSession:CreateSteamCoreProSession",
        function(ctx, world, settings, name, maxp) bumpMax(maxp) end)
end)
pcall(function()
    RegisterHook("/Script/SteamCorePro.SteamCoreProUpdateSession:UpdateSteamCoreProSession",
        function(ctx, world, settings, name, maxp) bumpMax(maxp) end)
end)

-- ---------- splits ----------
local function resetRace()
    state.raceStart = nil
    state.splits = { [0] = {}, [1] = {} }
    state.seenBiome = { [0] = {}, [1] = {} }
    state.finished = {}
    state.bestZ = { [0] = 0, [1] = 0 }
end

local function startClock(reason)
    resetRace(); state.raceStart = now()
    log("clock started (" .. reason .. ") at " .. state.raceStart)
end

local function onBiome(biome, other, forcedTeam)
    if not state.enabled or not isHost() then return end
    if forcedTeam == nil and (not valid(other) or not other:GetClass():GetFName():ToString():find("BP_Character")) then return end
    local ok, name = pcall(function() return biome.BiomeNameText:ToString() end)
    name = ok and name or "?"
    local team = forcedTeam or (isRace() and teamOf(other) or 0)
    if state.seenBiome[team][name] then return end
    state.seenBiome[team][name] = true
    if not state.raceStart then startClock("first split") end
    local t = now() - state.raceStart
    table.insert(state.splits[team], { name = name, t = t })
    local prefix = isRace() and (TEAM_NAME[team] .. "  ") or ""
    say(string.format("%s%s  %s", prefix, name, fmt(t)), isRace() and team or nil)
end

-- sections read from the level's BiomeText_BP triggers, sorted by height
CT.sections = nil
local function loadSections()
    local list = {}
    for _, b in ipairs(FindAllOf("BiomeText_BP_C") or {}) do
        if valid(b) then
            local okn, n = pcall(function() return b.BiomeNameText:ToString() end)
            local okl, l = pcall(function() return b:K2_GetActorLocation() end)
            if okn and okl and n and n ~= "" then list[#list + 1] = { name = n, z = l.Z, actor = b } end
        end
    end
    table.sort(list, function(a, b) return a.z < b.z end)
    if #list > 0 then
        CT.sections = list
        local names = {}; for _, s in ipairs(list) do names[#names + 1] = string.format("%s@%.0f", s.name, s.z) end
        log("sections: " .. table.concat(names, ", "))
    end
end

local function checkHeightSplits(team, topZ)
    if not CT.sections then loadSections() end
    if not CT.sections then return end
    for _, s in ipairs(CT.sections) do
        if topZ >= s.z - 150 and not state.seenBiome[team][s.name] then onBiome(s.actor, nil, team) end
    end
end

-- ---------- win / finish ----------
local function finish(team)
    if state.finished[team] or not state.raceStart then return end
    state.finished[team] = now() - state.raceStart
    if not isRace() then
        say(string.format("TOP REACHED  %s", fmt(state.finished[team])))
        local parts = {}
        for _, s in ipairs(state.splits[0]) do parts[#parts + 1] = s.name .. " " .. fmt(s.t) end
        if #parts > 0 then say("RUN: " .. table.concat(parts, " | ")) end
        return
    end
    say(string.format("%s REACHED THE TOP  %s", TEAM_NAME[team], fmt(state.finished[team])), team)
    local other = 1 - team
    if not state.finished[other] then
        say(TEAM_NAME[team] .. " WINS! (" .. TEAM_NAME[other] .. " can keep climbing)", team)
        local gs = GS()
        if gs and isRace() then
            -- end the race through the game's own timeout path: CheckCountdownOver sees Timer < 0 and
            -- picks the highest team (the one at the top) as winner, RaceWinReason = TimesUp.
            ExecuteWithDelay(4000, function() ExecuteInGameThread(function()
                pcall(function() gs.Timer = -1 end)
            end) end)
        end
    end
    -- summary
    for tm = 0, 1 do
        local parts = {}
        for _, s in ipairs(state.splits[tm]) do parts[#parts + 1] = s.name .. " " .. fmt(s.t) end
        if #parts > 0 then say(TEAM_NAME[tm] .. ": " .. table.concat(parts, " | "), tm) end
    end
end

-- 1 Hz tick: progress + top detection
local lastTicker = 0
LoopAsync(1000, function()
    if not state.enabled or not isHost() or not state.raceStart then return false end
    ExecuteInGameThread(function()
        local top = { [0] = 0, [1] = 0 }
        for _, c in ipairs(chars()) do
            local tm = isRace() and teamOf(c) or 0
            local zz = z(c); if zz > top[tm] then top[tm] = zz end
            if zz >= TOP_Z - 400 then finish(tm) end
        end
        for tm = 0, 1 do
            if top[tm] > state.bestZ[tm] then state.bestZ[tm] = top[tm] end
            if top[tm] > 0 then checkHeightSplits(tm, top[tm]) end
        end
        local t = now()
        if CT.debug then log(string.format("tick chars=%d top0=%.0f top1=%.0f fin0=%s", #chars(), top[0], top[1], tostring(state.finished[0]))) end
        if t - lastTicker >= 120 then
            lastTicker = t
            if isRace() then
                say(string.format("RED %.0f%%  vs  BLUE %.0f%%   (%s)", pct(top[0]), pct(top[1]), fmt(t - state.raceStart)))
            end
        end
    end)
    return false
end)

-- ---------- practice: positions ----------
local function groupOf(c)
    local out = { c }
    pcall(function()
        local arr = {}
        c:GetAttachedGroup(arr)
        -- out-param arrays come back in the table passed in
        local list = arr.Charaters or arr[1]
        if list then
            out = {}
            list:ForEach(function(_, e) local o = e:get(); if valid(o) then out[#out + 1] = o end end)
        end
    end)
    return out
end

local function snapshot(team)
    local snap = {}
    for _, c in ipairs(chars()) do
        if (not isRace()) or teamOf(c) == team then
            local l = c:K2_GetActorLocation(); local r = c:K2_GetActorRotation()
            snap[#snap + 1] = { c = c, x = l.X, y = l.Y, z = l.Z, yaw = r.Yaw }
        end
    end
    return snap
end

local TP_LIFT = 60   -- land ~2 ft above the saved spot so we never end up inside the floor

-- Place a character exactly. K2_TeleportTo "finds a free spot nearby" and slid players sideways,
-- so set the location directly first and only fall back to the engine teleport if that didn't move us.
local function tpChar(c, x, y, zz, yaw)
    local loc = { X = x, Y = y, Z = zz }; local rot = { Pitch = 0, Yaw = yaw or 0, Roll = 0 }
    local function dist()
        local ok, l = pcall(function() return c:K2_GetActorLocation() end)
        if not (ok and l) then return 1e9 end
        return math.sqrt((l.X - x) ^ 2 + (l.Y - y) ^ 2 + (l.Z - zz) ^ 2)
    end
    -- Like the game's BP_Teleporter: the character pulls itself toward its synced position
    -- (ClientRepLocation/ServerRepLocation) and has a physics sphere + chain links, so move all of them.
    local ZERO = { X = 0, Y = 0, Z = 0 }
    pcall(function() c.IsTeleporting = true end)
    pcall(function() c:K2_SetActorLocation(loc, false, {}, true) end)
    pcall(function() c:K2_SetActorRotation(rot, true) end)
    pcall(function() c.ClientRepLocation = loc end)
    pcall(function() c.ServerRepLocation = loc end)
    pcall(function() c.ServerRepVelocity = ZERO end)
    pcall(function()
        local s = c.Sphere
        if valid(s) then
            s:K2_SetWorldLocation(loc, false, {}, true)
            s:SetAllPhysicsLinearVelocity(ZERO, false)
        end
    end)
    pcall(function()
        local out = {}
        c:GetConnectedChains(out)
        if out.Chains then
            out.Chains:ForEach(function(_, e)
                local ch = e:get()
                if valid(ch) then pcall(function()
                    ch.Maillons_Array:ForEach(function(_, m)
                        local link = m:get()
                        if valid(link) then
                            pcall(function() link:K2_SetWorldLocation(loc, false, {}, true) end)
                            pcall(function() link:SetAllPhysicsLinearVelocity(ZERO, false) end)
                        end
                    end)
                end) end
            end)
        end
    end)
    -- The character is physics driven and keeps its old momentum (it slid ~14 m after a teleport).
    -- Pin it to the target for 0.6 s: re-place it and zero every velocity each 50 ms.
    local function pin()
        if not valid(c) then return end
        pcall(function() c.ServerRepVelocity = ZERO end)
        pcall(function() c.ServerRepLocation = loc end)
        pcall(function() c.ClientRepLocation = loc end)
        pcall(function() c:K2_SetActorLocation(loc, false, {}, true) end)
        pcall(function()
            local s = c.Sphere
            if valid(s) then
                s:K2_SetWorldLocation(loc, false, {}, true)
                s:SetAllPhysicsLinearVelocity(ZERO, false)
                s:SetPhysicsLinearVelocity(ZERO, false, FName("None"))
                s:SetPhysicsAngularVelocityInDegrees(ZERO, false, FName("None"))
            end
        end)
    end
    pin()
    for i = 1, 12 do
        ExecuteWithDelay(i * 50, function() ExecuteInGameThread(pin) end)
    end
    ExecuteWithDelay(700, function() ExecuteInGameThread(function()
        if valid(c) then
            pcall(function() c.ClientRepLocation = c:K2_GetActorLocation() end)
            pcall(function() c.IsTeleporting = false end)
        end
    end) end)
    local d = dist()
    if d > 100 then log(string.format("teleport: ended %.0f units away from target", d)); return false end
    return true
end

local function restore(snap)
    for _, s in ipairs(snap) do if valid(s.c) then tpChar(s.c, s.x, s.y, s.z + TP_LIFT, s.yaw) end end
end

-- whole team to one spot: stacked straight up above it (no sideways spread into walls)
local function tpTeamTo(team, x, y, zz, yaw)
    local i = 0
    for _, c in ipairs(chars()) do
        if (not isRace()) or teamOf(c) == team then
            tpChar(c, x, y, zz + TP_LIFT + i * 110, yaw); i = i + 1
        end
    end
end
-- skips file: name x y z yaw
local function loadSkips()
    state.skips = {}
    local f = io.open(DATA_DIR .. "skips.txt", "r"); if not f then return end
    for line in f:lines() do
        local n, x, y, zz, yaw = line:match("^(%S+)%s+(%-?[%d%.]+)%s+(%-?[%d%.]+)%s+(%-?[%d%.]+)%s*(%-?[%d%.]*)")
        if n then state.skips[n] = { x = tonumber(x), y = tonumber(y), z = tonumber(zz), yaw = tonumber(yaw) or 0 } end
    end
    f:close()
end
local function saveSkips()
    local f = io.open(DATA_DIR .. "skips.txt", "w"); if not f then log("cannot write skips.txt"); return end
    local names = {}; for n in pairs(state.skips) do names[#names + 1] = n end; table.sort(names)
    for _, n in ipairs(names) do local s = state.skips[n]; f:write(string.format("%s %.0f %.0f %.0f %.0f\n", n, s.x, s.y, s.z, s.yaw)) end
    f:close()
end

-- ---------- chat commands ----------
local HELP = "!help !time !splits !pos !team red|blue !spectate !me | practice: !save !load !mark <name> !tp <name> !skips !top | host: !balance !start !reset !rematch"

local function senderChar(pc)
    local ok, p = pcall(function() return pc.Pawn end)
    if ok and valid(p) then return p end
end

local function onCommand(pc, msg)
    local cmd, arg = msg:match("^!(%S+)%s*(.*)$"); if not cmd then return end
    cmd = cmd:lower()
    local me = senderChar(pc)
    local team = me and teamOf(me) or 0
    if not isRace() then team = 0 end
    local okh, hostPC = pcall(function() return pc:IsLocalController() end)
    if (cmd == "start" or cmd == "reset" or cmd == "rematch" or cmd == "balance") and not (okh and hostPC) then
        say("only the host can use !" .. cmd); return
    end
    if cmd == "help" then say(HELP)
    elseif cmd == "time" then say(state.raceStart and ("clock " .. fmt(now() - state.raceStart)) or "clock not running")
    elseif cmd == "splits" then
        for tm = 0, 1 do
            local parts = {}
            for _, s in ipairs(state.splits[tm]) do parts[#parts + 1] = s.name .. " " .. fmt(s.t) end
            say((isRace() and TEAM_NAME[tm] or "RUN") .. ": " .. (#parts > 0 and table.concat(parts, " | ") or "no splits yet"), isRace() and tm or nil)
            if not isRace() then break end
        end
    elseif cmd == "pos" and me then
        local l = me:K2_GetActorLocation()
        say(string.format("pos %.0f %.0f %.0f  (%.1f%% to top)", l.X, l.Y, l.Z, pct(l.Z)))
    elseif cmd == "team" then
        local want = (arg:lower():find("red") and 1) or (arg:lower():find("blue") and 0)
        if want == nil then say("use !team red or !team blue")
        else
            pcall(function() pc:RequestTeamServer(want) end)
            pcall(function() pc.PlayerState.ChosenTeamID = want end)
            say("you are now " .. TEAM_NAME[want], want)
        end
    elseif cmd == "spectate" or cmd == "spec" then
        -- cycle through the other team's players (or anyone when not racing)
        CT.specIdx = CT.specIdx or {}
        local key = tostring(pc:GetFullName())
        local targets = {}
        for _, c in ipairs(chars()) do if c ~= me and ((not isRace()) or teamOf(c) ~= team) then targets[#targets + 1] = c end end
        if #targets == 0 then say("nobody to spectate")
        else
            CT.specIdx[key] = ((CT.specIdx[key] or 0) % #targets) + 1
            local t = targets[CT.specIdx[key]]
            pcall(function() pc:SetViewTargetWithBlend(t, 0.4, 0, 0, false) end)
            say("spectating - !spectate for next, !me to return")
        end
    elseif cmd == "me" then
        if me then pcall(function() pc:SetViewTargetWithBlend(me, 0.4, 0, 0, false) end) end
    elseif cmd == "rematch" then
        resetRace(); say("REMATCH - reloading the map, everyone stays connected")
        CT.extraSpawns = 0; CT.startCalls = 0
        ExecuteWithDelay(2500, function() ExecuteInGameThread(function()
            local ksl = StaticFindObject("/Script/Engine.Default__KismetSystemLibrary")
            local ok, err = pcall(function() ksl:ExecuteConsoleCommand(pc, "ServerTravel /Game/Levels/L_Game02?listen", pc) end)
            log("rematch servertravel: " .. tostring(ok) .. " " .. tostring(err))
        end) end)
    elseif cmd == "bots" and CT.devBots then
        -- DEV: add N local "bot" players (engine CreatePlayer) so lobby/teams/chains/race logic can be tested solo
        local n = tonumber(arg) or 5
        local gsl = StaticFindObject("/Script/Engine.Default__GameplayStatics")
        for _, gv in ipairs(FindAllOf("GameViewportClient") or {}) do
            pcall(function() gv.MaxSplitscreenPlayers = 8 end)
            pcall(function() log("MaxSplitscreenPlayers=" .. tostring(gv.MaxSplitscreenPlayers)) end)
        end
        local made = 0
        for i = 1, n do
            local ok, pcNew = pcall(function() return gsl:CreatePlayer(pc, -1, true) end)
            if ok and valid(pcNew) then made = made + 1 else log("CreatePlayer failed: " .. tostring(pcNew)) end
        end
        ExecuteWithDelay(1500, function() ExecuteInGameThread(function()
            for _, ps in ipairs(FindAllOf("PS_Lobby_C") or {}) do
                if valid(ps) then pcall(function() if ps.ChosenChar == 0 then ps.ChosenChar = 1 end end) end
            end
        end) end)
        say(string.format("added %d bots", made))
    elseif cmd == "botsat" and CT.devBots then
        -- DEV: teleport every non-host character of a team: !botsat blue|red x y z
        local tn, x, y, zz = arg:match("(%a+)%s+(%-?[%d%.]+)%s+(%-?[%d%.]+)%s+(%-?[%d%.]+)")
        local want = tn and (tn:lower() == "red" and 1 or 0)
        if want then
            local i = 0
            for _, c in ipairs(chars()) do
                if teamOf(c) == want then tpChar(c, tonumber(x) + i * 90, tonumber(y), tonumber(zz) + 50, 0); i = i + 1 end
            end
            say(string.format("moved %d %s players", i, TEAM_NAME[want]))
        end
    elseif cmd == "play" and CT.devBots then
        for _, wdg in ipairs(FindAllOf("W_Lobby_C") or {}) do
            if valid(wdg) then
                pcall(function() wdg.Ready = true end)
                local ok, err = pcall(function() wdg:BndEvt__W_Lobby_W_Button_K2Node_ComponentBoundEvent_0_OnClicked__DelegateSignature() end)
                log("play pressed: " .. tostring(ok) .. " " .. tostring(err))
            end
        end
        for _, wdg in ipairs(FindAllOf("W_ConfirmPlay_C") or {}) do log("confirm dialog present") end
    elseif cmd == "gs" and CT.devBots then
        -- DEV: !gs <Property> [true|false|number]  read/write a GS_Game property
        local gs = GS(); local k, v = arg:match("^(%S+)%s*(%S*)$")
        if gs and k then
            if v ~= "" then
                local val = (v == "true") and true or ((v == "false") and false or tonumber(v))
                pcall(function() gs[k] = val end)
            end
            local ok, cur = pcall(function() return gs[k] end)
            log("GS." .. k .. " = " .. tostring(ok and cur))
        end
    elseif cmd == "botsready" and CT.devBots then
        -- bots never run the client-side "levels loaded" report; real players do. Mark them loaded.
        for _, ps in ipairs(FindAllOf("PS_Lobby_C") or {}) do
            pcall(function() ps.BeginLevelsLoaded = true end)
            pcall(function() if ps.ChosenChar == 0 then ps.ChosenChar = 1 end end)
        end
        local gs = GS(); if gs then pcall(function() gs:CheckSpawnPlayersAfterLoading() end) end
        say("bots marked as loaded")
    elseif cmd == "state" and CT.devBots then
        local gs = GS()
        local function g(o, k) local ok, v = pcall(function() return o[k] end); return ok and tostring(v) or "err" end
        if gs then
            log(string.format("GS GameBegun=%s CharactersAreAttached=%s SpawnedCharacterIndex=%s PreviousPlayerNum=%s Timer=%s",
                g(gs, "GameBegun"), g(gs, "CharactersAreAttached"), g(gs, "SpawnedCharacterIndex"), g(gs, "PreviousPlayerNum"), g(gs, "Timer")))
            pcall(function() log("GS PlayerArray=" .. gs.PlayerArray:GetArrayNum()) end)
        end
        for i, ps in ipairs(FindAllOf("PS_Lobby_C") or {}) do
            log(string.format("PS%d BeginLevelsLoaded=%s ChosenChar=%s Team=%s", i, g(ps, "BeginLevelsLoaded"), g(ps, "ChosenChar"), g(ps, "ChosenTeamID")))
        end
        for i, p in ipairs(FindAllOf("PC_Game_C") or {}) do
            local okl, l = pcall(function() return p:IsLocalController() end)
            log(string.format("PC%d local=%s pawn=%s", i, tostring(okl and l), g(p, "Pawn")))
        end
        local gi = GI(); if gi then log("GI PlayersInSession=" .. g(gi, "PlayersInSession")) end
    elseif cmd == "tptrace" and CT.devBots and me then
        -- DEV: teleport, then log position + a few movement fields every 100 ms for 3 s
        local x, y, zz = arg:match("(%-?[%d%.]+)%s+(%-?[%d%.]+)%s+(%-?[%d%.]+)")
        x, y, zz = tonumber(x), tonumber(y), tonumber(zz)
        tpChar(me, x, y, zz, 0)
        for i = 1, 30 do
            ExecuteWithDelay(i * 100, function() ExecuteInGameThread(function()
                if not valid(me) then return end
                local l = me:K2_GetActorLocation()
                local function g(k) local ok, v = pcall(function() return me[k] end); if ok and type(v) == "userdata" then local ok2, s = pcall(function() return string.format("(%.0f,%.0f,%.0f)", v.X, v.Y, v.Z) end); return ok2 and s or "?" end; return tostring(ok and v) end
                local mode = "?"; pcall(function() mode = tostring(me.CharacterMovement.MovementMode) end)
                local sp = "?"; pcall(function() local s = me.Sphere:K2_GetComponentLocation(); sp = string.format("(%.0f,%.0f,%.0f)", s.X, s.Y, s.Z) end)
                log(string.format("trace %2d actor=(%.0f,%.0f,%.0f) d=%.0f mode=%s sphere=%s clientRep=%s serverRep=%s tele=%s",
                    i, l.X, l.Y, l.Z, math.sqrt((l.X - x) ^ 2 + (l.Y - y) ^ 2 + (l.Z - zz) ^ 2), mode, sp, g("ClientRepLocation"), g("ServerRepLocation"), g("IsTeleporting")))
            end) end)
        end
    elseif cmd == "widgets" and CT.devBots then
        -- DEV: list visible user widgets and the widget tree of anything that looks like a pause menu
        for _, wdg in ipairs(FindAllOf("UserWidget") or {}) do
            local okv, vis = pcall(function() return wdg:IsInViewport() end)
            if okv and vis then
                local cn = wdg:GetClass():GetFName():ToString()
                log("widget in viewport: " .. cn .. "  " .. wdg:GetFullName())
                if cn:lower():find("pause") or cn:lower():find("menu") or cn:lower():find("escape") then
                    pcall(function()
                        wdg:GetClass():ForEachProperty(function(p)
                            local n = p:GetFName():ToString()
                            local okw, v = pcall(function() return wdg[n] end)
                            if okw and type(v) == "userdata" then
                                local okc, c2 = pcall(function() return v:GetClass():GetFName():ToString() end)
                                if okc then log("   " .. n .. " : " .. c2) end
                            end
                        end)
                    end)
                end
            end
        end
    elseif cmd == "wtree" and CT.devBots then
        -- DEV: dump the widget tree of a widget class: !wtree W_SettingsMain_C
        local target = FindFirstOf(arg ~= "" and arg or "W_SettingsMain_C")
        if not valid(target) then log("wtree: not found"); return end
        local lines = {}
        local function walk(wd, depth)
            if not valid(wd) or depth > 12 then return end
            local cn = wd:GetClass():GetFName():ToString()
            local nm = wd:GetFName():ToString()
            local txt = ""
            pcall(function() txt = " '" .. wd:GetText():ToString() .. "'" end)
            local vis = ""; pcall(function() vis = " vis=" .. tostring(wd:GetVisibility()) end)
            lines[#lines + 1] = string.rep("  ", depth) .. cn .. " " .. nm .. txt .. vis
            local okc, n = pcall(function() return wd:GetChildrenCount() end)
            if okc and n then
                for i = 0, n - 1 do local okg, ch = pcall(function() return wd:GetChildAt(i) end); if okg then walk(ch, depth + 1) end end
            end
            pcall(function() local inner = wd.WidgetTree.RootWidget; if valid(inner) and inner ~= wd then walk(inner, depth + 1) end end)
            pcall(function() local c0 = wd:GetContent(); if valid(c0) then walk(c0, depth + 1) end end)
        end
        pcall(function() walk(target.WidgetTree.RootWidget, 0) end)
        local f = io.open(DATA_DIR .. "wtree.txt", "w"); if f then f:write(table.concat(lines, "\n")); f:close() end
        log("wtree: " .. #lines .. " widgets -> wtree.txt")
    elseif cmd == "funcs" and CT.devBots then
        -- DEV: !funcs /V_WidgetEssentials/Widgets/W_Button.W_Button_C  -> functions + props to funcs.txt (append)
        local cls = StaticFindObject(arg)
        local lines = { "== " .. arg .. " valid=" .. tostring(valid(cls)) }
        if valid(cls) then
            pcall(function()
                cls:ForEachFunction(function(fn)
                    local ps = {}
                    pcall(function() fn:ForEachProperty(function(p) local n = p:GetFName():ToString(); if not n:find("^CallFunc_") and not n:find("^K2Node_") and not n:find("^Temp_") then ps[#ps + 1] = n end end) end)
                    lines[#lines + 1] = "  fn " .. fn:GetFName():ToString() .. "(" .. table.concat(ps, ", ") .. ")"
                end)
                cls:ForEachProperty(function(p) lines[#lines + 1] = "  prop " .. p:GetFName():ToString() .. " : " .. p:GetClass():GetFName():ToString() end)
            end)
        end
        local f = io.open(DATA_DIR .. "funcs.txt", "a"); if f then f:write(table.concat(lines, "\n") .. "\n"); f:close() end
        log("funcs: " .. #lines)
    elseif cmd == "fxinfo" and CT.devBots and me then
        local function g(f) local ok, v = pcall(f); return ok and tostring(v) or "err" end
        log("fxinfo scale=" .. g(function() local s = me:GetActorScale3D(); return string.format("%.2f", s.X) end)
            .. " meshScale=" .. g(function() local s = me.Mesh:K2_GetComponentScale(); return string.format("%.2f", s.X) end)
            .. " capsuleHalf=" .. g(function() return me.CapsuleComponent:GetScaledCapsuleHalfHeight() end)
            .. " grav=" .. g(function() return me.GravityForce end)
            .. " jump=" .. g(function() return me.JumpForce end)
            .. " walk=" .. g(function() return me.MaxWalkSpeed end)
            .. " damping=" .. g(function() return me.Sphere:GetLinearDamping() end))
    elseif cmd == "who" then
        for _, c in ipairs(chars()) do
            local l = c:K2_GetActorLocation()
            local n = 0; pcall(function() local out = {}; c["Get Num Attached Characters"](c, false, false, out); n = out.Count or 0 end)
            local short = function(o) return (o:GetFName():ToString():gsub("BPC_Character_Sumo_C_", "#")) end
            local att = {}
            for _, key in ipairs({ "Rep Attached Characters", "InitialAttachedCharacters", "AttachedCharacters" }) do
                pcall(function()
                    c[key]:ForEach(function(_, e) local o = e:get(); if valid(o) then att[#att + 1] = key:sub(1, 3) .. ":" .. short(o) .. "(" .. (TEAM_NAME[teamOf(o)] or "?") .. ")" end end)
                end)
            end
            log(string.format("%s team=%s z=%.0f attached=[%s]", short(c), TEAM_NAME[teamOf(c)] or "?", l.Z, table.concat(att, " ")))
        end
    elseif cmd == "fixspawn" then local n = CT.fixMissingSpawns(); say("spawned " .. n .. " missing player(s)")
    elseif cmd == "balance" then CT.balanceTeams()
    elseif cmd == "reset" then resetRace(); say("race clock reset")
    elseif cmd == "start" then startClock("!start"); say("clock started")
    elseif isRace() and state.raceStart and not state.finished[team] then
        say("practice commands are off during a live race")
    elseif cmd == "save" then state.saved[team] = snapshot(team); say("position saved", isRace() and team or nil)
    elseif cmd == "load" then
        if state.saved[team] then restore(state.saved[team]); say("position loaded") else say("nothing saved yet - use !save") end
    elseif cmd == "mark" and me and arg ~= "" then
        local l = me:K2_GetActorLocation(); local r = me:K2_GetActorRotation()
        state.skips[arg:gsub("%s+", "_")] = { x = l.X, y = l.Y, z = l.Z, yaw = r.Yaw }; saveSkips()
        say("skip '" .. arg .. "' saved")
    elseif cmd == "tp" then
        local s = state.skips[arg:gsub("%s+", "_")]
        if s then tpTeamTo(team, s.x, s.y, s.z, s.yaw); say("teleported to " .. arg) else say("unknown skip - !skips to list") end
    elseif cmd == "skips" then
        local names = {}; for n in pairs(state.skips) do names[#names + 1] = n end; table.sort(names)
        say(#names > 0 and ("skips: " .. table.concat(names, ", ")) or "no skips yet - stand somewhere and type !mark <name>")
    elseif cmd == "tpxyz" then
        local x, y, zz = arg:match("(%-?[%d%.]+)%s+(%-?[%d%.]+)%s+(%-?[%d%.]+)")
        if x then tpTeamTo(team, tonumber(x), tonumber(y), tonumber(zz), 0); say("teleported") end
    elseif cmd == "top" then
        local e = FindFirstOf("BP_EndCinematic_C"); local l = valid(e) and e:K2_GetActorLocation() or { X = 67873, Y = -20317, Z = 368365 }
        tpTeamTo(team, l.X, l.Y, l.Z + 150, 0); say("teleported to the top")
    end  -- unknown commands are ignored (other mods may use them)
end


-- Chat poller: the SendMessageSRV hook does not fire for typed chat (it's an RPC). Instead read new entries
-- from GS_Game.Tchat (array of S_TchatElement: Playername_2_..., Message_4_...) and match the sender by name.
CT.chatSeen = nil
local CHAT_FIELDS = { Playername = "Playername_2_61BD72644F6167A7C06BDEB30F4246AA", Message = "Message_4_8C914A0F473A572E93CAF580FB02CB0D" }
local function fieldOf(el, prefix)
    local val
    pcall(function() val = el[CHAT_FIELDS[prefix]] end)
    if val == nil then
        pcall(function()
            el:GetStruct():ForEachProperty(function(p)
                local k = p:GetFName():ToString()
                if k:sub(1, #prefix) == prefix then val = el[k] end
            end)
        end)
    end
    if val == nil then return nil end
    local ok, s = pcall(function() return val:ToString() end)
    return ok and s or tostring(val)
end
local function pcByName(name)
    for _, pc in ipairs(FindAllOf("PC_Game_C") or {}) do
        local ok, n = pcall(function() return pc.PlayerState:GetPlayerName():ToString() end)
        if ok and n == name then return pc end
    end
end
LoopAsync(300, function()
    if not state.enabled or not isHost() then return false end
    ExecuteInGameThread(function()
        local gs = GS(); if not gs then CT.chatSeen = nil; return end
        local okn, n = pcall(function() return gs.Tchat:GetArrayNum() end)
        if not okn then return end
        if CT.chatSeen == nil or n < CT.chatSeen then CT.chatSeen = n; return end
        for i = CT.chatSeen + 1, n do
            local el; pcall(function() el = gs.Tchat[i] end)
            if el then
                local who = fieldOf(el, "Playername") or ""
                local msg = fieldOf(el, "Message") or ""
                if msg:sub(1, 1) == "!" and who ~= TAG then
                    local pc = pcByName(who) or FindFirstOf("PC_Game_C")
                    onCommand(pc, msg)
                end
            end
        end
        CT.chatSeen = n
    end)
    return false
end)

-- ---------- section triggers ----------
pcall(function()
    CT.hookLater("/Game/Blueprint/BiomeText/BiomeText_BP.BiomeText_BP_C:BndEvt__BiomeText_BP_Box_K2Node_ComponentBoundEvent_0_ComponentBeginOverlapSignature__DelegateSignature",
        function(ctx, overlapped, other)
            local biome = ctx:get(); local o = other:get()
            ExecuteInGameThread(function() onBiome(biome, o) end)
        end)
end)

-- race countdown finished -> start the clock
pcall(function()
    CT.hookLater("/Game/Blueprint/Gameplay/GS_Game.GS_Game_C:CheckCountdownOver", function()
        if state.enabled and isHost() and not state.raceStart then startClock("race countdown") end
    end)
end)

-- ---------- 3v3 race lobby ----------
-- W_Lobby recomputes Ready every 0.5 s; in Race (mode 5) it requires NumPlayers == 4 exactly (shipping build).
-- Re-apply Ready for 5-6 players. The lobby only has 4 pedestals, so players 5-6 can't pick a skin:
-- require min(players, 4) selected characters.
local RACE_MINUTES = 180   -- first-to-top race: the vanilla 30-min "highest wins" timer becomes a safety cap
LoopAsync(250, function()
    if not state.enabled or not isHost() then return false end
    ExecuteInGameThread(function()
        local gi = GI(); if not gi then return end
        local okm, mode = pcall(function() return gi.SelectedGameMode end)
        if not okm or mode ~= 5 then return end
        for _, wdg in ipairs(FindAllOf("W_Lobby_C") or {}) do
            if valid(wdg) then
                local players, selected = 0, 0
                for _, ps in ipairs(FindAllOf("PS_Lobby_C") or {}) do
                    if valid(ps) then
                        players = players + 1
                        local okc, ch = pcall(function() return ps.ChosenChar end)
                        if okc and ch and ch ~= 0 then selected = selected + 1 end
                    end
                end
                if players >= 5 and players <= MAX_PLAYERS and selected >= 4 then
                    pcall(function() wdg.Ready = true end)
                    pcall(function() wdg.W_PlayButton:SetRenderOpacity(1.0) end)
                end
            end
        end
        local gs = GS()
        if gs then pcall(function() if gs.InitialCountdown < RACE_MINUTES * 60 and not gs.GameBegun then gs.InitialCountdown = RACE_MINUTES * 60 end end) end
    end)
    return false
end)

-- The level's BP_CustomPlayerStart has exactly 4 spawn capsules, so GS_Game.FindPlayerStart fails for players 5-6
-- ("No playerstart found" -> no character). Post-hook: when it fails, hand back a transform beside the start.
CT.extraSpawns = 0
pcall(function()
    CT.hookLater("/Game/Blueprint/Gameplay/GS_Game.GS_Game_C:FindPlayerStart", function() end,
        function(ctx, transformP, retP)
            if not state.enabled then return end
            CT.startCalls = (CT.startCalls or 0) + 1
            local ok, found = pcall(function() return retP:get() end)
            log("FindPlayerStart call " .. CT.startCalls .. " found=" .. tostring(found))
            -- the 4 capsules get reused (blocked spawn) or run out from the 5th player on
            if ok and found and CT.startCalls <= 4 then return end
            local ps = FindFirstOf("BP_CustomPlayerStart_C")
            local base = (valid(ps) and ps:K2_GetActorLocation()) or { X = 66760, Y = -7500, Z = 3210 }
            CT.extraSpawns = CT.extraSpawns + 1
            local off = CT.extraSpawns * 140
            local okset = pcall(function()
                transformP:set({
                    Rotation = { X = 0, Y = 0, Z = 0, W = 1 },
                    Translation = { X = base.X - 250, Y = base.Y + off, Z = base.Z + 120 },
                    Scale3D = { X = 1, Y = 1, Z = 1 },
                })
                retP:set(true)
            end)
            log("extra player start #" .. CT.extraSpawns .. " (" .. tostring(okset) .. ")")
        end)
end)

pcall(function()
    CT.hookLater("/Game/Blueprint/Gameplay/GS_Game.GS_Game_C:ReceiveBeginPlay", function()
        CT.startCalls = 0; CT.extraSpawns = 0; CT.sections = nil; CT.spawnFixDone = false; resetRace()
    end)
end)

-- Players 5-6 get no character (only 4 spawn capsules). After the game's own spawn pass, spawn the missing ones
-- with PC_Game:SumoSpawnCharacter beside the start and chain them to their team.
local function hasCharacter(pc)
    local ok, p = pcall(function() return pc.Pawn end)
    return ok and valid(p) and p:GetClass():GetFName():ToString():find("Character") ~= nil
end
function CT.fixMissingSpawns()
    local gs = GS(); if not gs then return 0 end
    local base = { X = 66760, Y = -7500, Z = 3210 }
    local st = FindFirstOf("BP_CustomPlayerStart_C"); if valid(st) then base = st:K2_GetActorLocation() end
    local fixed = 0
    for _, pc in ipairs(FindAllOf("PC_Game_C") or {}) do
        if valid(pc) and not hasCharacter(pc) then
            local ps = pc.PlayerState
            local function g(k, d) local ok, v = pcall(function() return ps[k] end); if ok and v ~= nil then return v end; return d end
            fixed = fixed + 1
            local before = {}
            for _, c in ipairs(chars()) do before[c:GetFullName()] = true end
            local xf ={ Rotation = { X = 0, Y = 0, Z = 0, W = 1 },
                Translation = { X = base.X - 250, Y = base.Y + fixed * 160, Z = base.Z + 120 }, Scale3D = { X = 1, Y = 1, Z = 1 } }
            local ok, err = pcall(function()
                pc:SumoSpawnCharacter(xf, true, g("ChosenCharacterName", ""), g("ChosenChar", 1), g("ChosenTeamID", 0),
                    g("Chosen Gender", 0), g("Chosen Body", 0), g("Chosen Head", 0), g("Chosen Hair", 0), g("ChosenChain", 0))
            end)
            log("spawned missing player " .. fixed .. ": " .. tostring(ok) .. " " .. tostring(err))
            -- SumoSpawnCharacter doesn't possess for these extra players: find the new pawn and possess it
            for _, c in ipairs(chars()) do
                if not before[c:GetFullName()] then
                    local okp, ep = pcall(function() pc:Possess(c) end)
                    log("possess new character: " .. tostring(okp) .. " " .. tostring(ep) .. " -> " .. tostring(hasCharacter(pc)))
                    break
                end
            end
        end
    end
    -- the game waits until every player has a character before AttachPlayersAndBeginGame; kick it ourselves
    ExecuteWithDelay(2500, function() ExecuteInGameThread(function()
        local okA, att = pcall(function() return gs.CharactersAreAttached end)
        if okA and not att then
            -- GS Tick only re-checks "spawned >= players in session" while CountSpawnedCharacter is true
            pcall(function() gs.CountSpawnedCharacter = true end)
            log("re-armed spawn check (CountSpawnedCharacter=true)")
        end
    end) end)
    return fixed
end
-- auto: once characters are attached in a race, fill in missing ones
LoopAsync(2000, function()
    if not state.enabled or not isHost() then return false end
    ExecuteInGameThread(function()
        local gs = GS(); if not gs then return end
        local okA, att = pcall(function() return gs.CharactersAreAttached end)
        local okB, begun = pcall(function() return gs.GameBegun end)
        if not (okB and begun) or (okA and att) or CT.spawnFixDone then CT.missingSince = nil; return end
        local pcs, withChar = 0, 0
        for _, pc in ipairs(FindAllOf("PC_Game_C") or {}) do
            if valid(pc) then pcs = pcs + 1; if hasCharacter(pc) then withChar = withChar + 1 end end
        end
        if withChar == 0 or withChar >= pcs then CT.missingSince = nil; return end
        CT.missingSince = CT.missingSince or os.time()
        if os.time() - CT.missingSince >= 6 then   -- game's own spawn pass is done and stuck
            CT.spawnFixDone = true
            local n = CT.fixMissingSpawns()
            say(string.format("spawned %d extra player(s) for 3v3", n))
        end
    end)
    return false
end)

-- !balance (host): even teams by join order, 0,1,0,1... (Blue/Red)
local function balanceTeams()
    local i = 0
    for _, pc in ipairs(FindAllOf("PC_Game_C") or {}) do
        if valid(pc) then
            local tm = i % 2
            pcall(function() pc:RequestTeamServer(tm) end)
            pcall(function() pc.PlayerState.ChosenTeamID = tm end)
            i = i + 1
        end
    end
    say(string.format("teams balanced (%d players)", i))
end
CT.balanceTeams = balanceTeams

-- ---------- fun controls, pushing, outfits, side panel (fun.lua) ----------
do
    local API = {
            CT = CT, state = state, TEAM_NAME = TEAM_NAME, DATA_DIR = DATA_DIR, TAG = TAG,
            log = log, valid = valid, GS = GS, GI = GI, now = now, fmt = fmt, isHost = isHost, say = say,
            chars = chars, teamOf = teamOf, z = z, pct = pct, isRace = isRace,
            tpChar = tpChar, tpTeamTo = tpTeamTo, saveSkips = saveSkips,
            onCommand = onCommand, balanceTeams = balanceTeams,
    }
    for _, modName in ipairs({ "fun", "menu" }) do
        local okf, setup = pcall(require, modName)
        if okf and type(setup) == "function" then
            local okr, err = pcall(setup, API)
            if not okr then log(modName .. ".lua failed: " .. tostring(err)) end
        else
            log(modName .. ".lua not loaded: " .. tostring(setup))
        end
    end
end

-- ---------- startup ----------
LoopAsync(2000, function()
    local r = versionCheck()
    if r ~= nil then loadSkips(); return true end
    return false
end)

-- F9 (host): unlock the lobby Play button even when teams aren't 2v2 (solo tests / uneven teams)
RegisterKeyBind(Key.F9, function() ExecuteInGameThread(function()
    for _, wdg in ipairs(FindAllOf("W_Lobby_C") or {}) do
        if valid(wdg) then
            pcall(function() wdg:CheatActivatePlayButton() end)
            pcall(function() wdg.Ready = true end)
            pcall(function() wdg.AllCharsLoaded = true end)
            local b = wdg.W_PlayButton
            if valid(b) then
                pcall(function() b:SetIsEnabled(true) end)
                pcall(function() b:SetRenderOpacity(1.0) end)
                pcall(function() b:SetVisibility(0) end)
            end
            log("play button unlocked")
        end
    end
end) end)

-- F10 (host, dev): force the game start sequence without the lobby Play button
RegisterKeyBind(Key.F10, function() ExecuteInGameThread(function()
    local gs = GS(); if not gs then return end
    log("forcing start: SwitchToGameMode / AttachPlayersAndBeginGame")
    for _, pc in ipairs(FindAllOf("PC_Game_C") or {}) do pcall(function() pc:SwitchToGameMode() end) end
    ExecuteWithDelay(1500, function() ExecuteInGameThread(function()
        pcall(function() gs:AttachPlayersAndBeginGame() end)
    end) end)
end) end)

-- F11 (host, dev): run each line of data/devcmd.txt as a chat command from the host, 2.5 s apart
RegisterKeyBind(Key.F11, function()
    local f = io.open(DATA_DIR .. "devcmd.txt", "r"); if not f then log("no devcmd.txt"); return end
    local cmds = {}; for line in f:lines() do if line:match("%S") then cmds[#cmds + 1] = line end end; f:close()
    for i, c in ipairs(cmds) do
        ExecuteWithDelay(i * 2500, function() ExecuteInGameThread(function()
            local pc = FindFirstOf("PC_Game_C"); log("devcmd: " .. c); onCommand(pc, c)
        end) end)
    end
end)

-- DEV: no-input command runner. Drop lines into data/devcmd_run.txt; the mod runs them (2 s apart) and deletes the file.
if CT.devBots then
    LoopAsync(1000, function()
        local path = DATA_DIR .. "devcmd_run.txt"
        local f = io.open(path, "r"); if not f then return false end
        local cmds = {}; for line in f:lines() do if line:match("%S") then cmds[#cmds + 1] = line end end; f:close()
        os.remove(path)
        for i, c in ipairs(cmds) do
            ExecuteWithDelay(i * 2000, function() ExecuteInGameThread(function()
                local pc = nil
                for _, p in ipairs(FindAllOf("PC_Game_C") or {}) do
                    local ok, loc = pcall(function() return p:IsLocalController() end)
                    if ok and loc then pc = p; break end
                end
                log("devcmd: " .. c); onCommand(pc, c)
            end) end)
        end
        return false
    end)
end

RegisterKeyBind(Key.F8, function() ExecuteInGameThread(function() say("Chained Teams " .. CT.VERSION .. " ready. Type !help") end) end)
log("loaded " .. CT.VERSION)
