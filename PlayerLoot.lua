-- PlayerLoot.lua: one player's loot history (right-click a name in Group stats).
-- Every item they won (or every roll they made), newest first, with their pick,
-- roll, place and value. Small by default (about five items), scrolls, resizable.
local _, ns = ...
local St, L, S = ns.St, ns.L, ns.S

local format, max = string.format, math.max

local PL = {}
ns.PlayerLoot = PL

local ROW_H = 38
local TOP = 82                         -- title bar + name + summary
local W = 440
local H = TOP + 5 * ROW_H + 16         -- five items at the default size
local MIN_H = TOP + 3 * ROW_H + 16     -- three at the smallest

local frame, list, nameText, summary
local filterButtons = {}
local state = { filter = "won" }       -- won | all
local current                          -- { name, c, g, runs, since, scope }

-------------------------------------------------------------------------------
--  Data
-------------------------------------------------------------------------------
local function EntryOf(rec, name)
    for _, e in ipairs(rec.rolls or {}) do
        if e.n == name then return e end
    end
end

local function Build()
    local name, since = current.name, current.since or 0
    local rows = {}
    local t = { won = 0, gold = 0, ah = 0, rolls = 0, need = 0, greed = 0, pass = 0 }
    local rolls = ns.db.rolls
    for i = #rolls, 1, -1 do
        local rec = rolls[i]
        if rec.t >= since then
            local e = EntryOf(rec, name)
            local won = rec.win == name
            if e and e.s and e.s ~= S.NONE then
                t.rolls = t.rolls + 1
                if e.s == S.NEED or e.s == S.OFF then t.need = t.need + 1
                elseif e.s == S.GREED or e.s == S.XMOG then t.greed = t.greed + 1
                elseif e.s == S.PASS then t.pass = t.pass + 1 end
            end
            if won then
                t.won = t.won + 1
                t.gold = t.gold + (rec.sell or 0)
                t.ah = t.ah + (ns.AH(rec) or 0)
            end
            if won or (state.filter == "all" and e) then
                rows[#rows + 1] = { rec = rec, e = e, won = won }
            end
        end
    end
    if #rows == 0 then
        rows[1] = { kind = "empty", h = 40,
            text = state.filter == "won" and L["No items won"] or L["Nothing matches"] }
    end
    return rows, t
end

-------------------------------------------------------------------------------
--  Rows
-------------------------------------------------------------------------------
-- Item tooltip on hover: off (default) | hover | compare (with the equipped item).
local TIP_MODES = { "off", "hover", "compare" }
local TIP_LABEL = { off = "Tooltip: off", hover = "Tooltip: hover", compare = "Tooltip: compare" }
local function TipMode() return ns.db.opts.lootTip or "off" end

local function HideCompare()
    for _, name in ipairs({ "ShoppingTooltip1", "ShoppingTooltip2" }) do
        local t = _G[name]
        if t and t:IsShown() then t:Hide() end
    end
end

local function ItemTip(owner, rec)
    local mode = TipMode()
    if mode == "off" then return end
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
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
    if mode == "compare" then
        if GameTooltip_ShowCompareItem then pcall(GameTooltip_ShowCompareItem, GameTooltip) end
    else
        HideCompare()
    end
end

local function Make(l)
    local row = CreateFrame("Button", nil, l)
    St.RowBackground(row)
    row.icon = St.Icon(row, 26)
    row.icon:SetPoint("LEFT", 6, 0)
    row.title = St.Text(row, 11)
    row.title:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 8, -1)
    row.title:SetPoint("RIGHT", row, "RIGHT", -96, 0)
    row.sub = St.Text(row, 10)
    row.sub:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -3)
    row.sub:SetPoint("RIGHT", row, "RIGHT", -8, 0)
    row.value = St.Text(row, 11, "RIGHT")
    row.value:SetPoint("TOPRIGHT", -8, -5)
    row.value:SetWidth(90)
    row.empty = St.Text(row, 11, "CENTER")
    row.empty:SetPoint("CENTER")
    row.empty:SetTextColor(1, 1, 1, 0.45)
    row.sep = St.Fill(row, { 1, 1, 1, 0.07 }, "BORDER")
    row.sep:SetPoint("BOTTOMLEFT", 6, 1); row.sep:SetPoint("BOTTOMRIGHT", -6, 1); row.sep:SetHeight(1)
    row:SetScript("OnClick", function(self)
        local item = self.item
        if item and item.rec and IsModifiedClick("CHATLINK") then HandleModifiedItemClick(item.rec.link) end
    end)
    row:SetScript("OnEnter", function(self)
        self:PaintState(false)
        if self.item and self.item.rec then ItemTip(self, self.item.rec) end
        -- "hover" mode: the game may add the comparison later (Shift, always-compare):
        -- keep it off, but only while the mouse is on this row.
        if TipMode() == "hover" then self:SetScript("OnUpdate", HideCompare) end
    end)
    row:SetScript("OnLeave", function(self)
        self:SetScript("OnUpdate", nil)
        self:PaintState(false)
        GameTooltip:Hide()
        HideCompare()
    end)
    return row
