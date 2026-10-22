-- menu.lua: a "Mods" tab inside the game's own Esc menu (W_SettingsMain).
-- Uses the hidden DEV tab slot and the game's own W_Button / W_Slider widgets, so it matches the game's style.
-- Clicks are caught by hooking the shared click events of W_Button / W_Slider / W_Tab and matching the instance.

return function(A)
    local CT, state, valid, log, say = A.CT, A.state, A.valid, A.log, A.say
    local isHost = A.isHost

    local BUTTON_CLASS = "/V_WidgetEssentials/Widgets/W_Button.W_Button_C"
    local SLIDER_CLASS = "/V_WidgetEssentials/Widgets/W_Slider.W_Slider_C"
    local actions = {}        -- widget full name -> function()
    local sliders = {}        -- widget full name -> setting name
    local built = {}          -- settings widget full name -> { page = VerticalBox, menu = settings widget }
    local current = nil       -- the settings widget we built into most recently

    local function fname(o) local ok, n = pcall(function() return o:GetFullName() end); return ok and n or tostring(o) end

    local function localPC()
        for _, pc in ipairs(FindAllOf("PC_Game_C") or {}) do
            local okl, l = pcall(function() return pc:IsLocalController() end)
            if okl and l then return pc end
        end
    end

    -- run a command: host applies it directly, a friend sends it as a chat command to the host
    local function run(cmd)
        if isHost() then
            local ok, err = pcall(CT.panelCommand, cmd)
            if not ok then log("menu command failed: " .. cmd .. " -> " .. tostring(err)) end
        else
            local pc = localPC()
            if pc then pcall(function() pc:SendMessageSRV("!" .. cmd) end) end
        end
    end

    -- ---------- building widgets ----------
    local wbl = nil
    local function newButton(menu, text, onClick)
        wbl = wbl or StaticFindObject("/Script/UMG.Default__WidgetBlueprintLibrary")
        local cls = StaticFindObject(BUTTON_CLASS)
        local btn
        pcall(function() btn = wbl:Create(menu, cls, localPC()) end)
        if not valid(btn) then log("menu: could not create button"); return nil end
        -- copy the look of the game's "Nearest safe location" button
        pcall(function()
            local ref = menu.NearestSafeLocation_Button
            btn.FontSize = ref.FontSize
            btn.UnhoveredTextColor = ref.UnhoveredTextColor
            btn.HoveredTextColor = ref.HoveredTextColor
            btn.UnhoveredBorderColor = ref.UnhoveredBorderColor
            btn.HoveredBorderColor = ref.HoveredBorderColor
        end)
        local function label(b, s)
            pcall(function() b.Text = FText(s) end)
            pcall(function() b:SetText(FText(s)) end)
            pcall(function() b.W_MenuButtonText_C_0.Text = FText(s) end)
            pcall(function() b.W_MenuButtonText_C_0:SetText(FText(s)) end)
            pcall(function() b.W_MenuButtonText_C_0.TextBlock_31:SetText(FText(s)) end)
        end
        label(btn, text)
        -- the button resets its label when it is constructed on screen; set it again afterwards
        ExecuteWithDelay(100, function() ExecuteInGameThread(function() if valid(btn) then label(btn, text) end end) end)
        CT.menuLabel = label
        actions[fname(btn)] = onClick
        return btn
    end

    local function newHeader(menu, text)
        local cls = StaticFindObject("/Script/UMG.TextBlock")
        local tb
        pcall(function() tb = StaticConstructObject(cls, menu.WidgetTree, FName("CT_Header_" .. text:gsub("%W", ""))) end)
        if not valid(tb) then return nil end
        pcall(function() tb:SetText(FText(text)) end)
        -- same font as the game's "Teleport" heading
        pcall(function()
            local ref = menu.Teleportation_VerticalBox:GetChildAt(0)
            tb:SetFont(ref.Font)
            tb:SetColorAndOpacity(ref.ColorAndOpacity)
        end)
        return tb
    end

    local function newSlider(menu, label, setting, minV, maxV, step, value)
        wbl = wbl or StaticFindObject("/Script/UMG.Default__WidgetBlueprintLibrary")
        local cls = StaticFindObject(SLIDER_CLASS)
        local s
        pcall(function() s = wbl:Create(menu, cls, localPC()) end)
        if not valid(s) then return nil end
        pcall(function() s.MinValue = minV; s.MaxValue = maxV; s.StepSize = step; s.Identifier = setting end)
        pcall(function() s:SetSliderValue(value) end)
        sliders[fname(s)] = setting
        return s, newHeader(menu, label)
    end

    local function add(box, w, padTop)
        if not valid(w) then return end
        local slot
        pcall(function() slot = box:AddChildToVerticalBox(w) end)
        if slot then pcall(function() slot:SetPadding({ Left = 40, Top = padTop or 4, Right = 0, Bottom = 4 }) end) end
    end

    local function fmtx(v) return string.format("%.2fx", v) end

    -- (re)fill the Mods page
    local function fill(menu, page)
        actions = {}; sliders = {}
        pcall(function() page:ClearChildren() end)
        local fx = CT.fx or {}

        add(page, newHeader(menu, "Teleport"), 10)
        local names = {}
        for n in pairs(state.skips or {}) do names[#names + 1] = n end
        table.sort(names)
        if #names == 0 then add(page, newHeader(menu, "   (no saved spots yet)")) end
        for _, n in ipairs(names) do
            add(page, newButton(menu, "Go to: " .. n, function() run("tp " .. n) end))
        end
        add(page, newButton(menu, "Mark this spot", function()
            local i = 1
            while (state.skips or {})["spot" .. i] do i = i + 1 end
            run("mark spot" .. i)
            ExecuteWithDelay(300, function() ExecuteInGameThread(function() if current and valid(current.menu) and valid(current.page) then fill(current.menu, current.page) end end) end)
        end), 12)
        add(page, newButton(menu, "Delete last spot", function()
            if #names > 0 then run("delmark " .. names[#names]) end
            ExecuteWithDelay(300, function() ExecuteInGameThread(function() if current and valid(current.menu) and valid(current.page) then fill(current.menu, current.page) end end) end)
        end))
        add(page, newButton(menu, "Quick save position", function() run("save") end), 12)
        add(page, newButton(menu, "Quick load position", function() run("load") end))
        add(page, newButton(menu, "Go to the top", function() run("top") end))

        -- Achievements: only when the personal achievement mod (ChainedPersonal) is installed next to this one.
        -- Separate mod = separate Lua state, so talk through its files: read achievements.txt, write command.txt.
        local personalDir = A.DATA_DIR .. "../../ChainedPersonal/"
        local af = io.open(personalDir .. "achievements.txt", "r")
        if af then
            add(page, newHeader(menu, "Achievements"), 20)
            local locked = 0
            for line in af:lines() do
                local n, mark, name = line:match("^%s*(%d+)%s+%[(.)%]%s+%S+%s+(.-)%s+%-%s")
                if n and mark ~= "x" then
                    locked = locked + 1
                    add(page, newButton(menu, "Unlock: " .. name, function()
                        local cf = io.open(personalDir .. "command.txt", "a")
                        if cf then cf:write("ach " .. n .. "\n"); cf:close() end
                        say("unlocking: " .. name)
                        ExecuteWithDelay(2500, function() ExecuteInGameThread(function() if current and valid(current.menu) and valid(current.page) then fill(current.menu, current.page) end end) end)
                    end))
                end
            end
            af:close()
            if locked == 0 then
                add(page, newHeader(menu, "   (all achievements unlocked)"))
            else
                add(page, newButton(menu, "Unlock all achievements", function()
                    local cf = io.open(personalDir .. "command.txt", "a")
                    if cf then cf:write("ach all\n"); cf:close() end
                    say("unlocking all achievements")
                    ExecuteWithDelay(3000, function() ExecuteInGameThread(function() if current and valid(current.menu) and valid(current.page) then fill(current.menu, current.page) end end) end)
                end))
            end
            add(page, newButton(menu, "Collect all 10 wings", function()
                local cf = io.open(personalDir .. "command.txt", "a")
                if cf then cf:write("wings\n"); cf:close() end
                say("collecting all 10 wings")
            end))
        end

        if isHost() then
            add(page, newHeader(menu, "Fun"), 20)
            -- click-to-cycle buttons (the game's own slider widget ignores the mouse when created at runtime)
            local PRESETS = {
                gravity = { 1, 0.6, 0.3, 0.15, 2, 3 },
                speed = { 1, 1.3, 1.6, 2, 3, 0.6 },
                jump = { 1, 1.5, 2, 3, 4, 0.5 },
                scale = { 1, 1.5, 2, 3, 0.6, 0.3 },
                chain = { 1, 1.5, 2, 0.5 },
            }
            local function vtext(v) return (string.format("%.2f", v):gsub("0+$", ""):gsub("%.$", "")) .. "x" end
            local function cycle(label, key)
                local btn
                local function caption() return label .. ": " .. vtext((CT.fx and CT.fx[key]) or 1) .. "   (click to change)" end
                btn = newButton(menu, caption(), function()
                    local list = PRESETS[key]
                    local cur = (CT.fx and CT.fx[key]) or 1
                    local nextV = list[1]
                    for i, v in ipairs(list) do if math.abs(v - cur) < 0.01 then nextV = list[i % #list + 1] end end
                    run(string.format("set %s %.2f", key, nextV))
                    if CT.menuLabel then CT.menuLabel(btn, caption()) end
                end)
                add(page, btn)
            end
            cycle("Gravity", "gravity")
            cycle("Speed", "speed")
            cycle("Jump height", "jump")
            cycle("Player size", "scale")
            local function toggle(label, key)
                local btn
                btn = newButton(menu, label .. ": " .. (fx[key] and "ON" or "OFF"), function()
                    run("set " .. key .. " " .. ((CT.fx and CT.fx[key]) and "off" or "on"))
                    if CT.menuLabel then CT.menuLabel(btn, label .. ": " .. ((CT.fx and CT.fx[key]) and "ON" or "OFF")) end
                end)
                add(page, btn)
            end
            add(page, nil)
            toggle("Ice floor", "ice")
            toggle("Pushing", "push")
            toggle("Chaos mode", "chaos")
            add(page, newButton(menu, "Fling everyone", function() run("fling") end), 12)
            add(page, newButton(menu, "Random outfits for everyone", function() run("outfit randomall") end))
            add(page, newButton(menu, "Reset all fun settings", function()
                run("resetfun")
                ExecuteWithDelay(200, function() ExecuteInGameThread(function() if current and valid(current.menu) and valid(current.page) then fill(current.menu, current.page) end end) end)
            end))

            add(page, newHeader(menu, "Race"), 20)
            add(page, newButton(menu, "Join Red", function() run("team red") end))
            add(page, newButton(menu, "Join Blue", function() run("team blue") end))
            add(page, newButton(menu, "Balance teams", function() run("balance") end))
            add(page, newButton(menu, "Start clock", function() run("start") end))
            add(page, newButton(menu, "Reset clock", function() run("reset") end))
            add(page, newButton(menu, "Rematch (back to lobby)", function() run("rematch") end))
        else
            add(page, newHeader(menu, "Team"), 20)
            add(page, newButton(menu, "Join Red", function() run("team red") end))
            add(page, newButton(menu, "Join Blue", function() run("team blue") end))
            add(page, newButton(menu, "Spectate other team", function() run("spectate") end))
            add(page, newButton(menu, "Back to my view", function() run("me") end))
        end
    end

    local function showPage(menu)
        local b = built[fname(menu)]; if not b then return end
        current = b
        fill(menu, b.page)
        local okA, eA = pcall(function() menu.SettingSwitcher:SetActiveWidget(b.page) end)
        local n = -1; pcall(function() n = b.page:GetChildrenCount() end)
        local idx = -1; pcall(function() idx = menu.SettingSwitcher:GetActiveWidgetIndex() end)
        log("menu: showPage set=" .. tostring(okA) .. " " .. tostring(eA) .. " children=" .. n .. " activeIndex=" .. idx)
        -- tab highlight: deselect the game's tabs, select ours
        for _, t in ipairs({ "TeleportationTab", "VideoTab", "SoundTab", "ControlsTab", "BindsTab", "LanguageTab" }) do
            pcall(function() menu[t]:SetSelected(false) end)
        end
        pcall(function() menu.DevTab:SetSelected(true) end)
    end

    -- turn the hidden DEV tab into "Mods" and add our page to the switcher
    local function buildInto(menu)
        local key = fname(menu)
        if built[key] then return end
        -- the game makes a new Esc menu each time; forget the old ones so delayed refreshes never touch them
        built = {}; current = nil; actions = {}; sliders = {}
        local tab = menu.DevTab
        if not valid(tab) then return end
        pcall(function() tab.Text = FText("Mods") end)
        pcall(function() tab.TextBlock_85:SetText(FText("Mods")) end)
        pcall(function() tab:SetVisibility(0) end)
        local page
        pcall(function() page = StaticConstructObject(StaticFindObject("/Script/UMG.VerticalBox"), menu.WidgetTree, FName("CT_ModsPage")) end)
        if not valid(page) then log("menu: could not create page"); return end
        local okc, ec = pcall(function() menu.SettingSwitcher:AddChild(page) end)
        log("menu: page added to switcher: " .. tostring(okc) .. " " .. tostring(ec))
        built[key] = { page = page, menu = menu, tab = fname(tab) }
        log("menu: Mods tab added")
    end

    -- watch for the Esc menu being opened
    LoopAsync(400, function()
        if state.enabled == false then return false end
        ExecuteInGameThread(function()
            for _, m in ipairs(FindAllOf("W_SettingsMain_C") or {}) do
                local okv, inVp = pcall(function() return m:IsInViewport() end)
                if okv and inVp then pcall(buildInto, m) end
            end
        end)
        return false
    end)

    -- clicks
    pcall(function()
        CT.hookLater("/V_WidgetEssentials/Widgets/W_Tab.W_Tab_C:BndEvt__W_Tabs_Button_0_K2Node_ComponentBoundEvent_2_OnButtonClickedEvent__DelegateSignature", function(ctx)
            local tab = ctx:get()
            local tn = fname(tab)
            log("menu: tab clicked " .. tn)
            for _, b in pairs(built) do
                if b.tab == tn then
                    ExecuteWithDelay(30, function() ExecuteInGameThread(function() showPage(b.menu) end) end)
                end
            end
        end)
    end)
    pcall(function()
        CT.hookLater("/V_WidgetEssentials/Widgets/W_Button.W_Button_C:BndEvt__W_Buttons_Button_0_K2Node_ComponentBoundEvent_2_OnButtonClickedEvent__DelegateSignature", function(ctx)
            local f = actions[fname(ctx:get())]
            if f then ExecuteWithDelay(10, function() ExecuteInGameThread(f) end) end
        end)
    end)
    pcall(function()
        CT.hookLater("/V_WidgetEssentials/Widgets/W_Slider.W_Slider_C:BndEvt__W_Slider_Slider_119_K2Node_ComponentBoundEvent_0_OnFloatValueChangedEvent__DelegateSignature", function(ctx, valueP)
            local setting = sliders[fname(ctx:get())]
            if not setting then return end
            local ok, v = pcall(function() return valueP:get() end)
            if ok and v then
                CT.menuPending = CT.menuPending or {}
                CT.menuPending[setting] = v
            end
        end)
    end)
    -- apply slider changes at most 4 times a second (dragging fires many events)
    LoopAsync(250, function()
        local p = CT.menuPending
        if p and next(p) then
            CT.menuPending = {}
            ExecuteInGameThread(function()
                for k, v in pairs(p) do run(string.format("set %s %.2f", k, v)) end
            end)
        end
        return false
    end)

    log("Esc menu Mods tab ready")
end
