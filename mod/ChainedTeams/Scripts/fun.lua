-- fun.lua: fun controls, pushing, chaos mode, outfits and the side-panel link for Chained Teams.
-- Loaded by main.lua, which passes in its helpers (A).
--
-- Host: settings come from the side panel (data/panel_cmd.txt) and are applied to every character.
-- Host announces them in chat as "Fun settings: ..."; players running the launcher read that line and
-- apply the same settings to their own character, so movement stays smooth for them.

return function(A)
    local CT, state, valid, log, say = A.CT, A.state, A.valid, A.log, A.say
    local GS, GI, chars, teamOf, isHost, isRace = A.GS, A.GI, A.chars, A.teamOf, A.isHost, A.isRace

    local DEFAULT = { gravity = 1, speed = 1, jump = 1, scale = 1, chain = 1, ice = false, push = false, chaos = false }
    local fx = {}
    for k, v in pairs(DEFAULT) do fx[k] = v end
    CT.fx = fx

    local base = {}          -- per character: original movement values
    local chaosEffect = nil  -- name of the running chaos effect
    local chaosSaved = nil

    -- ---------- applying settings to characters ----------
    local function cmc(c) local ok, m = pcall(function() return c.CharacterMovement end); if ok and valid(m) then return m end end
    local function key(c) local ok, k = pcall(function() return c:GetFullName() end); return ok and k or tostring(c) end

    local function baseOf(c)
        local k = key(c)
        if base[k] then return base[k] end
        local m = cmc(c); if not m then return nil end
        local b = {}
        pcall(function() b.g = m.GravityScale end)
        pcall(function() b.j = m.JumpZVelocity end)
        pcall(function() b.f = m.GroundFriction end)
        pcall(function() b.br = m.BrakingDecelerationWalking end)
        pcall(function() b.acc = m.MaxAcceleration end)
        -- chain length: any numeric max-distance style property on the character (best effort)
        b.chainProps = {}
        pcall(function()
            local cls = c:GetClass()
            while cls and cls:IsValid() do
                cls:ForEachProperty(function(p)
                    local n = p:GetFName():ToString()
                    if n:find("MaxDistance") or n:find("ChainLength") then
                        local okv, v = pcall(function() return c[n] end)
                        if okv and type(v) == "number" then b.chainProps[n] = v end
                    end
                end)
                local okS, sup = pcall(function() return cls:GetSuperStruct() end)
                if not okS or not sup or not sup:IsValid() then break end
                cls = sup
            end
        end)
        base[k] = b
        return b
    end

    local function applyTo(c)
        local m = cmc(c); if not m then return end
        local b = baseOf(c); if not b then return end
        if b.g then pcall(function() m.GravityScale = b.g * fx.gravity end) end
        if b.j then pcall(function() m.JumpZVelocity = b.j * fx.jump end) end
        pcall(function() c.CustomTimeDilation = fx.speed end)
        pcall(function() c:SetActorScale3D({ X = fx.scale, Y = fx.scale, Z = fx.scale }) end)
        if fx.ice then
            pcall(function() m.GroundFriction = 0.05 end)
            pcall(function() m.BrakingDecelerationWalking = 40 end)
            pcall(function() m.MaxAcceleration = (b.acc or 1500) * 0.35 end)
        else
            if b.f then pcall(function() m.GroundFriction = b.f end) end
            if b.br then pcall(function() m.BrakingDecelerationWalking = b.br end) end
            if b.acc then pcall(function() m.MaxAcceleration = b.acc end) end
        end
        for n, v in pairs(b.chainProps or {}) do pcall(function() c[n] = v * fx.chain end) end
    end

    local function myPawn()
        for _, pc in ipairs(FindAllOf("PC_Game_C") or {}) do
            local okl, l = pcall(function() return pc:IsLocalController() end)
            if okl and l then local ok, p = pcall(function() return pc.Pawn end); if ok and valid(p) then return p end end
        end
    end

    local function isDefault()
        for k, v in pairs(DEFAULT) do if fx[k] ~= v and k ~= "push" and k ~= "chaos" then return false end end
        return true
    end

    -- Host applies to everyone; a client (launcher, not host) applies to its own character only.
    -- ALS rewrites some movement values every frame, so re-apply often while anything is changed.
    local wasDefault = true
    LoopAsync(150, function()
        if state.enabled == false then return false end
        ExecuteInGameThread(function()
            local def = isDefault()
            if def and wasDefault then return end
            if isHost() then
                for _, c in ipairs(chars()) do applyTo(c) end
            else
                local p = myPawn(); if p then applyTo(p) end
            end
            wasDefault = def
        end)
        return false
    end)

    -- ---------- announcing settings (so launcher players mirror them) ----------
    local function fmtx(v) return string.format("%.2f", v):gsub("0+$", ""):gsub("%.$", "") end
    local function announce()
        say(string.format("Fun settings: gravity %sx, speed %sx, jump %sx, size %sx, chain %sx, ice %s, pushing %s, chaos %s",
            fmtx(fx.gravity), fmtx(fx.speed), fmtx(fx.jump), fmtx(fx.scale), fmtx(fx.chain),
            fx.ice and "on" or "off", fx.push and "on" or "off", fx.chaos and "on" or "off"))
    end
    CT.announceFun = announce

    -- clients: read the host's "Fun settings:" line from chat
    local CHAT_FIELDS = { Playername = "Playername_2_61BD72644F6167A7C06BDEB30F4246AA", Message = "Message_4_8C914A0F473A572E93CAF580FB02CB0D" }
    local seen = nil
    LoopAsync(500, function()
        ExecuteInGameThread(function()
            if isHost() then return end
            local gs = GS(); if not gs then seen = nil; return end
            local okn, n = pcall(function() return gs.Tchat:GetArrayNum() end)
            if not okn then return end
            if seen == nil or n < seen then seen = 0 end
            for i = seen + 1, n do
                local el; pcall(function() el = gs.Tchat[i] end)
                local msg = ""; pcall(function() msg = el[CHAT_FIELDS.Message]:ToString() end)
                local who = ""; pcall(function() who = el[CHAT_FIELDS.Playername]:ToString() end)
                if who == A.TAG and msg:find("^Fun settings:") then
                    local g, s, j, sc, ch, ice = msg:match("gravity ([%d%.]+)x, speed ([%d%.]+)x, jump ([%d%.]+)x, size ([%d%.]+)x, chain ([%d%.]+)x, ice (%a+)")
                    if g then
                        fx.gravity, fx.speed, fx.jump, fx.scale, fx.chain = tonumber(g), tonumber(s), tonumber(j), tonumber(sc), tonumber(ch)
                        fx.ice = (ice == "on")
                        wasDefault = false
                    end
                end
            end
            seen = n
        end)
        return false
    end)

    -- ---------- flinging ----------
    local function launch(c, x, y, zz)
        pcall(function() c:LaunchCharacter({ X = x, Y = y, Z = zz }, true, true) end)
    end
    local function fling(filterTeam)
        local n = 0
        for _, c in ipairs(chars()) do
            if filterTeam == nil or teamOf(c) == filterTeam then
                launch(c, math.random(-600, 600), math.random(-600, 600), 1800); n = n + 1
            end
        end
        return n
    end

    -- ---------- pushing ----------
    -- Teams pass through each other, so a push is a bump: run into a player from the other team
    -- (or, outside a race, anyone not on your own chain) and they get shoved away.
    local pushCooldown = {}
    local function vel(c) local ok, v = pcall(function() return c:GetVelocity() end); if ok and v then return v end; return { X = 0, Y = 0, Z = 0 } end
    local function loc(c) local ok, l = pcall(function() return c:K2_GetActorLocation() end); if ok and l then return l end end
    local function sameGroup(a, b)
        if isRace() then return teamOf(a) == teamOf(b) end
        local found = false
        pcall(function()
            a["Rep Attached Characters"]:ForEach(function(_, e) if e:get() == b then found = true end end)
        end)
        return found
    end
    LoopAsync(100, function()
        if not fx.push or state.enabled == false then return false end
        ExecuteInGameThread(function()
            if not isHost() then return end
            local list = chars()
            local t = os.clock()
            for _, a in ipairs(list) do
                local va = vel(a)
                local speed = math.sqrt(va.X * va.X + va.Y * va.Y)
                if speed > 250 then
                    local la = loc(a)
                    for _, b in ipairs(list) do
                        if a ~= b and la and not sameGroup(a, b) then
                            local lb = loc(b)
                            if lb then
                                local dx, dy, dz = lb.X - la.X, lb.Y - la.Y, lb.Z - la.Z
                                local d = math.sqrt(dx * dx + dy * dy)
                                if d < 130 and math.abs(dz) < 150 then
                                    local dot = (dx * va.X + dy * va.Y) / math.max(1, d * speed)
                                    local kb = key(b)
                                    if dot > 0.3 and (pushCooldown[kb] or 0) < t then
                                        pushCooldown[kb] = t + 1.2
                                        local nx, ny = dx / math.max(1, d), dy / math.max(1, d)
                                        launch(b, nx * 1100, ny * 1100, 380)
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end)
        return false
    end)

    -- ---------- chaos mode ----------
    local CHAOS = {
        { "Moon gravity", function() fx.gravity = 0.3 end },
        { "Tiny people", function() fx.scale = 0.5 end },
        { "Giants", function() fx.scale = 1.8 end },
        { "Super jump", function() fx.jump = 2.5 end },
        { "Ice floor", function() fx.ice = true end },
        { "Fast forward", function() fx.speed = 1.6 end },
        { "Slow motion", function() fx.speed = 0.6 end },
        { "Everybody fly", function() fling(nil) end },
    }
    local nextChaos = nil
    LoopAsync(1000, function()
        if not fx.chaos or state.enabled == false then nextChaos = nil; return false end
        ExecuteInGameThread(function()
            if not isHost() or not GS() then return end
            local t = os.time()
            if nextChaos == nil then nextChaos = t + 30 end
            if chaosEffect and t >= nextChaos - 70 then
                -- effect lasts 20 s (next one comes 90 s after the previous started)
                for k, v in pairs(chaosSaved) do fx[k] = v end
                chaosEffect = nil; chaosSaved = nil; wasDefault = false
                announce()
            end
            if t >= nextChaos then
                local e = CHAOS[math.random(1, #CHAOS)]
                chaosSaved = { gravity = fx.gravity, speed = fx.speed, jump = fx.jump, scale = fx.scale, ice = fx.ice }
                e[2](); chaosEffect = e[1]; wasDefault = false
                say("CHAOS: " .. e[1] .. "!")
                announce()
                nextChaos = t + 90
            end
        end)
        return false
    end)

    -- ---------- outfits ----------
    local function rowCount(path)
        local dt = StaticFindObject(path)
        if not valid(dt) then return 0 end
        local lib = StaticFindObject("/Script/Engine.Default__DataTableFunctionLibrary")
        local out = {}
        local ok = pcall(function() lib:GetDataTableRowNames(dt, out) end)
        local n = 0
        if ok and out.OutRowNames then pcall(function() n = out.OutRowNames:GetArrayNum() end) end
        return n
    end
    local function randomOutfit(ps)
        local bodies = math.max(1, rowCount("/Game/Blueprint/Characters/CharacterData/DT_CharacterBody.DT_CharacterBody"))
        local heads = math.max(1, rowCount("/Game/Blueprint/Characters/CharacterData/DT_CharacterHead.DT_CharacterHead"))
        local hairs = math.max(1, rowCount("/Game/Blueprint/Characters/CharacterData/DT_CharacterHair.DT_CharacterHair"))
        local chains = math.max(1, rowCount("/Game/Blueprint/Characters/CharacterData/DT_ChainCustomisation.DT_ChainCustomisation"))
        pcall(function() ps["Chosen Gender"] = math.random(0, 1) end)
        pcall(function() ps["Chosen Body"] = math.random(0, bodies - 1) end)
        pcall(function() ps["Chosen Head"] = math.random(0, heads - 1) end)
        pcall(function() ps["Chosen Hair"] = math.random(0, hairs - 1) end)
        pcall(function() ps.ChosenChain = math.random(0, chains - 1) end)
        log(string.format("outfit ranges body=%d head=%d hair=%d chain=%d", bodies, heads, hairs, chains))
    end

    -- ---------- panel commands ----------
    local function hostPC()
        for _, pc in ipairs(FindAllOf("PC_Game_C") or {}) do
            local okl, l = pcall(function() return pc:IsLocalController() end)
            if okl and l then return pc end
        end
    end
    local function pcByName(name)
        for _, pc in ipairs(FindAllOf("PC_Game_C") or {}) do
            local ok, n = pcall(function() return pc.PlayerState:GetPlayerName():ToString() end)
            if ok and n == name then return pc end
        end
    end
    local function clampNum(v, lo, hi) v = tonumber(v); if not v then return nil end; return math.max(lo, math.min(hi, v)) end

    local LIMITS = { gravity = { 0.1, 3 }, speed = { 0.5, 3 }, jump = { 0.5, 4 }, scale = { 0.3, 3 }, chain = { 0.5, 2 } }

    local function panelCommand(line)
        local w = {}
        for t in line:gmatch("%S+") do w[#w + 1] = t end
        local cmd = (w[1] or ""):lower()
        if cmd == "set" then
            local what, val = (w[2] or ""):lower(), (w[3] or ""):lower()
            if LIMITS[what] then
                local v = clampNum(val, LIMITS[what][1], LIMITS[what][2])
                if v then fx[what] = v; wasDefault = false; announce() end
            elseif what == "ice" or what == "push" or what == "chaos" then
                fx[what] = (val == "on" or val == "true" or val == "1"); wasDefault = false; announce()
                if what == "chaos" and not fx.chaos and chaosSaved then
                    for k, v in pairs(chaosSaved) do fx[k] = v end
                    chaosEffect = nil; chaosSaved = nil
                end
            end
        elseif cmd == "resetfun" then
            for k, v in pairs(DEFAULT) do fx[k] = v end
            chaosEffect = nil; chaosSaved = nil; wasDefault = false
            announce()
        elseif cmd == "fling" then
            say(string.format("WHEEE (%d players)", fling(nil)))
        elseif cmd == "flingteam" then
            local tm = (w[2] or ""):lower() == "red" and 1 or 0
            say(string.format("%s team goes flying", A.TEAM_NAME[tm]))
            fling(tm)
        elseif cmd == "team" and #w >= 3 then
            local side = w[#w]:lower()
            local name = table.concat(w, " ", 2, #w - 1)
            local tm = side == "red" and 1 or 0
            local pc = pcByName(name)
            if pc then
                pcall(function() pc:RequestTeamServer(tm) end)
                pcall(function() pc.PlayerState.ChosenTeamID = tm end)
                say(name .. " is now " .. A.TEAM_NAME[tm], tm)
            else say("player not found: " .. name) end
        elseif cmd == "tpplayer" and #w >= 3 then
            local skip = w[#w]
            local name = table.concat(w, " ", 2, #w - 1)
            local s = state.skips[skip]
            local pc = pcByName(name)
            local p; if pc then pcall(function() p = pc.Pawn end) end
            if s and valid(p) then A.tpChar(p, s.x, s.y, s.z + 50, s.yaw); say(name .. " teleported to " .. skip)
            else say("cannot teleport " .. name .. " to " .. skip) end
        elseif cmd == "delmark" and w[2] then
            state.skips[w[2]] = nil; A.saveSkips(); say("deleted spot " .. w[2])
        elseif cmd == "outfit" then
            local who = (w[2] or "random"):lower()
            local n = 0
            for _, ps in ipairs(FindAllOf("PS_Lobby_C") or {}) do
                local mine = false
                pcall(function() mine = ps:GetOwner():IsLocalController() end)
                if who == "randomall" or mine then randomOutfit(ps); n = n + 1 end
            end
            say(string.format("random outfit for %d player(s) - shows after the next rematch", n))
        else
            -- everything else is a normal chat command
            A.onCommand(hostPC(), "!" .. line)
        end
    end
    CT.panelCommand = panelCommand

    LoopAsync(500, function()
        local path = A.DATA_DIR .. "panel_cmd.txt"
        local f = io.open(path, "r"); if not f then return false end
        local lines = {}
        for raw in f:lines() do
            local l = raw:gsub("^\239\187\191", "")
            if l:match("%S") then lines[#lines + 1] = l end
        end
        f:close(); os.remove(path)
        ExecuteInGameThread(function()
            if not isHost() then say("the panel only works for the host"); return end
            for _, l in ipairs(lines) do
                local ok, err = pcall(panelCommand, l)
                if not ok then log("panel command failed: " .. l .. " -> " .. tostring(err)) end
            end
        end)
        return false
    end)

    -- ---------- state.json for the panel ----------
    local function js(s)
        s = tostring(s):gsub('\\', '\\\\'):gsub('"', '\\"'):gsub('\n', ' '):gsub('[%c]', '')
        return '"' .. s .. '"'
    end
    local recentLog = {}
    local origSay = A.say
    CT.recentLog = recentLog

    LoopAsync(1000, function()
        ExecuteInGameThread(function()
            local gs = GS()
            local parts = {}
            parts[#parts + 1] = '"version":' .. js(CT.VERSION)
            parts[#parts + 1] = '"inGame":' .. tostring(gs ~= nil)
            parts[#parts + 1] = '"isHost":' .. tostring(isHost() == true)
            parts[#parts + 1] = '"isRace":' .. tostring(isRace() == true)
            parts[#parts + 1] = '"raceRunning":' .. tostring(state.raceStart ~= nil)
            parts[#parts + 1] = '"raceTime":' .. js(state.raceStart and A.fmt(A.now() - state.raceStart) or "--:--")
            local pl = {}
            for _, pc in ipairs(FindAllOf("PC_Game_C") or {}) do
                local name = "?"; pcall(function() name = pc.PlayerState:GetPlayerName():ToString() end)
                local p; pcall(function() p = pc.Pawn end)
                local team, zz = "?", 0
                local okc = valid(p) and p:GetClass():GetFName():ToString():find("Character")
                if okc then team = A.TEAM_NAME[teamOf(p)] or "?"; zz = A.z(p)
                else pcall(function() team = A.TEAM_NAME[pc.PlayerState.ChosenTeamID] or "?" end) end
                pl[#pl + 1] = string.format('{"name":%s,"team":%s,"pct":%.1f,"z":%.0f}', js(name), js(team), A.pct(zz), zz)
            end
            parts[#parts + 1] = '"players":[' .. table.concat(pl, ",") .. "]"
            local sk = {}
            local names = {}; for n in pairs(state.skips or {}) do names[#names + 1] = n end; table.sort(names)
            for _, n in ipairs(names) do sk[#sk + 1] = js(n) end
            parts[#parts + 1] = '"skips":[' .. table.concat(sk, ",") .. "]"
            parts[#parts + 1] = string.format('"settings":{"gravity":%.2f,"speed":%.2f,"jump":%.2f,"scale":%.2f,"chain":%.2f,"ice":%s,"push":%s,"chaos":%s}',
                fx.gravity, fx.speed, fx.jump, fx.scale, fx.chain, tostring(fx.ice), tostring(fx.push), tostring(fx.chaos))
            local sp = {}
            for tm = 0, 1 do
                local rows = {}
                for _, s in ipairs((state.splits or {})[tm] or {}) do rows[#rows + 1] = "[" .. js(s.name) .. "," .. js(A.fmt(s.t)) .. "]" end
                sp[#sp + 1] = js(A.TEAM_NAME[tm]) .. ":[" .. table.concat(rows, ",") .. "]"
            end
            parts[#parts + 1] = '"splits":{' .. table.concat(sp, ",") .. "}"
            local lg = {}
            for _, l in ipairs(CT.chatLog or {}) do lg[#lg + 1] = js(l) end
            parts[#parts + 1] = '"log":[' .. table.concat(lg, ",") .. "]"
            local f = io.open(A.DATA_DIR .. "state.json.tmp", "w")
            if f then
                f:write("{" .. table.concat(parts, ",") .. "}")
                f:close()
                os.remove(A.DATA_DIR .. "state.json")
                os.rename(A.DATA_DIR .. "state.json.tmp", A.DATA_DIR .. "state.json")
            end
        end)
        return false
    end)

    log("fun controls ready")
end
