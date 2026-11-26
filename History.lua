-- History.lua: the roll history. Left: days or places, each with its visits.
-- Middle: the items of the selection (or its stats: gold won per dungeon).
-- Right: everyone's pick and roll for the selected item.
local _, ns = ...
local St, L, S = ns.St, ns.L, ns.S

local format, max, min, lower = string.format, math.max, math.min, string.lower
local sort = table.sort

local History = {}
ns.History = History

local W, H = 830, 500
local LEFT_W, MID_W = 200, 310
local TOP = 36

local frame, tree, list, detail
local tabDays, tabPlaces, tabRolls, tabStats
local filterButtons = {}
local midTitle, midSummary, search, statsChoice, statsMine

local state = {
    mode = "days",                       -- days | places
    sel = { kind = "all" },              -- all | day | visit | place
    open = {},                           -- expanded tree rows
    tab = "rolls",                       -- rolls | stats
    filter = "all",                      -- all | won
    search = "",
    selRec = nil,                        -- record id shown on the right
}

local function Inset(parent)
    local f = CreateFrame("Frame", nil, parent)
    local bg = St.Fill(f, St.INSET)
    bg:SetAllPoints()
    St.Border(f, 0.06)
    return f
end

-------------------------------------------------------------------------------
--  Data
-------------------------------------------------------------------------------
local function VisitCounts()
    local counts = {}
    for _, rec in ipairs(ns.db.rolls) do counts[rec.v] = (counts[rec.v] or 0) + 1 end
    return counts
end

