-- LiveFrame.lua: the loot roll window. One card per item: who picked Need, Greed,
-- Pass, who is still choosing ("waiting"), the rolls and the winner.
local _, ns = ...
local St, L, S = ns.St, ns.L, ns.S

local format, max, min, floor = string.format, math.max, math.min, math.floor

local Live = {}
ns.Live = Live

local W = 320
local HEAD = 28
local CARD_H = 42
local ROW_H = 19
local FOOT = 24
local GAP = 4
local MIN_W, MAX_W = 260, 700   -- the window can be dragged between these (bottom right corner)
local MAX_H = 900
local GROUP = 5                 -- a dungeon group
-- Visible area: three items with a full group's rolls folded out; more scrolls.
local VIEW_MAX = 3 * (CARD_H + 4 + GROUP * ROW_H + 4) + 2 * GAP
local EMPTY_H = 46

local frame, countText, emptyText, footer
local scroll, content, thumb
local cards = {}
local ticker
local AnyOpen, CardWidth
local wasOpen, closeToken = false, nil
local sizing = false

-- Card width follows the window (6px left, room for the scrollbar on the right).
function CardWidth()
    return (frame and frame:GetWidth() or W) - 18
end
local CLOSE_DELAY = 5
local dots = 0

-------------------------------------------------------------------------------
--  Rows (one per player)
-------------------------------------------------------------------------------
local function NewRow(card)
    local row = CreateFrame("Frame", nil, card)
    row:SetHeight(ROW_H)
    row.bg = St.Fill(row, { 1, 1, 1, 0 }, "BACKGROUND", 2)
    row.bg:SetAllPoints()
    row.check = row:CreateTexture(nil, "OVERLAY")
    row.check:SetSize(12, 12)
    row.check:SetPoint("LEFT", 8, 0)
    row.check:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
    row.name = St.Text(row, 11)
    row.name:SetPoint("LEFT", 24, 0)
    row.name:SetWidth(130)
    row.pill = St.Pill(row, 62, 15)
    row.pill:SetPoint("LEFT", 162, 0)
    row.roll = St.Text(row, 11, "RIGHT")
    row.roll:SetPoint("RIGHT", -10, 0)
    row.roll:SetWidth(50)
    return row
end

local function FillRow(row, e)
    local waiting = e.s == S.NONE
    local r, g, b = ns.ClassColor(e.c)
    row.name:SetText(e.n)
    row.name:SetTextColor(r, g, b, waiting and 0.55 or 1)
    row.pill:SetState(e.s)
    row.check:SetShown(e.w == true)
    if waiting then
        row.roll:SetText(string.rep(".", dots % 3 + 1))
        row.roll:SetTextColor(1, 1, 1, 0.5)
    elseif e.r then
        row.roll:SetText(e.r)
        if e.w then
            row.roll:SetTextColor(St.Accent())
        else
            row.roll:SetTextColor(1, 1, 1, 0.8)
        end
    else
        row.roll:SetText("")
    end
    if e.w then
        local ar, ag, ab = St.Accent()
        row.bg:SetColorTexture(ar, ag, ab, 0.10)
    elseif e.me then
        row.bg:SetColorTexture(1, 1, 1, 0.04)
    else
        row.bg:SetColorTexture(0, 0, 0, 0)
    end
end

-------------------------------------------------------------------------------
--  Cards (one per item)
-------------------------------------------------------------------------------
local function ItemTooltip(owner, rec)
    GameTooltip:SetOwner(owner, "ANCHOR_LEFT")
    if not pcall(GameTooltip.SetHyperlink, GameTooltip, rec.link) then
        GameTooltip:AddLine(rec.n or "?")
    end
    if rec.sell and rec.sell > 0 then
        GameTooltip:AddDoubleLine(L["Vendor value"], ns.Money(rec.sell), 1, 1, 1, 1, 1, 1)
    end
    local ah = ns.AH(rec)
    if ah then GameTooltip:AddDoubleLine(L["AH value"], ns.Money(ah), 1, 1, 1, 1, 1, 1) end
    GameTooltip:AddLine(L["Shift-click to link it."], 0.6, 0.6, 0.6)
    GameTooltip:Show()
