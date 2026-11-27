-- StyleChoice.lua: on the very first start after installing, a window asks which
-- look you want: the Nibbelz style or the Classic style (the WoW Forever UI).
-- Core.lua sets opts.chooseStyle on a fresh install; the choice clears it.
-- The style can be changed later in Options > Others.
local _, ns = ...
local St, L = ns.St, ns.L

local SC = {}
ns.StyleChoice = SC

local frame

local function Choose(key)
    local o = ns.db.opts
    o.chooseStyle = nil
    frame:Hide()
    if o.theme ~= key then
        o.theme = key
        St.ReloadPrompt(L["The new window style is used after a UI reload. Reload now?"])
    end
end

-- A small mock window in that style, so you see the difference.
local function Preview(card, classic)
    local p = CreateFrame("Frame", nil, card)
    p:SetPoint("TOPLEFT", 12, -34)
    p:SetPoint("TOPRIGHT", -12, -34)
    p:SetHeight(96)
    local bg = St.Fill(p, classic and { 0.03, 0.025, 0.02, 1 } or { 0.067, 0.067, 0.067, 1 })
    bg:SetAllPoints()
    if classic then
        St.Border(p, 1, 0.72, 0.56, 0.3, 1)
    else
        St.Border(p, 0.12)
    end
    local title = St.Text(p, 12)
    title:SetPoint("TOPLEFT", 8, -7)
    local line = St.Fill(p, { 1, 1, 1, 1 }, "ARTWORK")
    line:SetPoint("TOPLEFT", 6, -24); line:SetPoint("TOPRIGHT", -6, -24); line:SetHeight(1)
    local row = St.Text(p, 11)
    row:SetPoint("TOPLEFT", 10, -34)
    row:SetText(L["Need"] .. " 87  ·  " .. L["Greed"] .. " 42")
    if classic then
        title:SetText(L["Loot Rolls"])
        title:SetTextColor(1, 0.82, 0)
        line:SetColorTexture(0.72, 0.56, 0.3, 0.8)
        -- The game's own red button.
        local ok, b = pcall(CreateFrame, "Button", nil, p, "UIPanelButtonTemplate")
        if ok and b then
            b:SetSize(110, 22)
            b:SetPoint("BOTTOM", 0, 10)
            b:SetText(L["History"])
            b:EnableMouse(false)
        end
    else
        title:SetText("NIBBELZ |cff0cd29f" .. L["Loot Rolls"] .. "|r")
        line:SetColorTexture(0.047, 0.824, 0.624, 0.9)
        local b = CreateFrame("Frame", nil, p)
        b:SetSize(110, 22)
        b:SetPoint("BOTTOM", 0, 10)
        local bbg = St.Fill(b, { 1, 1, 1, 0.06 })
        bbg:SetAllPoints()
        St.Border(b, 1, 0.047, 0.824, 0.624, 0.8)
        local t = St.Text(b, 11, "CENTER")
        t:SetPoint("CENTER")
        t:SetText(L["History"])
    end
end

local function Card(key, name, text, classic, x)
    local c = CreateFrame("Frame", nil, frame)
    c:SetSize(230, 236)
    c:SetPoint("TOPLEFT", x, -64)
    local bg = St.Fill(c, { 0, 0, 0, 0.3 })
    bg:SetAllPoints()
    St.Border(c, 0.12)
    local head = St.Text(c, 14, "CENTER")
    head:SetPoint("TOP", 0, -10)
    head:SetText(name)
    if classic then head:SetTextColor(1, 0.82, 0) else head:SetTextColor(St.Accent()) end
    Preview(c, classic)
    local desc = St.Text(c, 10)
    desc:SetPoint("TOPLEFT", 12, -140)
    desc:SetPoint("RIGHT", c, "RIGHT", -12, 0)
    desc:SetWordWrap(true)
    desc:SetText(text)
    desc:SetTextColor(1, 1, 1, 0.75)
    local pick = St.Button(c, L["Use this style"], 150, 24, function() Choose(key) end)
    pick:SetPoint("BOTTOM", 0, 12)
    return c
end

local function Build()
    frame = St.Window("NibbelzLootStyleChoiceFrame", 500, 360, L["Choose your style"], "stylechoice")
    frame:Place({ "CENTER", UIParent, "CENTER", 0, 60 })
    frame:SetFrameStrata("DIALOG")
    frame:Hide()
    local intro = St.Text(frame, 11)
    intro:SetPoint("TOPLEFT", 14, -38)
    intro:SetPoint("RIGHT", frame, "RIGHT", -14, 0)
    intro:SetWordWrap(true)
    intro:SetText(L["Welcome to Nibbelz Loot! Which look do you want? You can change it any time in Options > Others."])
    intro:SetTextColor(1, 1, 1, 0.85)
    Card("nibbelz", "Nibbelz", L["Modern and flat: dark panels, turquoise accents, switches."], false, 14)
    Card("classic", L["Classic"], L["Like the WoW Forever interface: red buttons, gold text, bronze lines."], true, 256)
    -- Closing without a choice keeps the Nibbelz style and does not ask again.
    frame:HookScript("OnHide", function() ns.db.opts.chooseStyle = nil end)
end

function SC:Show()
    if not frame then Build() end
    frame:Show()
    frame:Raise()
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function()
    if ns.db and ns.db.opts.chooseStyle then
        C_Timer.After(2, function() SC:Show() end)
    end
end)
