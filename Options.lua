-- Options.lua: the options window. Everything the /rolls commands do, as switches,
-- sliders and buttons. Also listed under the game's Options > AddOns.
-- The content scrolls (mouse wheel); the window can be resized at the corner.
local _, ns = ...
local St, L = ns.St, ns.L

local format, max, min = string.format, math.max, math.min

local Options = {}
ns.Options = Options

local W = 380
local PAD = 16
local COL_W = (W - PAD * 2 - 8) / 2
local BAR = 30          -- title bar
local BOTTOM = 18       -- room for the resize grip
local DEFAULT_H = 560   -- default window height (the rest scrolls)

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
    frame = St.Window("NibbelzLootOptionsFrame", W, DEFAULT_H, L["Options"], "options")
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

    -- Everything below the title bar scrolls; a thin bar on the right shows where.
    local scroll = CreateFrame("ScrollFrame", nil, frame)
    scroll:SetPoint("TOPLEFT", 0, -BAR)
    scroll:SetPoint("BOTTOMRIGHT", 0, BOTTOM)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(W, 10)
    scroll:SetScrollChild(content)
    local track = St.Fill(frame, { 1, 1, 1, 0.04 }, "ARTWORK")
    track:SetPoint("TOPRIGHT", -4, -BAR - 4)
    track:SetPoint("BOTTOMRIGHT", -4, BOTTOM + 4)
    track:SetWidth(3)
    local thumb = frame:CreateTexture(nil, "OVERLAY")
    thumb:SetWidth(3)
    local function UpdateThumb()
        local range = scroll:GetVerticalScrollRange()
        if range <= 0.5 then
            track:Hide(); thumb:Hide()
            return
        end
        local h, view = track:GetHeight(), scroll:GetHeight()
        local th = max(20, h * view / (view + range))
        local r, g, b = St.Accent()
        thumb:SetColorTexture(r, g, b, 0.7)
        thumb:SetHeight(th)
        thumb:ClearAllPoints()
        thumb:SetPoint("TOPRIGHT", track, "TOPRIGHT", 0, -(h - th) * scroll:GetVerticalScroll() / range)
        track:Show(); thumb:Show()
    end
    local function ScrollTo(v)
        scroll:SetVerticalScroll(max(0, min(scroll:GetVerticalScrollRange(), v)))
        UpdateThumb()
    end
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta) ScrollTo(self:GetVerticalScroll() - delta * 40) end)
    scroll:SetScript("OnScrollRangeChanged", function(self) ScrollTo(self:GetVerticalScroll()) end)

    local y = 12
    -- Rows of buttons share the width and grow with the window (see Layout).
    local rows = {}
    local function Section(text)
        local fs = St.Section(content, text)
        fs:SetPoint("TOPLEFT", PAD, -y)
        local line = St.Fill(content, { 1, 1, 1, 0.06 }, "BORDER")
        line:SetPoint("LEFT", fs, "RIGHT", 8, 0)
        line:SetPoint("RIGHT", content, "RIGHT", -PAD, 0)
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
        local fs = St.Text(content, 10)
        fs:SetPoint("TOPLEFT", PAD, -y)
        fs:SetPoint("RIGHT", content, "RIGHT", -PAD, 0)
        fs:SetWordWrap(true)
        fs:SetText(text)
        fs:SetTextColor(1, 1, 1, 0.5)
        y = y + h
    end
    local function Btn(label, onClick) return St.Button(content, label, COL_W, 22, onClick) end

    -- Loot roll window
    Section(L["LOOT ROLL WINDOW"])
    controls.scale = St.Slider(content, L["Window size"], 60, 150, 5,
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
    controls.liveStay = St.Slider(content, L["Window stays open after the last roll"], 0, ns.STAY_OPEN, 1,
        function(v)
            if v <= 0 then return L["Never opens"] end
            if v >= ns.STAY_OPEN then return L["Stays open"] end
            return format(L["%d sec"], v)
        end,
        function(v) ns.db.opts.liveStay = v end)
    Full(controls.liveStay, 44)
    controls.minimap = St.Checkbox(content, L["Show minimap button"], function(on)
        ns.Minimap:SetShown(on)
    end)
    Full(controls.minimap, 26)
    controls.sound100 = St.Checkbox(content, L["Play a sound when someone rolls a 100"], function(on)
        ns.db.opts.sound100 = on
    end)
    Full(controls.sound100, 26)
    controls.hideRollChat = St.Checkbox(content, L["Hide the roll messages in chat"], function(on)
        ns.db.opts.hideRollChat = on
    end)
    Full(controls.hideRollChat, 26)
    Note(L["The window empties after each dungeon and when you leave the group. All rolls stay in the roll history."], 34)
    Row({ Btn(L["Show loot roll window"], function() ns.Live:Toggle() end),
        Btn(L["Preview with test rolls"], function() ns.TestRolls() end) })
    Row({ Btn(L["Remove test rolls"], function() ns.ClearTest() end) }, 2)
    y = y + 8

    -- History
    Section(L["ROLL HISTORY"])
    local reset = Btn(L["Delete roll history"], function() StaticPopup_Show("NIBBELZLOOT_RESET") end)
    reset.danger = true
    reset:Paint()
    Row({ Btn(L["Add demo history"], function() ns.AddDemo() end),
        Btn(L["Remove demo history"], function() ns.ClearDemo() end) })
    Row({ reset, Btn(L["Gold per dungeon in chat"], function() ns.PrintGold() end) })
    y = y + 8

    -- Loot battle, and the other windows one click away (a block of four).
    Section(L["LOOT BATTLE"])
    controls.battleOffer = St.Checkbox(content, L["Remind me of the battle when entering a dungeon"], function(on)
        ns.db.opts.battleOffer = on
    end)
    Full(controls.battleOffer, 26)
    controls.battleAnnounce = St.Checkbox(content, L["Post the result in group chat (my battles)"], function(on)
        ns.db.opts.battleAnnounce = on
    end)
    Full(controls.battleAnnounce, 26)
    Row({ Btn(L["Loot battle"], function() ns.Battle:Command() end),
        Btn(L["Fair share"], function() ns.Share:Toggle() end) })
    Row({ Btn(L["Roll history"], function() ns.History:Toggle() end),
        Btn(L["Group stats"], function() ns.GroupStats:Toggle() end) })
    y = y + 8

    -- Others: where the AH value comes from, and the window style (side by side).
    Section(L["OTHERS"])
    local function SourceLabel(key)
        for _, src in ipairs(ns.AH_SOURCES) do
            if src.key == key then return src.label end
        end
        return L["Automatic"]
    end
    controls.ahSource = St.Dropdown(content, COL_W, 22, function()
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
    -- A new style needs a UI reload.
    local function StyleLabel(key)
        for _, t in ipairs(St.THEMES) do
            if t.key == key then return L[t.label] end
        end
        return L[St.THEMES[1].label]
    end
    controls.style = St.Dropdown(content, COL_W, 22, function()
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
    Row({ controls.ahSource, controls.style })
    Note(L["AH prices are taken when an item drops. Older items without a price look it up once."], 34)

    local hint = St.Text(content, 10)
    hint:SetPoint("TOPLEFT", PAD, -y)
    hint:SetPoint("RIGHT", content, "RIGHT", -PAD, 0)
    hint:SetWordWrap(true)
    hint:SetText("/nl   ·   /rolls   ·   /rollhistory   ·   /lootbattle   ·   /fairshare   ·   /rolls options")
    hint:SetTextColor(1, 1, 1, 0.35)
    y = y + 30
    content:SetHeight(y)

    -- Content and button rows follow the window width.
    local function Layout()
        local width = frame:GetWidth()
        content:SetWidth(width)
        local inner = width - PAD * 2
        for _, r in ipairs(rows) do
            local w = (inner - 8 * (r.slots - 1)) / r.slots
            for _, b in ipairs(r.widgets) do b:SetWidth(w) end
        end
        ScrollTo(scroll:GetVerticalScroll())
    end
    local fullH = y + BAR + BOTTOM
    frame.defaultH = min(DEFAULT_H, fullH)
    frame:SetHeight(frame.defaultH)
    -- OnShow first: St.Resizable and the layout hook into it afterwards.
    frame:SetScript("OnShow", Apply)
    St.Resizable(frame, W, 220, 760, fullH, Layout)
    frame:HookScript("OnSizeChanged", Layout)
    frame:HookScript("OnShow", function() C_Timer.After(0, Layout) end)
    Layout()
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