local function BuildTree()
    local rows = {}
    local counts = VisitCounts()
    rows[1] = { kind = "all", key = "all", label = L["All rolls"], count = #ns.db.rolls }

    local groups, order = {}, {}
    for _, v in ipairs(ns.db.visits) do
        -- Visits with rolls, or with looted coins only.
        local n = counts[v.id] or ((v.money or 0) > 0 and 0 or nil)
        if n then
            local gkey = state.mode == "days" and ns.DayKey(v.t) or v.place
            local g = groups[gkey]
            if not g then
                g = { key = gkey, t = v.t, count = 0, visits = {} }
                groups[gkey] = g
                order[#order + 1] = g
            end
            g.count = g.count + n
            g.t = max(g.t, v.last or v.t)
            g.visits[#g.visits + 1] = v
        end
    end
    if state.mode == "days" then
        sort(order, function(a, b) return a.key > b.key end)
    else
        sort(order, function(a, b) return a.t > b.t end)
    end

    local kind = state.mode == "days" and "day" or "place"
    for _, g in ipairs(order) do
        local okey = kind .. ":" .. g.key
        local label = kind == "day" and ns.DayLabel(g.visits[1].t) or g.key
        rows[#rows + 1] = { kind = kind, key = g.key, okey = okey, label = label, count = g.count, open = state.open[okey] }
        if state.open[okey] then
            sort(g.visits, function(a, b) return a.t > b.t end)
            for _, v in ipairs(g.visits) do
                local vlabel
                if kind == "day" then
                    vlabel = ns.Clock(v.t) .. "  " .. v.place
                else
                    vlabel = ns.DayLabel(v.t) .. ", " .. ns.Clock(v.t)
                end
                rows[#rows + 1] = { kind = "visit", key = v.id, label = vlabel, count = counts[v.id] or 0, indent = true,
                    title = ns.Clock(v.t) .. "  " .. v.place }
            end
        end
    end
    return rows
end

local function InScope(rec)
    local sel = state.sel
    if sel.kind == "all" then return true end
    if sel.kind == "visit" then return rec.v == sel.key end
    local v = ns.visitById[rec.v]
    if not v then return false end
    if sel.kind == "day" then return ns.DayKey(v.t) == sel.key end
    if sel.kind == "place" then return v.place == sel.key end
    return false
end

-- The search text, trimmed and lower case ("" = no search).
local function Query()
    return lower((state.search or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

-- A record passes the filter and the search. Returns the matched player's roll entry
-- when the search found a player (so the row can show what they picked and rolled).
local function Passes(rec, q)
    if q == "" then
        if state.filter == "won" and not rec.mw then return false end
        return true
    end
    local hit
    for _, e in ipairs(rec.rolls or {}) do
        if e.n and lower(e.n):find(q, 1, true) then hit = e break end
    end
    if state.filter == "won" then
        -- "Won" while searching a player: what that player won.
        if hit then return hit.w == true, hit end
        return rec.mw and rec.n and lower(rec.n):find(q, 1, true) ~= nil or false
    end
    if hit then return true, hit end
    return rec.n and lower(rec.n):find(q, 1, true) ~= nil or false
end

-- scoped = the tree selection (for the stats), shown = the rows of the rolls tab.
-- A search looks through the whole history, whatever is selected on the left.
local function Collect()
    local scoped, shown, matches = {}, {}, {}
    local q = Query()
    local rolls = ns.db.rolls
    for i = #rolls, 1, -1 do
        local rec = rolls[i]
        local inScope = InScope(rec)
        if inScope then scoped[#scoped + 1] = rec end
        if inScope or q ~= "" then
            local ok, hit = Passes(rec, q)
            if ok then
                shown[#shown + 1] = rec
                matches[rec] = hit
            end
        end
    end
    return scoped, shown, matches
end

local function RollRows(shown, matches)
    local rows, lastV = {}, nil
    for _, rec in ipairs(shown) do
        if rec.v ~= lastV then
            lastV = rec.v
            rows[#rows + 1] = { kind = "hdr", v = ns.visitById[rec.v], h = 24 }
        end
        rows[#rows + 1] = { kind = "item", rec = rec, match = matches and matches[rec], h = 38 }
    end
    if #rows == 0 then
        rows[1] = { kind = "empty", h = 40, text = #ns.db.rolls == 0 and L["No rolls yet"] or L["Nothing matches"] }
    end
    return rows
end

-- The visits of the current selection (for the looted coins, which belong to visits).
local function VisitInScope(v)
    local sel = state.sel
    if sel.kind == "all" then return true end
    if sel.kind == "visit" then return v.id == sel.key end
    if sel.kind == "day" then return ns.DayKey(v.t) == sel.key end
    if sel.kind == "place" then return v.place == sel.key end
    return false
end

-- Stats the player can switch off (the "Shown stats" menu), in display order.
local STATS = {
    { key = "items",   label = "Items dropped" },
    { key = "picks",   label = "Your Need / Greed / Pass" },
    { key = "won",     label = "Items won" },
    { key = "money",   label = "Money looted" },
    { key = "gold",    label = "Gold won (vendor value)" },
    { key = "ah",      label = "Won items at AH prices" },
    { key = "total",   label = "Total (money + vendor value)" },
    { key = "all",     label = "Vendor value of all drops" },
    { key = "allAH",   label = "AH value of all drops" },
    { key = "places",  label = "Gold by place" },
    { key = "winners", label = "Most items won" },
}
local function StatOn(key) return not ns.db.opts.hideStats[key] end

-- "Only me": just the items you rolled on, and only you in "Most items won".
local function Mine(rec)
    if rec.mw or (rec.my and rec.my ~= S.NONE) then return true end
    for _, e in ipairs(rec.rolls or {}) do
        if e.me then return true end
    end
    return false
end

local function StatRows(scoped)
    local onlyMe = ns.db.opts.statsMine
    if onlyMe then
        local mine = {}
        for _, rec in ipairs(scoped) do
            if Mine(rec) then mine[#mine + 1] = rec end
        end
        scoped = mine
    end
    local me = ns.MyName()
    local sum = ns.Sum(scoped)
    local money, moneyByPlace = 0, {}
    for _, v in ipairs(ns.db.visits) do
        if (v.money or 0) > 0 and VisitInScope(v) then
            money = money + v.money
            moneyByPlace[v.place] = (moneyByPlace[v.place] or 0) + v.money
        end
    end
    local values = {
        items = tostring(sum.items),
        picks = format("%d / %d / %d", sum.need, sum.greed, sum.pass),
        won = tostring(sum.won),
        money = ns.Money(money),
        gold = ns.Money(sum.gold),
        ah = ns.Money(sum.ah),
        total = ns.Money(money + sum.gold),
        all = ns.Money(sum.all),
        allAH = ns.Money(sum.allAH),
    }
    local accent = { money = true, gold = true, ah = true, total = true }
    local rows = { { kind = "shdr", text = L["Overview"], h = 26 } }
    for _, s in ipairs(STATS) do
        if values[s.key] and StatOn(s.key) then
            rows[#rows + 1] = { kind = "stat", h = 22, text = L[s.label], value = values[s.key], accent = accent[s.key] }
        end
    end
    if #rows == 1 then rows = {} end

    if StatOn("places") then
        rows[#rows + 1] = { kind = "shdr", text = L["Gold by place"], h = 30 }
        local listed = {}
        for _, p in ipairs(ns.GoldByPlace(scoped)) do
            listed[p.place] = true
            local m = moneyByPlace[p.place] or 0
            rows[#rows + 1] = {
                kind = "place", h = 34, text = p.place, value = ns.Money(p.gold + m),
                sub = format("%s  ·  %s  ·  %s", p.runs == 1 and L["1 run"] or format(L["%d runs"], p.runs),
                    p.items == 1 and L["1 item"] or format(L["%d items"], p.items), format(L["won %d"], p.won))
                    .. (m > 0 and ("  ·  " .. L["Money"] .. " " .. ns.Money(m)) or "")
                    .. (p.ah > 0 and ("  ·  AH " .. ns.Money(p.ah)) or ""),
            }
        end
        -- Places where only coins were looted.
        for place, m in pairs(moneyByPlace) do
            if not listed[place] then
                rows[#rows + 1] = { kind = "place", h = 34, text = place, value = ns.Money(m),
                    sub = L["Money"] .. " " .. ns.Money(m) }
            end
        end
    end

    local winners, wlist = {}, {}
    local showWinners = StatOn("winners")
    for _, rec in ipairs(scoped) do
        if showWinners and rec.win and (not onlyMe or rec.mw or rec.win == me) then
            local w = winners[rec.win]
            if not w then
                w = { name = rec.win, class = rec.wc, count = 0, gold = 0 }
                winners[rec.win] = w
                wlist[#wlist + 1] = w
            end
            w.count = w.count + 1
            w.gold = w.gold + (rec.sell or 0)
        end
    end
    if #wlist > 0 then
        sort(wlist, function(a, b)
            if a.count ~= b.count then return a.count > b.count end
            return a.name < b.name
        end)
        rows[#rows + 1] = { kind = "shdr", text = L["Most items won"], h = 30 }
        for i = 1, min(10, #wlist) do
            local w = wlist[i]
            rows[#rows + 1] = { kind = "stat", h = 22, text = ns.ClassName(w.name, w.class),
                value = format("%d  |cff9a9a9a(%s)|r", w.count, ns.Money(w.gold)) }
        end
    end
    if #rows == 0 then
        rows[1] = { kind = "empty", h = 40, text = L["No stats selected"] }
    end
    return rows, sum
end

local function SelectionTitle()
    local sel = state.sel
    return sel.title or sel.label or L["All rolls"]
end

-------------------------------------------------------------------------------
--  Left: tree
-------------------------------------------------------------------------------
local function TreeMake(l)
    local row = CreateFrame("Button", nil, l)
    St.RowBackground(row)
    row.exp = St.Text(row, 12, "CENTER")
    row.exp:SetWidth(12)
    row.label = St.Text(row, 11)
    row.count = St.Text(row, 10, "RIGHT")
    row.count:SetPoint("RIGHT", -6, 0)
    row.label:SetPoint("RIGHT", row.count, "LEFT", -4, 0)
    row:SetScript("OnClick", function(self)
        local item = self.item
        if not item then return end
        local same = state.sel.kind == item.kind and state.sel.key == item.key
        if item.okey then
            if same then
                state.open[item.okey] = not state.open[item.okey]
            else
                state.open[item.okey] = true
            end
        end
        state.sel = { kind = item.kind, key = item.key, label = item.label, title = item.title }
        History:Refresh()
    end)
    row:SetScript("OnEnter", function(self) self:PaintState(self.selected) end)
    row:SetScript("OnLeave", function(self) self:PaintState(self.selected) end)
    return row
end

local function TreeFill(row, item)
    local indent = item.indent and 16 or 0
    row.exp:ClearAllPoints()
    row.exp:SetPoint("LEFT", 6 + indent, 0)
    row.label:ClearAllPoints()
    row.label:SetPoint("LEFT", 22 + indent, 0)
    row.label:SetPoint("RIGHT", row.count, "LEFT", -4, 0)
    if item.okey then
        row.exp:SetText(item.open and "-" or "+")
        row.exp:Show()
    else
        row.exp:Hide()
    end
    row.label:SetText(item.label)
    row.count:SetText(item.count or "")
    row.selected = state.sel.kind == item.kind and state.sel.key == item.key
    if row.selected then
        row.label:SetTextColor(St.Accent())
    else
        row.label:SetTextColor(1, 1, 1, item.indent and 0.7 or 0.9)
    end
    row.count:SetTextColor(1, 1, 1, 0.45)
    row.exp:SetTextColor(1, 1, 1, 0.5)
    row:PaintState(row.selected)
end

-------------------------------------------------------------------------------
--  Middle: items / stats
-------------------------------------------------------------------------------
local function ShowItemTip(owner, rec)
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
end

local function ListMake(l)
    local row = CreateFrame("Button", nil, l)
    St.RowBackground(row)
    row.icon = St.Icon(row, 26)
    row.icon:SetPoint("LEFT", 6, 0)
    row.title = St.Text(row, 11)
    row.sub = St.Text(row, 10)
    row.value = St.Text(row, 11, "RIGHT")
    row.value:SetPoint("RIGHT", -8, 0)
    row.stateIcon = row:CreateTexture(nil, "OVERLAY")
    row.stateIcon:SetSize(13, 13)
    row.stateIcon:SetPoint("RIGHT", row.value, "LEFT", -3, 0)
    row.sep = St.Fill(row, { 1, 1, 1, 0.07 }, "BORDER")
    row.sep:SetPoint("BOTTOMLEFT", 6, 2); row.sep:SetPoint("BOTTOMRIGHT", -6, 2); row.sep:SetHeight(1)
    row:SetScript("OnClick", function(self)
        local item = self.item
        if not (item and item.rec) then return end
        if IsModifiedClick("CHATLINK") then
            HandleModifiedItemClick(item.rec.link)
            return
        end
        state.selRec = item.rec.id
        History:Refresh(true)
    end)
    row:SetScript("OnEnter", function(self)
        self:PaintState(self.selected)
        if self.item and self.item.rec then ShowItemTip(self, self.item.rec) end
    end)
    row:SetScript("OnLeave", function(self)
        self:PaintState(self.selected)
        GameTooltip:Hide()
    end)
    return row
end

local function ListFill(row, item)
    local kind = item.kind
    row.title:ClearAllPoints()
    row.sub:ClearAllPoints()
    row.icon:Hide()
    row.sub:Hide()
    row.stateIcon:Hide()
    row.sep:Hide()
    row.selected = false
    row.title:SetTextColor(1, 1, 1, 1)
    row.value:SetTextColor(1, 1, 1, 0.9)
    row.value:SetText("")
    row:EnableMouse(kind == "item")

    if kind == "item" then
        local rec = item.rec
        row.icon:Show()
        row.icon:SetItem(rec.icon, rec.q)
        row.title:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 8, -1)
        row.title:SetPoint("RIGHT", row, "RIGHT", -58, 0)
        row.title:SetText(rec.n or "?")
        row.title:SetTextColor(ns.QualityColor(rec.q))
        row.sub:Show()
        row.sub:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -3)
        row.sub:SetPoint("RIGHT", row, "RIGHT", -58, 0)
        if rec.ap then
            row.sub:SetText("|cff9a9a9a" .. L["Everyone passed"] .. "|r")
        elseif rec.win then
            row.sub:SetText(L["Won by"] .. " " .. ns.ClassName(rec.win, rec.wc) .. " " .. St.StateMarkup(rec.ws, 11) .. " " .. (rec.wr or ""))
        else
            row.sub:SetText("|cff9a9a9a" .. L["Rolling..."] .. "|r")
        end
        -- Right: the searched player's pick and roll, else your own.
        local m = item.match
        local s, r, w
        if m then
            s, r, w = m.s, m.r, m.w
        else
            s, r, w = rec.my, rec.mr, rec.mw
        end
        if s and s ~= S.NONE then
            St.SetStateIcon(row.stateIcon, s)
            row.value:SetText(r or "")
            if w then row.value:SetTextColor(St.Accent()) end
        elseif m then
            row.value:SetText("|cff777777-|r")
        end
        row.selected = state.selRec == rec.id
    elseif kind == "hdr" then
        local v = item.v
        row.title:SetPoint("BOTTOMLEFT", 8, 5)
        row.title:SetPoint("RIGHT", row, "RIGHT", -110, 0)
        row.title:SetText(v and v.place or L["Unknown"])
        row.title:SetTextColor(1, 1, 1, 0.85)
        row.value:ClearAllPoints()
        row.value:SetPoint("BOTTOMRIGHT", -8, 5)
        row.value:SetText(v and (ns.DayLabel(v.t) .. ", " .. ns.Clock(v.t)) or "")
        row.value:SetTextColor(1, 1, 1, 0.5)
        row.sep:Show()
    elseif kind == "shdr" then
        row.title:SetPoint("BOTTOMLEFT", 8, 6)
        row.title:SetText(item.text)
        local r, g, b = St.Accent()
        row.title:SetTextColor(r, g, b, 0.9)
        row.sep:Show()
    elseif kind == "stat" then
        row.title:SetPoint("LEFT", 10, 0)
        row.title:SetPoint("RIGHT", row, "RIGHT", -120, 0)
        row.title:SetText(item.text)
        row.title:SetTextColor(1, 1, 1, item.accent and 1 or St.DIM + 0.15)
        row.value:SetText(item.value)
        if item.accent then row.value:SetTextColor(1, 1, 1, 1) end
    elseif kind == "place" then
        row.title:SetPoint("TOPLEFT", 10, -4)
        row.title:SetPoint("RIGHT", row, "RIGHT", -110, 0)
        row.title:SetText(item.text)
        row.sub:Show()
        row.sub:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -3)
        row.sub:SetPoint("RIGHT", row, "RIGHT", -110, 0)
        row.sub:SetText("|cff9a9a9a" .. item.sub .. "|r")
        row.value:SetText(item.value)
    elseif kind == "empty" then
        row.title:SetPoint("CENTER", 0, 0)
        row.title:SetText(item.text)
        row.title:SetTextColor(1, 1, 1, 0.45)
    end
    if kind ~= "hdr" then
        row.value:ClearAllPoints()
        row.value:SetPoint("RIGHT", -8, 0)
    end
    row:PaintState(row.selected)
end

-------------------------------------------------------------------------------
--  Right: detail of one item
-------------------------------------------------------------------------------
local function DetailMake(l)
    local row = CreateFrame("Frame", nil, l)
    row.bg = St.Fill(row, { 1, 1, 1, 0 })
    row.bg:SetAllPoints()
    row.check = row:CreateTexture(nil, "OVERLAY")
    row.check:SetSize(12, 12)
    row.check:SetPoint("LEFT", 6, 0)
    row.check:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
    row.name = St.Text(row, 11)
    row.name:SetPoint("LEFT", 22, 0)
    row.name:SetWidth(120)
    row.pill = St.Pill(row, 62, 15)
    row.pill:SetPoint("LEFT", 150, 0)
    row.roll = St.Text(row, 11, "RIGHT")
    row.roll:SetPoint("RIGHT", -8, 0)
    return row
end

local function DetailFill(row, e)
    local r, g, b = ns.ClassColor(e.c)
    row.name:SetText(e.n)
    row.name:SetTextColor(r, g, b, e.s == S.NONE and 0.55 or 1)
    row.pill:SetState(e.s)
    row.check:SetShown(e.w == true)
    row.roll:SetText(e.r or "")
    if e.w then
        local ar, ag, ab = St.Accent()
        row.bg:SetColorTexture(ar, ag, ab, 0.12)
        row.roll:SetTextColor(ar, ag, ab, 1)
    else
        row.bg:SetColorTexture(1, 1, 1, e.me and 0.04 or 0)
        row.roll:SetTextColor(1, 1, 1, 0.85)
    end
end

local function BuildDetail(parent)
    local d = CreateFrame("Frame", nil, parent)
    d:SetAllPoints()
    d.icon = St.Icon(d, 36)
    d.icon:SetPoint("TOPLEFT", 10, -10)
    d.icon:EnableMouse(true)
    d.icon:SetScript("OnEnter", function(self) if d.rec then ShowItemTip(self, d.rec) end end)
    d.icon:SetScript("OnLeave", function() GameTooltip:Hide() end)
    d.icon:SetScript("OnMouseUp", function()
        if d.rec and IsModifiedClick("CHATLINK") then HandleModifiedItemClick(d.rec.link) end
    end)
    d.name = St.Text(d, 13)
    d.name:SetPoint("TOPLEFT", d.icon, "TOPRIGHT", 8, -2)
    d.name:SetPoint("RIGHT", d, "RIGHT", -8, 0)
    d.where = St.Text(d, 10)
    d.where:SetPoint("TOPLEFT", d.name, "BOTTOMLEFT", 0, -5)
    d.where:SetPoint("RIGHT", d, "RIGHT", -8, 0)
    d.where:SetTextColor(1, 1, 1, St.DIM)
    d.result = St.Text(d, 11)
    d.result:SetPoint("TOPLEFT", 10, -56)
    d.result:SetPoint("RIGHT", d, "RIGHT", -8, 0)
    d.value = St.Text(d, 10)
    d.value:SetPoint("TOPLEFT", 10, -74)
    d.value:SetPoint("RIGHT", d, "RIGHT", -8, 0)
    d.mine = St.Text(d, 10)
    d.mine:SetPoint("TOPLEFT", 10, -90)
    d.mine:SetPoint("RIGHT", d, "RIGHT", -8, 0)
    local sep = St.Fill(d, { 1, 1, 1, 0.07 }, "BORDER")
    sep:SetPoint("TOPLEFT", 8, -108); sep:SetPoint("TOPRIGHT", -8, -108); sep:SetHeight(1)
    d.sep = sep
    d.players = St.List(d, 22, DetailMake, DetailFill)
    d.players:SetPoint("TOPLEFT", 4, -114)
    d.players:SetPoint("BOTTOMRIGHT", -4, 4)
    d.placeholder = St.Text(d, 11, "CENTER")
    d.placeholder:SetPoint("CENTER")
    d.placeholder:SetText(L["Select an item"])
    d.placeholder:SetTextColor(1, 1, 1, 0.4)

    function d:Display(rec)
        self.rec = rec
        local has = rec ~= nil
        for _, region in ipairs({ self.icon, self.name, self.where, self.result, self.value, self.mine, self.sep, self.players }) do
            region:SetShown(has)
        end
        self.placeholder:SetShown(not has)
        if not has then return end
        self.icon:SetItem(rec.icon, rec.q)
        self.name:SetText(rec.n or "?")
        self.name:SetTextColor(ns.QualityColor(rec.q))
        local v = ns.visitById[rec.v]
        self.where:SetText(format("%s, %s, %s", v and v.place or L["Unknown"], ns.DayLabel(rec.t), ns.Clock(rec.t)))
        self.result:SetText(ns.Status(rec))
        local ah = ns.AH(rec)
        self.value:SetText(format("|cff9a9a9a%s:|r %s     |cff9a9a9a%s:|r %s", L["Vendor value"], ns.Money(rec.sell or 0),
            L["AH value"], ah and ns.Money(ah) or "|cff666666-|r"))
        if rec.my and rec.my ~= S.NONE then
            local info = ns.StateInfo(rec.my)
            self.mine:SetText(format("|cff9a9a9a%s:|r %s %s %s", L["Your roll"], St.StateMarkup(rec.my, 11), info.label, rec.mr or ""))
        else
            self.mine:SetText("")
        end
        self.players:SetData(rec.rolls or {})
    end
    return d
end

-------------------------------------------------------------------------------
--  Window
-------------------------------------------------------------------------------
function History:Refresh(keepOffset)
    if not frame or not frame:IsShown() then return end
    tabDays:SetActive(state.mode == "days")
    tabPlaces:SetActive(state.mode == "places")
    tabRolls:SetActive(state.tab == "rolls")
    tabStats:SetActive(state.tab == "stats")
    for key, b in pairs(filterButtons) do b:SetActive(state.filter == key) end

    tree:SetData(BuildTree(), true)

    local scoped, shown, matches = Collect()
    local sum = ns.Sum(scoped)
    local q = Query()
    if q ~= "" and state.tab == "rolls" then
        -- Searching: the whole history. Count what the found player(s) won.
        local won = 0
        for _, rec in ipairs(shown) do
            local m = matches[rec]
            if m and m.w then won = won + 1 end
        end
        midTitle:SetText(format(L["Search: %s"], state.search))
        midSummary:SetText(format(L["%d items found"], #shown) .. (won > 0 and ("   ·   " .. format(L["won %d"], won)) or ""))
    else
        midTitle:SetText(SelectionTitle())
        midSummary:SetText(format(L["%d items, %d visits, won %d"], sum.items, sum.visits, sum.won) .. "   ·   " .. ns.Money(sum.gold))
    end

    local rows
    if state.tab == "stats" then
        rows = StatRows(scoped)
    else
        rows = RollRows(shown, matches)
    end
    local filterShown = state.tab == "rolls"
    search:SetShown(filterShown)
    for _, b in pairs(filterButtons) do b:SetShown(filterShown) end
    statsChoice:SetShown(not filterShown)
    statsMine:SetShown(not filterShown)
    statsMine:SetActive(ns.db.opts.statsMine == true)
    list:ClearAllPoints()
    list:SetPoint("TOPLEFT", 4, -76)
    list:SetPoint("BOTTOMRIGHT", -4, 4)
    list:SetData(rows, keepOffset)

    local rec = state.selRec and ns.byId[state.selRec]
    if not rec and shown[1] and state.tab == "rolls" then
        rec = shown[1]
        state.selRec = rec.id
        list:Refresh()
    end
    detail:Display(rec)
end

function History:Init()
    frame = St.Window("NibbelzLootHistoryFrame", W, H, L["Roll History"], "history")
    frame:Place({ "CENTER", UIParent, "CENTER", 0, 40 })
    frame:SetScale(ns.db.opts.scale or 1)
    frame:SetFrameStrata("HIGH")
    frame:Hide()
    tinsert(UISpecialFrames, "NibbelzLootHistoryFrame")

    local logo = frame.bar:CreateTexture(nil, "OVERLAY")
    logo:SetSize(16, 16)
    logo:SetPoint("LEFT", 10, 0)
    logo:SetTexture("Interface\\Buttons\\UI-GroupLoot-Dice-Up")
    frame.title:ClearAllPoints()
    frame.title:SetPoint("LEFT", logo, "RIGHT", 6, 0)
    local players = St.Button(frame.bar, L["Group stats"], 120, 18, function() ns.GroupStats:Toggle() end)
    local gear = St.IconButton(frame.bar, "Interface\\Buttons\\UI-OptionsButton", 14, L["Options"],
        function() ns.Options:Toggle() end)
    gear:SetPoint("RIGHT", frame.close, "LEFT", -8, 0)
    players:SetPoint("RIGHT", gear, "LEFT", -8, 0)

    -- Left
    local left = Inset(frame)
    left:SetPoint("TOPLEFT", 8, -TOP)
    left:SetPoint("BOTTOMLEFT", 8, 8)
    left:SetWidth(LEFT_W)
    local tabW = (LEFT_W - 14) / 2
    tabDays = St.Button(left, L["Days"], tabW, 20, function()
        state.mode = "days"
        if state.sel.kind == "place" or state.sel.kind == "visit" then state.sel = { kind = "all" } end
        History:Refresh()
    end)
    tabDays:SetPoint("TOPLEFT", 6, -6)
    tabPlaces = St.Button(left, L["Places"], tabW, 20, function()
        state.mode = "places"
        if state.sel.kind == "day" or state.sel.kind == "visit" then state.sel = { kind = "all" } end
        History:Refresh()
    end)
    tabPlaces:SetPoint("LEFT", tabDays, "RIGHT", 2, 0)
    tree = St.List(left, 20, TreeMake, TreeFill)
    tree:SetPoint("TOPLEFT", 4, -34)
    tree:SetPoint("BOTTOMRIGHT", -4, 4)

    -- Middle
    local mid = Inset(frame)
    mid:SetPoint("TOPLEFT", left, "TOPRIGHT", 8, 0)
    mid:SetPoint("BOTTOMLEFT", left, "BOTTOMRIGHT", 8, 0)
    mid:SetWidth(MID_W)
    midTitle = St.Text(mid, 15)
    midTitle:SetPoint("TOPLEFT", 10, -9)
    midTitle:SetPoint("RIGHT", mid, "RIGHT", -128, 0)
    tabStats = St.Button(mid, L["Stats"], 60, 20, function() state.tab = "stats"; History:Refresh() end)
    tabStats:SetPoint("TOPRIGHT", -6, -6)
    tabRolls = St.Button(mid, L["Rolls"], 60, 20, function() state.tab = "rolls"; History:Refresh() end)
    tabRolls:SetPoint("RIGHT", tabStats, "LEFT", -2, 0)
    midSummary = St.Text(mid, 10)
    midSummary:SetPoint("TOPLEFT", 10, -32)
    midSummary:SetPoint("RIGHT", mid, "RIGHT", -8, 0)
    midSummary:SetTextColor(1, 1, 1, St.DIM)

    search = St.Search(mid, MID_W - 14 - 64 - 44 - 8, 20, L["Search item or player"], function(text)
        if text ~= state.search then
            state.search = text
            state.selRec = nil
            History:Refresh()
        end
    end)
    search:SetPoint("TOPLEFT", 8, -50)
    search:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
        state.search = self:GetText() or ""
        History:Refresh()
    end)
    search:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(L["Search item or player"])
        GameTooltip:AddLine(L["A player's name shows what they picked, rolled and won (right side of each item)."], 1, 1, 1, true)
        GameTooltip:Show()
    end)
    search:HookScript("OnLeave", function() GameTooltip:Hide() end)
    local fWon = St.Button(mid, L["Won"], 64, 20, function() state.filter = "won"; History:Refresh() end)
    fWon:SetPoint("TOPRIGHT", -6, -50)
    local fAll = St.Button(mid, L["All"], 44, 20, function() state.filter = "all"; History:Refresh() end)
    fAll:SetPoint("RIGHT", fWon, "LEFT", -2, 0)
    filterButtons.all, filterButtons.won = fAll, fWon

    -- Stats tab: choose which stats are shown. The menu reopens after each click,
    -- so several can be switched in a row.
    local CHECK = "|TInterface\\Buttons\\UI-CheckBox-Check:14:14|t "
    local function StatItems()
        local items = {}
        for _, s in ipairs(STATS) do
            local key, on = s.key, StatOn(s.key)
            items[#items + 1] = { (on and CHECK or "|cff777777") .. L[s.label] .. (on and "" or "|r"), function()
                ns.db.opts.hideStats[key] = on or nil
                History:Refresh(true)
                St.ContextMenu(StatItems(), statsChoice)
            end, nil, on }
        end
        return items
    end
    statsChoice = St.Dropdown(mid, MID_W - 14 - 96, 20, function() return L["Shown stats"] end, StatItems)
    statsChoice:SetPoint("TOPLEFT", 8, -50)
    statsChoice:Hide()
    -- On / off: only your own stats (items you rolled on, your wins).
    statsMine = St.Button(mid, L["Only me"], 92, 20, function()
        ns.db.opts.statsMine = not ns.db.opts.statsMine or nil
        History:Refresh(true)
    end)
    statsMine:SetPoint("TOPRIGHT", -6, -50)
    statsMine:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(L["Only me"])
        GameTooltip:AddLine(L["On: the stats only count the items you rolled on, and only you in 'Most items won'."], 1, 1, 1, true)
        GameTooltip:Show()
    end)
    statsMine:HookScript("OnLeave", function() GameTooltip:Hide() end)
    statsMine:Hide()

    list = St.List(mid, 38, ListMake, ListFill)

    -- Right
    local right = Inset(frame)
    right:SetPoint("TOPLEFT", mid, "TOPRIGHT", 8, 0)
    right:SetPoint("BOTTOMRIGHT", -8, 8)
    detail = BuildDetail(right)

    frame:SetScript("OnShow", function() History:Refresh() end)
    -- Each pick on a roll notifies: rebuild the lists at most twice a second.
    ns.Listen(function()
        if frame:IsShown() then ns.Debounce("history", 0.5, function() History:Refresh(true) end) end
    end)
end

function History:Toggle()
    if not frame then return end
    frame:SetShown(not frame:IsShown())
end

function History:ApplyScale()
    if frame then frame:SetScale(ns.db.opts.scale or 1) end
end
