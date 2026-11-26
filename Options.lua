-- Options.lua: the options window. Everything the /rolls commands do, as switches,
-- sliders and buttons. Also listed under the game's Options > AddOns.
local _, ns = ...
local St, L = ns.St, ns.L

local format, floor = string.format, math.floor

local Options = {}
ns.Options = Options

local W = 380
local PAD = 16
local COL_W = (W - PAD * 2 - 8) / 2

local frame
local controls = {}

local function Apply()
    local o = ns.db.opts
    controls.liveStay:SetValue(o.liveStay or 5)
    controls.sound100:SetChecked(o.sound100)
    controls.hideRollChat:SetChecked(o.hideRollChat)
    controls.scale:SetValue(math.floor((o.scale or 1) * 100 + 0.5))
    controls.minimap:SetChecked(not o.minimapHide)
    controls.style:Update()
    controls.ahSource:Update()
    controls.battleOffer:SetChecked(o.battleOffer)
    controls.battleAnnounce:SetChecked(o.battleAnnounce)
end

local function Build()
    frame = St.Window("NibbelzLootOptionsFrame", W, 400, L["Options"], "options")
    frame:Place({ "CENTER", UIParent, "CENTER", 0, 60 })
    frame:SetFrameStrata("DIALOG")
    frame:Hide()
    tinsert(UISpecialFrames, "NibbelzLootOptionsFrame")

    local logo = frame.bar:CreateTexture(nil, "OVERLAY")
    logo:SetSize(16, 16)
    logo:SetPoint("LEFT", 10, 0)
    logo:SetTexture("Interface\\Icons\\INV_Misc_Coin_01")
    logo:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    frame.title:ClearAllPoints()
    frame.title:SetPoint("LEFT", logo, "RIGHT", 6, 0)
    frame.title:SetText("|cffffd100Nibbelz|r Loot  |cff9a9a9a" .. L["Options"] .. "|r")

    local y = 40
    -- Rows of buttons share the width and grow with the window (see Layout).
    local rows = {}
    local function Section(text)
        local fs = St.Section(frame, text)
        fs:SetPoint("TOPLEFT", PAD, -y)
        local line = St.Fill(frame, { 1, 1, 1, 0.06 }, "BORDER")
        line:SetPoint("LEFT", fs, "RIGHT", 8, 0)
        line:SetPoint("RIGHT", frame, "RIGHT", -PAD, 0)
        line:SetHeight(1)
        y = y + 20
    end
    local function Full(widget, h)
        widget:SetPoint("TOPLEFT", PAD, -y)
        widget:SetPoint("TOPRIGHT", -PAD, -y)
        y = y + h
    end
    -- Widgets side by side; slots = the row's column count (a lone button in a
    -- two-column row stays half wide).
    local function Row(widgets, slots)
        for i, w in ipairs(widgets) do
            if i == 1 then
                w:SetPoint("TOPLEFT", PAD, -y)
            else
                w:SetPoint("LEFT", widgets[i - 1], "RIGHT", 8, 0)
            end
        end
        rows[#rows + 1] = { widgets = widgets, slots = slots or #widgets }
        y = y + 28
    end
    local function Note(text, h)
        local fs = St.Text(frame, 10)
        fs:SetPoint("TOPLEFT", PAD, -y)
        fs:SetPoint("RIGHT", frame, "RIGHT", -PAD, 0)
        fs:SetWordWrap(true)
        fs:SetText(text)
        fs:SetTextColor(1, 1, 1, 0.5)
        y = y + h
    end

    -- Loot roll window
    Section(L["LOOT ROLL WINDOW"])
    controls.scale = St.Slider(frame, L["Window size"], 60, 150, 5,
        function(v) return v .. "%" end,
        function(v)
            ns.db.opts.scale = v / 100
            ns.Live:ApplyScale()
            ns.History:ApplyScale()
            ns.GroupStats:ApplyScale()
            ns.Battle:ApplyScale()
            ns.Share:ApplyScale()
        end)
    Full(controls.scale, 44)
    -- 0 = never opens by itself, 1-60 s after the last roll, STAY_OPEN = stays open.
    controls.liveStay = St.Slider(frame, L["Window stays open after the last roll"], 0, ns.STAY_OPEN, 1,
        function(v)
            if v <= 0 then return L["Never opens"] end
            if v >= ns.STAY_OPEN then return L["Stays open"] end
            return format(L["%d sec"], v)
        end,
        function(v) ns.db.opts.liveStay = v end)
    Full(controls.liveStay, 44)
    controls.minimap = St.Checkbox(frame, L["Show minimap button"], function(on)
        ns.Minimap:SetShown(on)
    end)
    Full(controls.minimap, 26)
    controls.sound100 = St.Checkbox(frame, L["Play a sound when someone rolls a 100"], function(on)
        ns.db.opts.sound100 = on
    end)
    Full(controls.sound100, 26)
    controls.hideRollChat = St.Checkbox(frame, L["Hide the roll messages in chat"], function(on)
        ns.db.opts.hideRollChat = on
    end)
    Full(controls.hideRollChat, 26)
    Note(L["The window empties after each dungeon and when you leave the group. All rolls stay in the roll history."], 34)
    Row({ St.Button(frame, L["Show loot roll window"], COL_W, 22, function() ns.Live:Toggle() end),
        St.Button(frame, L["Preview with test rolls"], COL_W, 22, function() ns.TestRolls() end) })
    Row({ St.Button(frame, L["Remove test rolls"], COL_W, 22, function() ns.ClearTest() end) }, 2)
    y = y + 8

    -- History
    Section(L["ROLL HISTORY"])
    local reset = St.Button(frame, L["Delete roll history"], COL_W, 22, function()
        StaticPopup_Show("NIBBELZLOOT_RESET")
    end)
    reset.danger = true
    reset:Paint()
    Row({ St.Button(frame, L["Add demo history"], COL_W, 22, function() ns.AddDemo() end),
        St.Button(frame, L["Remove demo history"], COL_W, 22, function() ns.ClearDemo() end) })
    Row({ reset, St.Button(frame, L["Gold per dungeon in chat"], COL_W, 22, function() ns.PrintGold() end) })
    y = y + 8

    -- Loot battle
    Section(L["LOOT BATTLE"])
    controls.battleOffer = St.Checkbox(frame, L["Remind me of the battle when entering a dungeon"], function(on)
        ns.db.opts.battleOffer = on
    end)
    Full(controls.battleOffer, 26)
    controls.battleAnnounce = St.Checkbox(frame, L["Post the result in group chat (my battles)"], function(on)
        ns.db.opts.battleAnnounce = on
    end)
    Full(controls.battleAnnounce, 26)
    Row({ St.Button(frame, L["Loot battle"], COL_W, 22, function() ns.Battle:Command() end) }, 2)

    -- The other windows, one click away.
    local THIRD = (W - PAD * 2 - 16) / 3
    Row({ St.Button(frame, L["Fair share"], THIRD, 22, function() ns.Share:Toggle() end),
        St.Button(frame, L["Roll history"], THIRD, 22, function() ns.History:Toggle() end),
        St.Button(frame, L["Group stats"], THIRD, 22, function() ns.GroupStats:Toggle() end) })
    y = y + 4

    -- Where the AH value comes from: automatic = the first addon that knows a price.
    local function SourceLabel(key)
        for _, src in ipairs(ns.AH_SOURCES) do
            if src.key == key then return src.label end
        end
        return L["Automatic"]
    end
    controls.ahSource = St.Dropdown(frame, W - PAD * 2, 22, function()
        return L["AH prices: "] .. SourceLabel(ns.db.opts.ahSource or "auto")
    end, function()
        local cur = ns.db.opts.ahSource or "auto"
        local function Pick(key)
            return function()
                ns.db.opts.ahSource = key
                ns.ResetAHMisses()
                controls.ahSource:Update()
                ns.Notify()
            end
        end
        local items = { { L["Automatic"], Pick("auto"), nil, cur == "auto" } }
        for _, src in ipairs(ns.AH_SOURCES) do
            local text = src.label
            if not src.available() then text = "|cff777777" .. text .. " (" .. L["not installed"] .. ")|r" end
            items[#items + 1] = { text, Pick(src.key), nil, cur == src.key }
        end
        return items
    end)
    Full(controls.ahSource, 26)
    Note(L["AH prices are taken when an item drops. Older items without a price look it up once."], 34)

    -- Design: the window style; a new style needs a UI reload.
    Section(L["DESIGN"])
    local function StyleLabel(key)
        for _, t in ipairs(St.THEMES) do
            if t.key == key then return L[t.label] end
        end
        return L[St.THEMES[1].label]
    end
    controls.style = St.Dropdown(frame, COL_W, 22, function()
        return L["Style: "] .. StyleLabel(ns.db.opts.theme)
    end, function()
        local items = {}
        for _, t in ipairs(St.THEMES) do
            local key = t.key
            items[#items + 1] = { L[t.label], function()
                if ns.db.opts.theme == key then return end
                ns.db.opts.theme = key
                controls.style:Update()
                St.ReloadPrompt(L["The new window style is used after a UI reload. Reload now?"])
            end, nil, key == ns.db.opts.theme }
        end
        return items
    end)
    Row({ controls.style }, 2)
    y = y + 6

    local hint = St.Text(frame, 10)
    hint:SetPoint("TOPLEFT", PAD, -y)
    hint:SetPoint("RIGHT", frame, "RIGHT", -PAD, 0)
    hint:SetWordWrap(true)
    hint:SetText("/nl   ·   /rolls   ·   /rollhistory   ·   /lootbattle   ·   /fairshare   ·   /rolls options")
    hint:SetTextColor(1, 1, 1, 0.35)
    y = y + 24

    -- Button rows follow the window width.
    local function Layout()
        local inner = frame:GetWidth() - PAD * 2
        for _, r in ipairs(rows) do
            local w = (inner - 8 * (r.slots - 1)) / r.slots
            for _, b in ipairs(r.widgets) do b:SetWidth(w) end
        end
    end
    frame:SetHeight(y)
    frame.defaultH = y
    -- Wider or narrower only: the content has a fixed height.
    St.Resizable(frame, W, y, 760, y, Layout)
    frame:HookScript("OnSizeChanged", Layout)
    Layout()
    frame:SetScript("OnShow", Apply)
end

-- An entry under Options > AddOns that opens the window.
local function RegisterBlizzard()
    if not (Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory) then return end
    local panel = CreateFrame("Frame")
    panel.name = "Nibbelz Loot"
    local title = St.Text(panel, 16)
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("|cffffd100Nibbelz|r Loot")
    local note = St.Text(panel, 11)
    note:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    note:SetText(L["Settings are in their own window."])
    note:SetTextColor(1, 1, 1, 0.7)
    local open = St.Button(panel, L["Open options"], 180, 24, function()
        if SettingsPanel and SettingsPanel:IsShown() then pcall(HideUIPanel, SettingsPanel) end
        Options:Open()
    end)
    open:SetPoint("TOPLEFT", note, "BOTTOMLEFT", 0, -14)
    local category = Settings.RegisterCanvasLayoutCategory(panel, "Nibbelz Loot")
    Settings.RegisterAddOnCategory(category)
end

function Options:Init()
    Build()
    pcall(RegisterBlizzard)
end

function Options:Open()
    if not frame then return end
    frame:Show()
    frame:Raise()
end

function Options:Toggle()
    if not frame then return end
    if frame:IsShown() then frame:Hide() else self:Open() end
end

-- Keep the window in step when a /rolls command changes a setting.
function Options:Sync()
    if frame and frame:IsShown() then Apply() end
end