end

local function Fill(row, item)
    local empty = item.kind == "empty"
    row.icon:SetShown(not empty)
    row.title:SetShown(not empty)
    row.sub:SetShown(not empty)
    row.value:SetShown(not empty)
    row.sep:SetShown(not empty)
    row.empty:SetShown(empty)
    row:EnableMouse(not empty)
    row:PaintState(false)
    if empty then
        row.empty:SetText(item.text)
        return
    end
    local rec, e = item.rec, item.e
    row.icon:SetItem(rec.icon, rec.q)
    row.title:SetText(rec.n or "?")
    row.title:SetTextColor(ns.QualityColor(rec.q))

    -- Their pick and roll, then who got it, then where and when.
    local line = ""
    if e and e.s and e.s ~= S.NONE then
        line = St.StateMarkup(e.s, 11) .. " " .. ns.StateInfo(e.s).label .. (e.r and (" " .. e.r) or "")
    elseif not e then
        line = "|cff9a9a9a-|r"
    end
    if not item.won then
        if rec.win then
            line = line .. "  |cff9a9a9a(" .. L["went to"] .. " " .. rec.win .. ")|r"
        elseif rec.ap then
            line = line .. "  |cff9a9a9a(" .. L["Everyone passed"] .. ")|r"
        end
    end
    local v = ns.visitById[rec.v]
    local where = v and (v.place .. ", " .. ns.DayLabel(v.t) .. " " .. ns.Clock(v.t)) or ns.DayLabel(rec.t)
    row.sub:SetText(line .. "  |cff777777·  " .. where .. "|r")

    if item.won then
        local ah = ns.AH(rec)
        row.value:SetText(ns.Money(ah or rec.sell or 0))
        row.value:SetTextColor(St.Accent())
        local r, g, b = St.Accent()
        row.hl:SetColorTexture(r, g, b, 0.05)
    else
        row.value:SetText("")
    end
end