end

local function NewCard()
    local c = CreateFrame("Button", nil, content)
    c:RegisterForClicks("LeftButtonUp")
    c.bg = St.Fill(c, { 1, 1, 1, 0.025 })
    c.bg:SetAllPoints()
    St.Border(c, 0.07)

    c.icon = St.Icon(c, 30)
    c.icon:SetPoint("TOPLEFT", 6, -6)
    c.icon:EnableMouse(true)
    c.icon:SetScript("OnEnter", function(self) if c.entry then ItemTooltip(self, c.entry.rec) end end)
    c.icon:SetScript("OnLeave", function() GameTooltip:Hide() end)
    -- A click on the card or its icon folds the player rows in or out (also while
    -- the roll is still running); Shift-click links the item.
    local function Toggle()
        local e = c.entry
        if not e then return end
        if IsModifiedClick("CHATLINK") then
            HandleModifiedItemClick(e.rec.link)
            return
        end
        e.open = not c.expanded
        Live:Render(false)
    end
    c.icon:SetScript("OnMouseUp", function(_, button)
        if button == "LeftButton" then Toggle() end
    end)

    c.name = St.Text(c, 12)
    c.name:SetPoint("TOPLEFT", c.icon, "TOPRIGHT", 8, -1)
    c.name:SetPoint("RIGHT", c, "RIGHT", -96, 0)

    c.status = St.Text(c, 10)
    c.status:SetPoint("TOPLEFT", c.name, "BOTTOMLEFT", 0, -4)
    c.status:SetPoint("RIGHT", c, "RIGHT", -26, 0)
    c.status:SetTextColor(1, 1, 1, 0.75)

    -- Fold indicator (+ / -), bottom right of the item header.
    c.exp = c:CreateTexture(nil, "OVERLAY")
    c.exp:SetSize(12, 12)
    c.exp:SetPoint("TOPRIGHT", -8, -24)
    c.exp:SetAlpha(0.7)

    c.right = St.Text(c, 11, "RIGHT")
    c.right:SetPoint("TOPRIGHT", -8, -7)
    c.rightIcon = c:CreateTexture(nil, "OVERLAY")
    c.rightIcon:SetSize(14, 14)
    c.rightIcon:SetPoint("RIGHT", c.right, "LEFT", -3, 0)

    c.timerBg = St.Fill(c, { 1, 1, 1, 0.06 }, "ARTWORK")
    c.timerBg:SetPoint("TOPLEFT", 6, -CARD_H)
    c.timerBg:SetPoint("TOPRIGHT", -6, -CARD_H)
    c.timerBg:SetHeight(2)
    c.timer = c:CreateTexture(nil, "OVERLAY")
    c.timer:SetPoint("TOPLEFT", c.timerBg, "TOPLEFT")
    c.timer:SetHeight(2)

    c.rows = {}
    c:SetScript("OnClick", Toggle)
    -- The wheel over a card scrolls the list.
    c:EnableMouseWheel(true)
    c:SetScript("OnMouseWheel", function(_, delta) Live:UpdateScroll(-delta * (CARD_H + GAP)) end)
    c:SetScript("OnEnter", function(self)
        self.bg:SetColorTexture(1, 1, 1, 0.05)
        self.exp:SetAlpha(1)
    end)
    c:SetScript("OnLeave", function(self)
        self.bg:SetColorTexture(1, 1, 1, 0.025)
        self.exp:SetAlpha(0.7)
    end)
    return c
end

