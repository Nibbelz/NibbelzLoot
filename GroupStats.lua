-- GroupStats.lua: the people you ran dungeons with -- runs together, items they
-- won and what those were worth (vendor and auction house). Sortable by any
-- column (guild too), filterable, optionally grouped by guild.
-- Compare: tick players (box on the left), then the "Compare" view counts only
-- the runs ALL ticked players did together (ns.CompareStats).
local _, ns = ...
local St, L = ns.St, ns.L

local format, lower, max, min = string.format, string.lower, math.max, math.min
local sort = table.sort

local GS = {}
ns.GroupStats = GS

local W, H = 760, 500
local ROW_H = 22
local DAY = 86400

local frame, list, search, summary, headerButtons
local scopeButtons, viewButtons = {}, {}
local checks = {}
local marked = {}   -- players ticked for the comparison

local state = {
    scope = "all",       -- all | 30 | 7
    sort = "runs",
    desc = true,
    search = "",
    repeatOnly = false,  -- only people you ran with at least twice
    byGuild = false,
    view = "all",        -- all | compare
}

local COLS = {
    { key = "name",  label = L["Player"],       x = 30,  w = 140, justify = "LEFT",  text = true },
    { key = "g",     label = L["Guild"],        x = 176, w = 160, justify = "LEFT",  text = true },
    { key = "runs",  label = L["Runs"],         x = 340, w = 60,  justify = "RIGHT" },
    { key = "items", label = L["Items"],        x = 404, w = 60,  justify = "RIGHT" },
    { key = "gold",  label = L["Vendor value"], x = 468, w = 120, justify = "RIGHT" },
    { key = "ah",    label = L["AH value"],     x = 592, w = 130, justify = "RIGHT" },
}
local IS_TEXT = { name = true, g = true }

local function Since()
    if state.scope == "all" then return 0 end
    return time() - tonumber(state.scope) * DAY
end

-------------------------------------------------------------------------------
--  Data
-------------------------------------------------------------------------------
local function Compare(a, b)
    local k = state.sort
    local va, vb = a[k], b[k]
    if IS_TEXT[k] then
        va = va and va ~= "" and lower(va) or nil
        vb = vb and vb ~= "" and lower(vb) or nil
        if va ~= vb then
            -- No guild always last.
            if va == nil then return false end
            if vb == nil then return true end
            if state.desc then return va > vb end
            return va < vb
        end
    elseif va ~= vb then
        if state.desc then return va > vb end
        return va < vb
    end
    if a.runs ~= b.runs then return a.runs > b.runs end
    return a.name < b.name
end