-------------------------------------------------------------------------------
--  Window
-------------------------------------------------------------------------------
function PL:Refresh(keepOffset)
    if not (frame and frame:IsShown() and current) then return end
    for key, b in pairs(filterButtons) do b:SetActive(state.filter == key) end
    nameText:SetText(ns.ClassName(current.name, current.c)
        .. (current.g and ("  |cff99e699<" .. current.g .. ">|r") or "")
        .. (current.scope and ("  |cff9a9a9a(" .. current.scope .. ")|r") or ""))
    local rows, t = Build()
    list:SetData(rows, keepOffset)
    local parts = {}
    if current.runs then parts[#parts + 1] = current.runs == 1 and L["1 run"] or format(L["%d runs"], current.runs) end
    parts[#parts + 1] = format(L["won %d"], t.won)
    if t.gold > 0 then parts[#parts + 1] = ns.Money(t.gold) end
    if t.ah > 0 then parts[#parts + 1] = "AH " .. ns.Money(t.ah) end
    if t.rolls > 0 then
        parts[#parts + 1] = format("%s %d / %d / %d", St.StateMarkup(S.NEED, 10), t.need, t.greed, t.pass)
    end
    summary:SetText(table.concat(parts, "  ·  "))
end

local function Init()
    frame = St.Window("NibbelzLootPlayerLootFrame", W, H, L["Loot history"], "playerloot")
    frame:Place({ "CENTER", UIParent, "CENTER", 300, 0 })
    St.Resizable(frame, 360, MIN_H, 900, 1000, function() PL:Refresh(true) end)
    frame:SetScale(ns.db.opts.scale or 1)
    frame:SetFrameStrata("DIALOG")
    frame:Hide()
    tinsert(UISpecialFrames, "NibbelzLootPlayerLootFrame")

    filterButtons.won = St.Button(frame, L["Won"], 70, 20, function()
        state.filter = "won"
        PL:Refresh()
    end)
    filterButtons.won:SetPoint("TOPRIGHT", -80, -36)
    filterButtons.all = St.Button(frame, L["All rolls"], 70, 20, function()
        state.filter = "all"
        PL:Refresh()
    end)
    filterButtons.all:SetPoint("LEFT", filterButtons.won, "RIGHT", 2, 0)

    nameText = St.Text(frame, 13)
    nameText:SetPoint("TOPLEFT", 12, -38)
    nameText:SetPoint("RIGHT", filterButtons.won, "LEFT", -8, 0)
    nameText:SetHeight(16)
    local tipButton
    tipButton = St.Button(frame, L[TIP_LABEL[TipMode()]], 120, 18, function()
        local cur, nextMode = TipMode(), "off"
        for i, m in ipairs(TIP_MODES) do
            if m == cur then nextMode = TIP_MODES[i % #TIP_MODES + 1] end
        end
        ns.db.opts.lootTip = nextMode
        tipButton.text:SetText(L[TIP_LABEL[nextMode]])
        tipButton:SetActive(nextMode ~= "off")
    end)
    tipButton:SetActive(TipMode() ~= "off")
    tipButton:SetPoint("TOPRIGHT", -8, -58)
    tipButton:SetScript("OnEnter", function(self)
        if self.Paint then self:Paint() end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(L["Item tooltip on hover"])
        GameTooltip:AddLine(L["Click to switch: off, hover, hover and compare with your equipped item."], 1, 1, 1, true)
        GameTooltip:Show()
    end)
    tipButton:SetScript("OnLeave", function(self)
        if self.Paint then self:Paint() end
        GameTooltip:Hide()
    end)

    summary = St.Text(frame, 10)
    summary:SetPoint("TOPLEFT", 12, -62)
    summary:SetPoint("RIGHT", tipButton, "LEFT", -6, 0)
    summary:SetTextColor(1, 1, 1, St.DIM + 0.15)

    local inset = CreateFrame("Frame", nil, frame)
    inset:SetPoint("TOPLEFT", 8, -TOP)
    inset:SetPoint("BOTTOMRIGHT", -8, 8)
    local bg = St.Fill(inset, St.INSET)
    bg:SetAllPoints()
    St.Border(inset, 0.06)

    list = St.List(inset, ROW_H, Make, Fill)
    list:SetPoint("TOPLEFT", 4, -4)
    list:SetPoint("BOTTOMRIGHT", -4, 14)

    ns.Listen(function()
        if frame:IsShown() then ns.Debounce("playerLoot", 1, function() PL:Refresh(true) end) end
    end)
end

-- p: a Group stats row (name, c, g, runs); since / scope: the time range shown there.
function PL:Open(p, since, scope)
    if not (p and p.name) then return end
    if not frame then Init() end
    current = { name = p.name, c = p.c, g = p.g, runs = p.runs, since = since, scope = scope }
    frame:Show()
    frame:Raise()
    PL:Refresh()
end

function PL:ApplyScale()
    if frame then frame:SetScale(ns.db.opts.scale or 1) end
end