local function FillCard(c, e)
    local rec = e.rec
    -- A finished roll that hasn't changed since the last draw: keep the card as it is.
    local ver = ns.version[rec] or 0
    if rec.done and c.entry == e and c.ver == ver and c.open == e.open and c.lastH then
        return c.lastH
    end
    c.ver, c.open = ver, e.open
    c.entry = e
    c.icon:SetItem(rec.icon, rec.q)
    c.name:SetText(rec.n or "?")
    c.name:SetTextColor(ns.QualityColor(rec.q))
    c.status:SetText(ns.Status(rec))

    local rolls = rec.rolls or {}
    if rec.win then
        c.right:SetText(ns.ClassName(rec.win, rec.wc) .. (rec.wr and ("  |cffffffff" .. rec.wr .. "|r") or ""))
        St.SetStateIcon(c.rightIcon, rec.ws)
    elseif rec.ap then
        c.right:SetText("|cff9a9a9a" .. L["Pass"] .. "|r")
        St.SetStateIcon(c.rightIcon, S.PASS)
    else
        local picked = 0
        for _, r in ipairs(rolls) do
            if r.s ~= S.NONE then picked = picked + 1 end
        end
        c.right:SetText(format("|cffbbbbbb%d/%d|r", picked, #rolls))
        c.rightIcon:Hide()
    end

    if rec.mw then
        c:SetBorderColor(St.Accent())
    else
        c:SetBorderColor(St.Line(0.07))
    end

    local timer = false
    if e.start and e.dur and not rec.done then
        local left = e.start + e.dur - GetTime()
        if left > 0 and left <= e.dur then
            timer = true
            local r, g, b = St.Accent()
            c.timer:SetColorTexture(r, g, b, 0.9)
            c.timer:SetWidth(max(1, (CardWidth() - 12) * left / e.dur))
        end
    end
    c.timer:SetShown(timer)
    c.timerBg:SetShown(timer)

    local expanded = e.open
    if expanded == nil then expanded = not rec.done end
    c.expanded = expanded
    if #rolls > 0 then
        c.exp:SetTexture(expanded and "Interface\\Buttons\\UI-MinusButton-Up" or "Interface\\Buttons\\UI-PlusButton-Up")
        c.exp:Show()
    else
        c.exp:Hide()
    end

    local y = CARD_H + (timer and 4 or 0)
    local used = 0
    if expanded then
        for i, r in ipairs(rolls) do
            local row = c.rows[i]
            if not row then
                row = NewRow(c)
                c.rows[i] = row
            end
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", 1, -y)
            row:SetPoint("TOPRIGHT", -1, -y)
            FillRow(row, r)
            row:Show()
            y = y + ROW_H
            used = i
        end
        if used > 0 then y = y + 4 end
    end
    for i = used + 1, #c.rows do c.rows[i]:Hide() end
    c.lastH = y
    return y
end

-------------------------------------------------------------------------------
--  Window
-------------------------------------------------------------------------------
function AnyOpen()
    for i = 1, #ns.live do
        if not ns.live[i].rec.done then return true end
    end
    return false
end

local function UpdateFooter()
    local v = ns.CurrentVisit()
    local place = v and v.place or ns.ctx.place
    local won, gold, ah = 0, 0, 0
    if v then
        -- Newest first; stop at the run's start instead of reading the whole history.
        local rolls = ns.db.rolls
        for i = #rolls, 1, -1 do
            local rec = rolls[i]
            if rec.t < v.t then break end
            if rec.v == v.id and rec.mw then
                won = won + 1
                gold = gold + (rec.sell or 0)
                ah = ah + (ns.AH(rec) or 0)
            end
        end
    end
    footer.text:SetText(format("|cff9a9a9a%s:|r %s", L["This run"], place or "?"))
    local text = format("|cffbbbbbb%s|r  %s", format(L["won %d"], won), ns.Money(gold))
    if ah > 0 then text = text .. "  |cff9a9a9aAH|r " .. ns.Money(ah) end
    footer.gold:SetText(text)
end

function Live:Render(full)
    if not frame or not frame:IsShown() then return end
    -- Newest item on top. The list only holds this dungeon's / group's rolls;
    -- it is emptied when you leave the dungeon or the group (Core.lua).
    local list = {}
    for i = #ns.live, 1, -1 do list[#list + 1] = ns.live[i] end

    if #list == 0 then
        countText:SetText("")
    else
        countText:SetText("|cffbbbbbb" .. (#list == 1 and L["1 item"] or format(L["%d items"], #list)) .. "|r")
    end

    local y, firstThree = 0, 0
    for i, e in ipairs(list) do
        local c = cards[i]
        if not c then
            c = NewCard()
            cards[i] = c
        end
        local h = FillCard(c, e)
        c:ClearAllPoints()
        c:SetPoint("TOPLEFT", 6, -y)
        c:SetSize(CardWidth(), h)
        c:Show()
        y = y + h + GAP
        if i == 3 then firstThree = y - GAP end
    end
    for i = #list + 1, #cards do cards[i]:Hide() end
    if #list > 0 then y = y - GAP end
    if #list <= 3 then firstThree = y end

    emptyText:SetShown(#list == 0)
    content:SetSize(frame:GetWidth(), max(1, y))
    local view
    if sizing then
        -- Being dragged: the window's height decides, cards scroll inside.
        view = max(EMPTY_H, frame:GetHeight() - HEAD - 12 - FOOT)
    elseif ns.db.opts.liveH then
        -- A size the player chose: keep it.
        view = max(EMPTY_H, ns.db.opts.liveH)
        frame:SetHeight(HEAD + 6 + view + 6 + FOOT)
    else
        -- Automatic: at most three items visible, folded in or out; the rest scrolls.
        view = #list == 0 and EMPTY_H or min(firstThree, VIEW_MAX)
        frame:SetHeight(HEAD + 6 + view + 6 + FOOT)
    end
    scroll:SetHeight(view)
    Live:UpdateScroll()

    if full ~= false then UpdateFooter() end
    -- The timer bars and "..." only move while a roll is open.
    local open = AnyOpen()
    if open then Live:StartTicker() else Live:StopTicker() end
    -- The last roll just finished: close a few seconds later (results stay readable).
    local stay = ns.db.opts.liveStay or CLOSE_DELAY
    if wasOpen and not open and stay < ns.STAY_OPEN then
        local token = {}
        closeToken = token
        C_Timer.After(max(1, stay), function()
            if closeToken == token and frame:IsShown() and not AnyOpen() then frame:Hide() end
        end)
    elseif open then
        closeToken = nil   -- a new roll came in: stay open
    end
    wasOpen = open
end

-- Keeps the scroll position in range and draws the thin scrollbar.
function Live:UpdateScroll(delta)
    local range = max(0, content:GetHeight() - scroll:GetHeight())
    local pos = min(range, max(0, scroll:GetVerticalScroll() + (delta or 0)))
    scroll:SetVerticalScroll(pos)
    if range <= 0 then
        thumb:Hide()
        return
    end
    local viewH = scroll:GetHeight()
    local th = max(20, viewH * viewH / content:GetHeight())
    thumb:SetHeight(th)
    thumb:ClearAllPoints()
    thumb:SetPoint("TOPRIGHT", scroll, "TOPRIGHT", -2, -(viewH - th) * pos / range)
    local r, g, b = St.Accent()
    thumb:SetColorTexture(r, g, b, 0.7)
    thumb:Show()
end

-- Runs only while the window is shown and a roll is still open.
function Live:StartTicker()
    if ticker or not (frame and frame:IsShown()) then return end
    ticker = C_Timer.NewTicker(0.5, function()
        dots = dots + 1
        Live:Render(false)
    end)
end

function Live:StopTicker()
    if ticker then ticker:Cancel() end
    ticker = nil
end

function Live:Init()
    frame = St.Window("NibbelzLootLiveFrame", ns.db.opts.liveW or W, 120, L["Loot Rolls"], "live")
    frame:Place({ "RIGHT", UIParent, "RIGHT", -260, 80 })
    frame:SetScale(ns.db.opts.scale or 1)
    frame:Hide()

    local hist = St.Button(frame.bar, L["History"], 64, 18, function() ns.History:Toggle() end)
    hist:SetPoint("RIGHT", frame.close, "LEFT", -6, 0)
    local gear = St.IconButton(frame.bar, "Interface\\Buttons\\UI-OptionsButton", 14, L["Options"],
        function() ns.Options:Toggle() end)
    gear:SetPoint("RIGHT", hist, "LEFT", -6, 0)
    countText = St.Text(frame.bar, 11, "RIGHT")
    countText:SetPoint("RIGHT", gear, "LEFT", -8, 0)

    -- Scrolling area for the item cards.
    scroll = CreateFrame("ScrollFrame", nil, frame)
    scroll:SetPoint("TOPLEFT", 0, -(HEAD + 6))
    scroll:SetPoint("TOPRIGHT", 0, -(HEAD + 6))
    scroll:SetHeight(EMPTY_H)
    if scroll.SetClipsChildren then scroll:SetClipsChildren(true) end
    content = CreateFrame("Frame", nil, scroll)
    content:SetSize(W, 1)
    scroll:SetScrollChild(content)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(_, delta) Live:UpdateScroll(-delta * (CARD_H + GAP)) end)
    thumb = scroll:CreateTexture(nil, "OVERLAY")
    thumb:SetWidth(3)
    thumb:Hide()

    emptyText = St.Text(scroll, 11, "CENTER")
    emptyText:SetPoint("CENTER", 0, 0)
    emptyText:SetText(L["No active rolls"])
    emptyText:SetTextColor(1, 1, 1, 0.45)

    footer = CreateFrame("Frame", nil, frame)
    footer:SetPoint("BOTTOMLEFT"); footer:SetPoint("BOTTOMRIGHT"); footer:SetHeight(FOOT)
    local line = St.Fill(footer, { 1, 1, 1, 0.06 }, "BORDER")
    line:SetPoint("TOPLEFT", 1, 0); line:SetPoint("TOPRIGHT", -1, 0); line:SetHeight(1)
    footer.gold = St.Text(footer, 10, "RIGHT")
    footer.gold:SetPoint("RIGHT", -22, 0)   -- room for the resize grip
    footer.text = St.Text(footer, 10)
    footer.text:SetPoint("LEFT", 10, 0)
    footer.text:SetPoint("RIGHT", footer.gold, "LEFT", -8, 0)

    -- Resize grip in the bottom right corner. Double-click: back to the automatic size.
    frame:SetResizable(true)
    if frame.SetResizeBounds then
        frame:SetResizeBounds(MIN_W, HEAD + 12 + FOOT + EMPTY_H, MAX_W, MAX_H)
    elseif frame.SetMinResize then
        frame:SetMinResize(MIN_W, HEAD + 12 + FOOT + EMPTY_H)
        frame:SetMaxResize(MAX_W, MAX_H)
    end
    local grip = CreateFrame("Button", nil, frame)
    grip:SetSize(16, 16)
    grip:SetPoint("BOTTOMRIGHT", -2, 2)
    grip:SetFrameLevel(footer:GetFrameLevel() + 5)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:SetScript("OnMouseDown", function(_, button)
        if button ~= "LeftButton" then return end
        sizing = true
        frame:StartSizing("BOTTOMRIGHT")
    end)
    grip:SetScript("OnMouseUp", function()
        if not sizing then return end
        frame:StopMovingOrSizing()
        sizing = false
        ns.db.opts.liveW = floor(frame:GetWidth() + 0.5)
        ns.db.opts.liveH = floor(frame:GetHeight() - HEAD - 12 - FOOT + 0.5)
        local point, _, relPoint, x, y = frame:GetPoint()
        ns.db.pos.live = { point, relPoint, x, y }
        Live:Render()
    end)
    grip:SetScript("OnDoubleClick", function()
        ns.db.opts.liveW, ns.db.opts.liveH = nil, nil
        frame:SetWidth(W)
        Live:Render()
    end)
    grip:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(L["Drag to resize"], 1, 1, 1)
        GameTooltip:AddLine(L["Double-click: automatic size"], 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    grip:SetScript("OnLeave", function() GameTooltip:Hide() end)
    -- While dragging, the cards follow the new size.
    frame:SetScript("OnSizeChanged", function()
        if sizing then Live:Render(false) end
    end)

    frame:SetScript("OnShow", function()
        Live:Render()
    end)
    frame:SetScript("OnHide", function() Live:StopTicker() end)
    ns.Listen(function() Live:Render() end)
end

function Live:Open()
    if frame and not frame:IsShown() then frame:Show() end
end

function Live:Toggle()
    if not frame then return end
    frame:SetShown(not frame:IsShown())
end

function Live:ApplyScale()
    if frame then frame:SetScale(ns.db.opts.scale or 1) end
end