local function Build()
    local players = ns.PlayerStats(Since())
    local q = lower(state.search or "")
    local shown = {}
    for _, p in ipairs(players) do
        local ok = true
        if state.repeatOnly and p.runs < 2 and not p.me then ok = false end
        if ok and q ~= "" then
            ok = lower(p.name):find(q, 1, true) ~= nil or (p.g and lower(p.g):find(q, 1, true) ~= nil)
        end
        if ok then shown[#shown + 1] = p end
    end

    local guilds = {}
    for _, p in ipairs(shown) do if p.g then guilds[p.g] = true end end
    local guildCount = 0
    for _ in pairs(guilds) do guildCount = guildCount + 1 end

    local rows = {}
    if state.byGuild then
        local groups, order = {}, {}
        for _, p in ipairs(shown) do
            local key = p.g or ""
            local g = groups[key]
            if not g then
                g = { kind = "guild", name = key ~= "" and key or L["No guild"], g = p.g, noGuild = key == "",
                    runs = 0, items = 0, gold = 0, ah = 0, members = {} }
                groups[key] = g
                order[#order + 1] = g
            end
            g.members[#g.members + 1] = p
            g.runs = max(g.runs, p.runs)
            g.items = g.items + p.items
            g.gold = g.gold + p.gold
            g.ah = g.ah + p.ah
        end
        sort(order, function(a, b)
            if a.noGuild ~= b.noGuild then return b.noGuild end
            local k = state.sort
            if IS_TEXT[k] then
                if state.desc then return lower(a.name) > lower(b.name) end
                return lower(a.name) < lower(b.name)
            end
            if a[k] ~= b[k] then
                if state.desc then return a[k] > b[k] end
                return a[k] < b[k]
            end
            return a.name < b.name
        end)
        for _, g in ipairs(order) do
            g.h = 26
            rows[#rows + 1] = g
            sort(g.members, Compare)
            for _, p in ipairs(g.members) do rows[#rows + 1] = p end
        end
    else
        sort(shown, Compare)
        for _, p in ipairs(shown) do rows[#rows + 1] = p end
    end
    if #rows == 0 then
        rows[1] = { kind = "empty", h = 40 }
    end
    return rows, #shown, guildCount
end

local function MarkedNames()
    local names = {}
    for name in pairs(marked) do names[#names + 1] = name end
    sort(names)
    return names
end

-- The ticked players, counted over the runs they all did together.
local function BuildCompare()
    local names = MarkedNames()
    if #names < 2 then
        return { { kind = "empty", h = 40, text = L["Tick at least two players (box on the left) to compare them."] } }, nil
    end
    local r = ns.CompareStats(names, Since())
    local rows = {}
    for _, p in ipairs(r.players) do rows[#rows + 1] = p end
    sort(rows, Compare)
    return rows, r
end

-------------------------------------------------------------------------------
--  Rows
-------------------------------------------------------------------------------
-- In the comparison: what each one did in the shared runs.
local function CompareTip(owner, p)
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:AddLine(ns.ClassName(p.name, p.c))
    if p.g then GameTooltip:AddLine("<" .. p.g .. ">", 0.6, 0.9, 0.6) end
    GameTooltip:AddDoubleLine(L["Runs together"], p.runs, 1, 1, 1, 1, 1, 1)
    GameTooltip:AddDoubleLine(L["Need picks"], p.needs, 1, 1, 1, 1, 1, 1)
    if p.rolls > 0 then
        GameTooltip:AddDoubleLine(L["Average roll"], format("%.1f", p.rollSum / p.rolls), 1, 1, 1, 1, 1, 1)
        GameTooltip:AddDoubleLine(L["Highest roll"], p.best, 1, 1, 1, 1, 1, 1)
    end
    if #p.won > 0 then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(L["Items won"], 1, 0.82, 0)
        for i = #p.won, max(1, #p.won - 9), -1 do
            local rec = p.won[i]
            local r, g, b = ns.QualityColor(rec.q)
            local ah = ns.AH(rec)
            GameTooltip:AddDoubleLine(rec.n or "?", ah and ns.Money(ah) or ns.Money(rec.sell or 0), r, g, b, 1, 1, 1)
        end
        if #p.won > 10 then GameTooltip:AddLine(format(L["... and %d more"], #p.won - 10), 0.6, 0.6, 0.6) end
    end
    GameTooltip:Show()
end

local function PlayerTip(owner, p)
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:AddLine(ns.ClassName(p.name, p.c))
    if p.g then GameTooltip:AddLine("<" .. p.g .. ">", 0.6, 0.9, 0.6) end
    GameTooltip:AddDoubleLine(L["Runs together"], p.runs, 1, 1, 1, 1, 1, 1)
    local since, n = Since(), 0
    local rolls = ns.db.rolls
    for i = #rolls, 1, -1 do
        local rec = rolls[i]
        if rec.t >= since and rec.win == p.name then
            n = n + 1
            if n == 1 then
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine(L["Items won"], 1, 0.82, 0)
            end
            if n <= 10 then
                local r, g, b = ns.QualityColor(rec.q)
                local ah = ns.AH(rec)
                GameTooltip:AddDoubleLine(rec.n or "?", ah and ns.Money(ah) or ns.Money(rec.sell or 0), r, g, b, 1, 1, 1)
            end
        end
    end
    if n > 10 then GameTooltip:AddLine(format(L["... and %d more"], n - 10), 0.6, 0.6, 0.6) end
    GameTooltip:Show()
end

local function Make(l)
    local row = CreateFrame("Button", nil, l)
    St.RowBackground(row)
    row.cells = {}
    for i, col in ipairs(COLS) do
        local fs = St.Text(row, 11, col.justify)
        fs:SetPoint("LEFT", col.x, 0)
        fs:SetWidth(col.w)
        row.cells[i] = fs
    end
    row.sep = St.Fill(row, { 1, 1, 1, 0.07 }, "BORDER")
    row.sep:SetPoint("BOTTOMLEFT", 6, 1); row.sep:SetPoint("BOTTOMRIGHT", -6, 1); row.sep:SetHeight(1)
    row.empty = St.Text(row, 11, "CENTER")
    row.empty:SetPoint("CENTER")
    -- Tick box: mark this player for the comparison.
    row.box = CreateFrame("Button", nil, row)
    row.box:SetSize(14, 14)
    row.box:SetPoint("LEFT", 8, 0)
    local bbg = St.Fill(row.box, { 0, 0, 0, 0.35 })
    bbg:SetAllPoints()
    St.Border(row.box, 0.3)
    row.mark = row.box:CreateTexture(nil, "ARTWORK")
    row.mark:SetPoint("TOPLEFT", 3, -3)
    row.mark:SetPoint("BOTTOMRIGHT", -3, 3)
    row.box:SetScript("OnClick", function(self)
        local item = self:GetParent().item
        if not (item and item.name and item.kind ~= "guild") then return end
        marked[item.name] = not marked[item.name] or nil
        GS:Refresh(true)
    end)
    row.box:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(L["Tick to compare"], 1, 1, 1)
        GameTooltip:Show()
    end)
    row.box:SetScript("OnLeave", function() GameTooltip:Hide() end)
    row:SetScript("OnEnter", function(self)
        self:PaintState(false)
        local item = self.item
        if item and item.runs and item.kind ~= "guild" then
            if item.won then CompareTip(self, item) else PlayerTip(self, item) end
        end
    end)
    row:SetScript("OnLeave", function(self)
        self:PaintState(false)
        GameTooltip:Hide()
    end)
    return row
end

local function Fill(row, item)
    local c = row.cells
    row.empty:Hide()
    row.sep:Hide()
    row.box:Hide()
    for _, fs in ipairs(c) do fs:Show(); fs:SetTextColor(1, 1, 1, 0.85) end
    c[1]:SetPoint("LEFT", COLS[1].x, 0)
    if item.kind == "empty" then
        for _, fs in ipairs(c) do fs:Hide() end
        row.empty:Show()
        row.empty:SetText(item.text or (#ns.db.rolls == 0 and L["No rolls yet"] or L["Nothing matches"]))
        row.empty:SetTextColor(1, 1, 1, 0.45)
        row:PaintState(false)
        return
    end
    if item.kind == "guild" then
        local r, g, b = St.Accent()
        c[1]:SetText(item.name)
        c[1]:SetTextColor(r, g, b, 1)
        c[2]:SetText(format(L["%d players"], #item.members))
        c[2]:SetTextColor(1, 1, 1, 0.5)
        c[3]:SetText("")
        c[4]:SetText(item.items)
        c[5]:SetText(ns.Money(item.gold))
        c[6]:SetText(item.ah > 0 and ns.Money(item.ah) or "|cff666666-|r")
        row.sep:Show()
        row:PaintState(false)
        row.hl:SetColorTexture(r, g, b, 0.06)
        return
    end
    row.box:Show()
    local r, g, b = St.Accent()
    row.mark:SetColorTexture(r, g, b, 1)
    row.mark:SetShown(marked[item.name] == true)
    local indent = (state.byGuild and state.view == "all") and 12 or 0
    c[1]:SetPoint("LEFT", COLS[1].x + indent, 0)
    c[1]:SetText(ns.ClassName(item.name, item.c) .. (item.me and ("  |cff9a9a9a(" .. L["You"] .. ")|r") or ""))
    c[2]:SetText(item.g or "|cff666666-|r")
    c[2]:SetTextColor(0.6, 0.9, 0.6, item.g and 0.9 or 1)
    c[3]:SetText(item.runs)
    c[4]:SetText(item.items)
    c[5]:SetText(item.gold > 0 and ns.Money(item.gold) or "|cff666666-|r")
    c[6]:SetText(item.ah > 0 and ns.Money(item.ah) or "|cff666666-|r")
    row:PaintState(false)
    if item.me then row.hl:SetColorTexture(1, 1, 1, 0.04) end
end

-------------------------------------------------------------------------------
--  Window
-------------------------------------------------------------------------------
local function PaintHeaders()
    for _, h in ipairs(headerButtons) do
        local on = state.sort == h.key
        h.arrow:SetShown(on)
        h.arrow:SetTexture(state.desc and "Interface\\Buttons\\Arrow-Down-Up" or "Interface\\Buttons\\Arrow-Up-Up")
        if on then
            h.text:SetTextColor(St.Accent())
        else
            h.text:SetTextColor(1, 1, 1, 0.6)
        end
    end
end

function GS:Refresh(keepOffset)
    if not frame or not frame:IsShown() then return end
    for key, b in pairs(scopeButtons) do b:SetActive(state.scope == key) end
    local count = #MarkedNames()
    viewButtons.all:SetActive(state.view == "all")
    viewButtons.compare:SetActive(state.view == "compare")
    viewButtons.compare.text:SetText(format(L["Compare (%d)"], count))
    viewButtons.clear:SetShown(count > 0)
    local compare = state.view == "compare"
    checks.repeatOnly:SetShown(not compare)
    checks.byGuild:SetShown(not compare)
    -- The comparison's summary (shared runs per dungeon) gets the whole line.
    summary:ClearAllPoints()
    summary:SetPoint("TOPRIGHT", -10, -69)
    summary:SetPoint("LEFT", frame, "LEFT", compare and 12 or 450, 0)
    summary:SetJustifyH(compare and "LEFT" or "RIGHT")
    PaintHeaders()

    local text
    if compare then
        local rows, r = BuildCompare()
        list:SetData(rows, keepOffset)
        if r then
            local parts = {}
            for i, p in ipairs(r.places) do
                if i > 4 then
                    parts[#parts + 1] = "..."
                    break
                end
                parts[#parts + 1] = format("%s %dx", p.place, p.n)
            end
            text = format(L["%d runs together"], r.runs) .. (#parts > 0 and ("  ·  " .. table.concat(parts, ", ")) or "")
        else
            text = ""
        end
    else
        local rows, players, guilds = Build()
        list:SetData(rows, keepOffset)
        text = format(L["%d players, %d guilds"], players, guilds)
    end
    if not ns.HasAH() then text = text .. "   |cffff6655" .. L["AH prices need TSM, Auctionator, Auctioneer or NaowhForever"] .. "|r" end
    summary:SetText(text)
end

local function Init()
    frame = St.Window("NibbelzLootGroupStatsFrame", W, H, L["Group stats"], "groupstats")
    frame:Place({ "CENTER", UIParent, "CENTER", 40, 20 })
    St.Resizable(frame, 700, 360, 1400, 1000, function() GS:Refresh(true) end)
    frame:SetScale(ns.db.opts.scale or 1)
    frame:SetFrameStrata("HIGH")
    frame:Hide()
    tinsert(UISpecialFrames, "NibbelzLootGroupStatsFrame")

    local logo = frame.bar:CreateTexture(nil, "OVERLAY")
    logo:SetSize(16, 16)
    logo:SetPoint("LEFT", 10, 0)
    logo:SetTexture("Interface\\Icons\\INV_Misc_GroupNeedMore")
    logo:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    frame.title:ClearAllPoints()
    frame.title:SetPoint("LEFT", logo, "RIGHT", 6, 0)

    -- Toolbar: time range, search, filters.
    local scopes = { { "all", L["All time"], 78 }, { "30", L["30 days"], 70 }, { "7", L["7 days"], 70 } }
    local prev
    for _, s in ipairs(scopes) do
        local key = s[1]
        local b = St.Button(frame, s[2], s[3], 20, function()
            state.scope = key
            GS:Refresh()
        end)
        if prev then b:SetPoint("LEFT", prev, "RIGHT", 2, 0) else b:SetPoint("TOPLEFT", 8, -38) end
        scopeButtons[key] = b
        prev = b
    end
    -- All players / only the ticked ones, counted over their shared runs.
    viewButtons.all = St.Button(frame, L["All players"], 100, 20, function()
        state.view = "all"
        GS:Refresh()
    end)
    viewButtons.all:SetPoint("LEFT", prev, "RIGHT", 14, 0)
    viewButtons.compare = St.Button(frame, L["Compare (%d)"], 100, 20, function()
        state.view = "compare"
        GS:Refresh()
    end)
    viewButtons.compare:SetPoint("LEFT", viewButtons.all, "RIGHT", 2, 0)
    viewButtons.clear = St.Button(frame, L["Clear ticks"], 96, 20, function()
        wipe(marked)
        GS:Refresh(true)
    end)
    viewButtons.clear:SetPoint("LEFT", viewButtons.compare, "RIGHT", 2, 0)

    search = St.Search(frame, 170, 20, L["Search player or guild"], function(text)
        if text ~= state.search then
            state.search = text
            GS:Refresh()
        end
    end)
    search:SetPoint("TOPRIGHT", -8, -38)

    checks.repeatOnly = St.Checkbox(frame, L["Only people I ran with 2+ times"], function(on)
        state.repeatOnly = on
        GS:Refresh()
    end)
    checks.repeatOnly:SetPoint("TOPLEFT", 8, -64)
    checks.repeatOnly:SetWidth(240)
    checks.byGuild = St.Checkbox(frame, L["Group by guild"], function(on)
        state.byGuild = on
        GS:Refresh()
    end)
    checks.byGuild:SetPoint("TOPLEFT", 256, -64)
    checks.byGuild:SetWidth(180)
    summary = St.Text(frame, 10, "RIGHT")
    summary:SetPoint("TOPRIGHT", -10, -69)
    summary:SetPoint("LEFT", frame, "LEFT", 450, 0)
    summary:SetTextColor(1, 1, 1, St.DIM)

    -- Table.
    local inset = CreateFrame("Frame", nil, frame)
    inset:SetPoint("TOPLEFT", 8, -92)
    inset:SetPoint("BOTTOMRIGHT", -8, 8)
    local bg = St.Fill(inset, St.INSET)
    bg:SetAllPoints()
    St.Border(inset, 0.06)

    headerButtons = {}
    local header = CreateFrame("Frame", nil, inset)
    header:SetPoint("TOPLEFT", 4, -2)
    header:SetPoint("TOPRIGHT", -4, -2)
    header:SetHeight(24)
    local hline = St.Fill(header, { 1, 1, 1, 0.08 }, "BORDER")
    hline:SetPoint("BOTTOMLEFT"); hline:SetPoint("BOTTOMRIGHT"); hline:SetHeight(1)
    for _, col in ipairs(COLS) do
        local b = CreateFrame("Button", nil, header)
        b:SetPoint("LEFT", col.x - 2, 0)
        b:SetSize(col.w + 4, 22)
        b.key = col.key
        b.text = St.Text(b, 10, col.justify)
        b.text:SetText(col.label)
        b.arrow = b:CreateTexture(nil, "OVERLAY")
        b.arrow:SetSize(10, 10)
        if col.justify == "RIGHT" then
            b.text:SetPoint("RIGHT", -2, 0)
            b.arrow:SetPoint("RIGHT", b.text, "LEFT", -2, 0)
        else
            b.text:SetPoint("LEFT", 2, 0)
            b.arrow:SetPoint("LEFT", b.text, "RIGHT", 2, 0)
        end
        b:SetScript("OnClick", function(self)
            if state.sort == self.key then
                state.desc = not state.desc
            else
                state.sort = self.key
                state.desc = not IS_TEXT[self.key]   -- names A-Z, numbers high first
            end
            GS:Refresh()
        end)
        b:SetScript("OnEnter", function(self) if state.sort ~= self.key then self.text:SetTextColor(1, 1, 1, 0.9) end end)
        b:SetScript("OnLeave", PaintHeaders)
        headerButtons[#headerButtons + 1] = b
    end

    list = St.List(inset, ROW_H, Make, Fill)
    list:SetPoint("TOPLEFT", 4, -28)
    list:SetPoint("BOTTOMRIGHT", -4, 4)

    frame:SetScript("OnShow", function()
        checks.repeatOnly:SetChecked(state.repeatOnly)
        checks.byGuild:SetChecked(state.byGuild)
        GS:Refresh()
    end)
    -- Each pick on a roll notifies: rebuild the table at most once a second.
    ns.Listen(function()
        if frame:IsShown() then ns.Debounce("groupStats", 1, function() GS:Refresh(true) end) end
    end)
end

function GS:Init()
    Init()
end

function GS:Toggle()
    if not frame then return end
    frame:SetShown(not frame:IsShown())
    if frame:IsShown() then frame:Raise() end
end

function GS:ApplyScale()
    if frame then frame:SetScale(ns.db.opts.scale or 1) end
end
