-- Share.lua: the fair share window.
--
-- Counts what everyone in the group loots (grey items, all items at vendor value,
-- or all items at AH value). Each item is shared among the players who were in the
-- group when it was looted, so someone who leaves early is owed a part only of what
-- dropped while they were there (and someone who joins late, only from then on).
-- The window shows each player's share and who would hand whom how much.
--
-- Leaving the dungeon or the group closes the running share: it moves to the
-- history (ns.db.shareHistory), where it can still be looked at and posted later.
-- Nothing is ever posted to chat on its own: only the "Post in group chat" button.
local _, ns = ...
local St, L = ns.St, ns.L

local format, floor, max = string.format, math.floor, math.max
local sort, concat, tinsert, tremove = table.sort, table.concat, table.insert, table.remove

local Share = {}
ns.Share = Share

local KEEP_HISTORY = 50

local BASES = {
    { key = "grey",   label = L["Grey items"],         field = "grey", money = L["vendor value of grey items"] },
    { key = "vendor", label = L["All items (vendor)"], field = "gold", money = L["vendor value of all items"] },
    { key = "ah",     label = L["All items (AH)"],     field = "ah",   money = L["AH value of all items"] },
}
local BASE_BY_KEY = {}
for _, b in ipairs(BASES) do BASE_BY_KEY[b.key] = b end

local frame, status, list, histList, baseButtons, resetBtn, postBtn, deleteBtn
local selected   -- nil = the running share, else a table from the history

-------------------------------------------------------------------------------
--  Data
--  share = { t, ended, place, key, basis, players = { [name] = { c } },
--            presence = { [name] = { { from, to }, ... } }, out = { [name] = true },
--            events = { { t, n, grey, gold, ah }, ... } }
-------------------------------------------------------------------------------
local function Active()
    return ns.db.share
end

local function History()
    ns.db.shareHistory = ns.db.shareHistory or {}
    return ns.db.shareHistory
end

-- The share on the right: a marked past run, else the running one (in a dungeon).
local function Shown()
    return selected or (ns.ctx.inst and Active()) or nil
end

local function OpenPresence(s, name, now)
    local ivs = s.presence[name]
    if not ivs then
        ivs = {}
        s.presence[name] = ivs
    end
    local last = ivs[#ivs]
    if not last or last.to then ivs[#ivs + 1] = { from = now } end
end

local function ClosePresence(s, name, now)
    local ivs = s.presence[name]
    local last = ivs and ivs[#ivs]
    if last and not last.to then last.to = now end
end

local function Present(s, name, t)
    for _, iv in ipairs(s.presence[name] or {}) do
        if t >= iv.from and (not iv.to or t <= iv.to) then return true end
    end
    return false
end

-- When the player last left the group (nil while still in it).
local function LeftAt(s, name)
    local ivs = s.presence[name]
    local last = ivs and ivs[#ivs]
    return last and last.to
end

local function AddPlayer(s, name, class)
    if not name or name == "" then return end
    local p = s.players[name]
    if not p then
        p = {}
        s.players[name] = p
    end
    if class then p.c = class end
end

-- Who is in the group now: they are present from now on; who is gone, until now.
local function SyncRoster(s)
    local now, here = time(), {}
    for _, unit in ipairs(ns.GroupUnits()) do
        if UnitExists(unit) then
            local name = ns.UnitFullName(unit)
            if name then
                local _, class = UnitClass(unit)
                AddPlayer(s, name, ns.Plain(class, "string"))
                OpenPresence(s, name, now)
                here[name] = true
            end
        end
    end
    for name in pairs(s.presence) do
        if not here[name] then ClosePresence(s, name, now) end
    end
end

local function NewShare(basis)
    local s = {
        t = time(), place = ns.ctx.place, key = ns.ctx.key,
        basis = basis or "grey",
        players = {}, presence = {}, out = {}, events = {},
    }
    ns.db.share = s
    SyncRoster(s)
    return s
end

-- Moves the running share to the history (if anything was looted) and starts a new one.
function Share:Archive()
    local s = Active()
    if s and #s.events > 0 then
        local now = time()
        for name in pairs(s.presence) do ClosePresence(s, name, now) end
        s.ended = now
        local h = History()
        tinsert(h, 1, s)
        while #h > KEEP_HISTORY do tremove(h) end
    end
    if selected == s then selected = nil end
    NewShare(s and s.basis)
    self:Refresh()
end

function Share:Reset()
    NewShare(Active() and Active().basis)
    selected = nil
    self:Refresh()
end

local function OnLoot(name, info)
    local s = Active()
    -- Only dungeons (and raids) count: not cities, not the open world.
    if not s or not ns.ctx.inst then return end
    AddPlayer(s, name)
    OpenPresence(s, name, time())   -- whoever loots is in the group right now
    s.events[#s.events + 1] = {
        t = time(), n = name,
        grey = info.quality == 0 and info.sell or 0,
        gold = info.sell, ah = info.ah,
    }
    Share:Refresh()
end

-- Shares from older versions only kept totals per player: one event each.
local function Upgrade(s)
    if type(s) ~= "table" or s.events then return end
    s.events, s.presence = {}, {}
    for name, l in pairs(s.loot or {}) do
        s.events[#s.events + 1] = { t = s.t, n = name, grey = l.grey or 0, gold = l.gold or 0, ah = l.ah or 0 }
    end
    for name in pairs(s.players or {}) do s.presence[name] = { { from = s.t } } end
    s.loot = nil
    s.players, s.out = s.players or {}, s.out or {}
end

-- Everyone's looted value, their share of it and the hand-overs.
function Share:Compute(s)
    local basis = BASE_BY_KEY[s.basis] or BASES[1]
    local own, owed, total = {}, {}, 0
    for name in pairs(s.players) do own[name], owed[name] = 0, 0 end
    for _, e in ipairs(s.events) do
        local v = e[basis.field] or 0
        if v > 0 and not s.out[e.n] then
            total = total + v
            own[e.n] = (own[e.n] or 0) + v
            -- Shared among everyone in the group at that moment.
            local present = {}
            for name in pairs(s.players) do
                if not s.out[name] and (name == e.n or Present(s, name, e.t)) then present[#present + 1] = name end
            end
            local part = v / #present
            for _, name in ipairs(present) do owed[name] = (owed[name] or 0) + part end
        end
    end
    local rows, entries, n = {}, {}, 0
    for name, p in pairs(s.players) do
        local inside = not s.out[name]
        local row = { name = name, c = p.c, value = own[name] or 0, share = floor((owed[name] or 0) + 0.5),
            inside = inside, left = LeftAt(s, name) }
        -- Closed with the share itself: that is not leaving early.
        if s.ended and row.left and row.left >= s.ended then row.left = nil end
        rows[#rows + 1] = row
        if inside then
            n = n + 1
            row.net = (owed[name] or 0) - row.value
            entries[#entries + 1] = { name = name, c = p.c, net = row.net }
        end
    end
    sort(rows, function(a, b)
        if a.inside ~= b.inside then return a.inside end
        if a.value ~= b.value then return a.value > b.value end
        return a.name < b.name
    end)
    local transfers = n > 1 and ns.Settle(entries) or {}
    -- What each one has after the hand-overs (exact, rounding included).
    local byName = {}
    for _, row in ipairs(rows) do
        row.after = row.value
        byName[row.name] = row
    end
    for _, t in ipairs(transfers) do
        if byName[t.from] then byName[t.from].after = byName[t.from].after - t.amount end
        if byName[t.to] then byName[t.to].after = byName[t.to].after + t.amount end
    end
    return { basis = basis, rows = rows, total = total, n = n, transfers = transfers }
end

-- A made-up run in the history, to try the window: five players, grey and other
-- loot over an hour, and one player who leaves halfway. Delete it like any run.
local PREVIEW_PLAYERS = {
    { "Syntux Ironveil", "PALADIN" }, { "Wenokah Dawnsong", "PRIEST" },
    { "Aldrin Stonefist", "WARRIOR" }, { "Mirelle Nightshade", "ROGUE" },
}
-- player index (0 = you), minute, grey copper, other vendor copper, AH copper
local PREVIEW_LOOT = {
    { 0, 3, 4500, 0, 0 },      { 1, 5, 2200, 0, 0 },        { 2, 8, 6100, 12000, 45000 },
    { 3, 11, 900, 0, 0 },      { 4, 14, 3300, 0, 0 },       { 0, 18, 1800, 25000, 180000 },
    { 1, 22, 5200, 0, 0 },     { 4, 26, 7400, 0, 0 },       { 2, 31, 1200, 0, 0 },
    { 0, 35, 2600, 0, 0 },     { 3, 39, 8800, 30000, 0 },   { 1, 44, 1500, 0, 0 },
    { 2, 48, 3900, 0, 0 },     { 0, 52, 600, 0, 0 },        { 3, 56, 2700, 0, 0 },
}

function Share:AddPreview()
    local now = time()
    local start = now - 3600
    local me = ns.MyName() or "You"
    local _, myClass = UnitClass("player")
    local s = {
        t = start, ended = start + 3500, place = L["Preview"] .. ": Razorfen Downs", key = "preview",
        basis = "grey", players = {}, presence = {}, out = {}, events = {}, preview = true,
    }
    local names = { [0] = me }
    s.players[me] = { c = myClass }
    s.presence[me] = { { from = start, to = s.ended } }
    for i, p in ipairs(PREVIEW_PLAYERS) do
        names[i] = p[1]
        s.players[p[1]] = { c = p[2] }
        -- Mirelle leaves after 30 minutes: she only shares in what dropped until then.
        s.presence[p[1]] = { { from = start, to = (i == 4) and (start + 1800) or s.ended } }
    end
    for _, e in ipairs(PREVIEW_LOOT) do
        local name = names[e[1]]
        local t = start + e[2] * 60
        -- Nobody loots after leaving.
        local ivs = s.presence[name]
        if t <= ivs[#ivs].to then
            s.events[#s.events + 1] = { t = t, n = name, grey = e[3], gold = e[3] + e[4], ah = e[5] }
        end
    end
    tinsert(History(), 1, s)
    selected = s
    ns.Print(L["Preview run added to the fair share history. Delete it like any other run."])
    self:Refresh()
end

-- Only ever on the button: never on its own.
function Share:Post()
    local channel = ns.GroupChannel()
    if not channel then
        ns.Print(L["You are not in a group."])
        return
    end
    local s = Shown()
    if not s then return end
    local r = self:Compute(s)
    -- "Fair share Razorfen Downs (vendor value of grey items): 19g in total, 3 players."
    -- then one line per hand-over: "Nibbelz trades Niljin 3g 66s 67c".
    local lines = { format(L["Fair share %s (%s): %s in total, %d players."], s.place or "", r.basis.money,
        ns.ChatMoney(r.total), r.n) }
    if #r.transfers == 0 then
        lines[2] = L["Nothing to share: everyone has the same."]
    else
        for _, t in ipairs(r.transfers) do
            lines[#lines + 1] = format(L["%s trades %s %s"], t.from, t.to, ns.ChatMoney(t.amount))
        end
        -- Then what everyone has.
        local parts = {}
        for _, row in ipairs(r.rows) do
            if row.inside then parts[#parts + 1] = row.name .. " " .. ns.ChatMoney(row.after) end
        end
        lines[#lines + 1] = L["Afterwards: "] .. table.concat(parts, ", ")
    end
    for _, line in ipairs(lines) do pcall(SendChatMessage, "[Nibbelz Loot] " .. line, channel) end
end

-------------------------------------------------------------------------------
--  Window: history on the left, the selected share on the right
-------------------------------------------------------------------------------
local COL_VALUE, COL_SHARE = 210, 110   -- right edges, from the row's right side

-- Removes one run from the history; for the running share, starts it over.
local function DeleteRun(run)
    if run == nil or run == Active() then
        Share:Reset()
        ns.Print(L["Running fair share started over."])
        return
    end
    local h = History()
    for i, s in ipairs(h) do
        if s == run then
            tremove(h, i)
            break
        end
    end
    if selected == run then selected = nil end
    ns.Print(format(L["Fair share of %s deleted."], run.place or "?"))
    Share:Refresh()
end

local function HistMake(l)
    local row = CreateFrame("Button", nil, l)
    St.RowBackground(row)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row.title = St.Text(row, 11)
    row.title:SetPoint("TOPLEFT", 10, -5)
    row.title:SetPoint("RIGHT", -8, 0)
    row.sub = St.Text(row, 10)
    row.sub:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -3)
    row.sub:SetPoint("RIGHT", -8, 0)
    row.sub:SetTextColor(1, 1, 1, 0.5)
    -- Left-click marks a run, right-click offers to delete it.
    -- Left-click marks a run. Right-click (read on mouse-up, so it works no
    -- matter which clicks the button listens to) offers to delete it.
    row:SetScript("OnClick", function(self, button)
        local item = self.item
        if not item or button == "RightButton" then return end
        selected = not item.active and item.share or nil
        Share:Refresh()
    end)
    row:SetScript("OnMouseUp", function(self, button)
        local item = self.item
        if button ~= "RightButton" or not item then return end
        local run = item.share
        selected = not item.active and run or nil
        Share:Refresh()
        St.ContextMenu({
            { item.active and L["Start the running share over"] or L["Delete this run"],
              function() DeleteRun(run) end, true },
            { CANCEL or "Cancel", function() end },
        })
    end)
    row:SetScript("OnEnter", function(self) self:PaintState(self.selected) end)
    row:SetScript("OnLeave", function(self) self:PaintState(self.selected) end)
    return row
end

local function HistFill(row, item)
    local s = item.share
    local count = 0
    for _ in pairs(s.players) do count = count + 1 end
    if item.active then
        row.title:SetText(L["Running"] .. "  |cff9a9a9a" .. (s.place or "") .. "|r")
        row.sub:SetText(format(L["since %s"], ns.Clock(s.t)) .. "  ·  " .. ns.Players(count))
    else
        row.title:SetText(s.place or "?")
        row.sub:SetText(format("%s %s  ·  %s", ns.DayLabel(s.t), ns.Clock(s.t), ns.Players(count)))
    end
    row.selected = Shown() == s
    if row.selected then row.title:SetTextColor(St.Accent()) else row.title:SetTextColor(1, 1, 1, 0.9) end
    row:PaintState(row.selected)
end

local function Make(l)
    local row = CreateFrame("Button", nil, l)
    St.RowBackground(row)
    row.box = CreateFrame("Frame", nil, row)
    row.box:SetSize(14, 14)
    row.box:SetPoint("LEFT", 8, 0)
    local bg = St.Fill(row.box, { 0, 0, 0, 0.35 })
    bg:SetAllPoints()
    St.Border(row.box, 0.3)
    row.mark = row.box:CreateTexture(nil, "ARTWORK")
    row.mark:SetPoint("TOPLEFT", 3, -3)
    row.mark:SetPoint("BOTTOMRIGHT", -3, 3)
    row.left = St.Text(row, 11)
    row.c1 = St.Text(row, 11, "RIGHT")
    row.c1:SetPoint("RIGHT", -COL_VALUE, 0)
    row.c2 = St.Text(row, 11, "RIGHT")
    row.c2:SetPoint("RIGHT", -COL_SHARE, 0)
    row.c3 = St.Text(row, 11, "RIGHT")
    row.c3:SetPoint("RIGHT", -8, 0)
    row:SetScript("OnClick", function(self, button)
        local item = self.item
        if item and item.kind == "player" and button ~= "RightButton" then
            local s = Shown()
            s.out[item.name] = item.inside and true or nil
            Share:Refresh()
        end
    end)
    -- Right-click a player: leave out / take back in, or delete what they looted.
    row:SetScript("OnMouseUp", function(self, button)
        local item = self.item
        if button ~= "RightButton" or not (item and item.kind == "player") then return end
        local s, name = Shown(), item.name
        St.ContextMenu({
            { item.inside and L["Leave out of the share"] or L["Count in the share again"], function()
                s.out[name] = item.inside and true or nil
                Share:Refresh()
            end },
            { format(L["Delete %s's loot"], name), function()
                for i = #s.events, 1, -1 do
                    if s.events[i].n == name then tremove(s.events, i) end
                end
                ns.Print(format(L["Loot of %s deleted from this fair share."], name))
                Share:Refresh()
            end, true },
            { format(L["Remove %s completely"], name), function()
                for i = #s.events, 1, -1 do
                    if s.events[i].n == name then tremove(s.events, i) end
                end
                s.players[name], s.presence[name], s.out[name] = nil, nil, nil
                ns.Print(format(L["%s removed from this fair share."], name))
                Share:Refresh()
            end, true },
            { CANCEL or "Cancel", function() end },
        })
    end)
    row:SetScript("OnEnter", function(self)
        self:PaintState(false)
        if self.item and self.item.kind == "player" then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(ns.ClassName(self.item.name, self.item.c))
            GameTooltip:AddDoubleLine(L["Looted"], ns.Money(self.item.value), 1, 1, 1, 1, 1, 1)
            GameTooltip:AddDoubleLine(L["Their share"], ns.Money(self.item.share), 1, 1, 1, 1, 1, 1)
            GameTooltip:AddDoubleLine(L["After evening out"], ns.Money(self.item.after), 1, 1, 1, 1, 1, 1)
            if self.item.left then
                GameTooltip:AddLine(format(L["Left the group at %s: shares only in what dropped until then."], ns.Clock(self.item.left)), 0.8, 0.8, 0.8, true)
            end
            GameTooltip:AddLine(L["Click to leave them out of the share."], 0.6, 0.6, 0.6)
            GameTooltip:AddLine(L["Right-click: more (delete their loot, remove them)."], 0.6, 0.6, 0.6)
            GameTooltip:Show()
        end
    end)
    row:SetScript("OnLeave", function(self)
        self:PaintState(false)
        GameTooltip:Hide()
    end)
    return row
end

local function Fill(row, item)
    row.box:Hide()
    row.c1:SetText(""); row.c2:SetText(""); row.c3:SetText("")
    row.c1:SetTextColor(1, 1, 1, 0.9); row.c2:SetTextColor(1, 1, 1, 0.9); row.c3:SetTextColor(1, 1, 1, 0.9)
    row.left:ClearAllPoints()
    row.left:SetTextColor(1, 1, 1, 1)
    row.left:SetAlpha(1)
    row:EnableMouse(item.kind == "player")
    if item.kind == "head" then
        row.left:SetPoint("BOTTOMLEFT", 8, 4)
        row.left:SetText(item.text)
        local r, g, b = St.Accent()
        row.left:SetTextColor(r, g, b, 0.9)
        row.c3:SetText(item.right or "")
        row.c3:SetTextColor(1, 1, 1, 0.6)
    elseif item.kind == "cols" then
        row.left:SetPoint("LEFT", 30, 0)
        row.left:SetText(L["Player"])
        row.left:SetTextColor(1, 1, 1, 0.5)
        row.c1:SetText(L["Looted"]); row.c1:SetTextColor(1, 1, 1, 0.5)
        row.c2:SetText(L["After evening out"]); row.c2:SetTextColor(1, 1, 1, 0.5)
        row.c3:SetText(L["Difference"]); row.c3:SetTextColor(1, 1, 1, 0.5)
    elseif item.kind == "player" then
        row.box:Show()
        local r, g, b = St.Accent()
        row.mark:SetColorTexture(r, g, b, 1)
        row.mark:SetShown(item.inside)
        row.left:SetPoint("LEFT", 30, 0)
        row.left:SetText(ns.ClassName(item.name, item.c)
            .. (item.left and ("  |cff9a9a9a(" .. format(L["left %s"], ns.Clock(item.left)) .. ")|r") or ""))
        row.left:SetAlpha(item.inside and 1 or 0.45)
        row.c1:SetText(ns.Money(item.value))
        if item.inside then
            row.c2:SetText(ns.Money(item.after))
            local r, g, b = St.Accent()
            row.c2:SetTextColor(r, g, b, 1)
            local diff = item.net and floor(item.net + 0.5) or 0
            if diff > 0 then
                row.c3:SetText("|cff66dd66+" .. ns.Money(diff) .. "|r")
            elseif diff < 0 then
                row.c3:SetText("|cffff6655-" .. ns.Money(-diff) .. "|r")
            end
        else
            row.c3:SetText("|cff777777" .. L["not included"] .. "|r")
        end
    elseif item.kind == "transfer" then
        row.left:SetPoint("LEFT", 12, 0)
        row.left:SetText(ns.ClassName(item.t.from, item.t.fc) .. "  |cff9a9a9a" .. L["gives"] .. "|r  " .. ns.ClassName(item.t.to, item.t.tc))
        row.c3:SetText(ns.Money(item.t.amount))
    else
        row.left:SetPoint("LEFT", 12, 0)
        row.left:SetText(item.text)
        row.left:SetTextColor(1, 1, 1, 0.5)
    end
    row:PaintState(false)
end

function Share:Refresh()
    if not frame or not frame:IsShown() then return end
    local inDungeon = ns.ctx.inst

    -- History list: the running share (only inside a dungeon), then the past ones.
    local items = {}
    if inDungeon then items[1] = { share = Active(), active = true, h = 36 } end
    for _, h in ipairs(History()) do items[#items + 1] = { share = h, h = 36 } end
    histList:SetData(items, true)

    -- Outside a dungeon nothing runs: show the newest past run, or nothing.
    if not inDungeon and not selected then selected = History()[1] end
    local s = selected or (inDungeon and Active()) or nil
    resetBtn:SetShown(inDungeon and not selected)
    deleteBtn:SetShown(selected ~= nil)
    if not s then
        for _, b in pairs(baseButtons) do b:SetActive(false) end
        status:SetText("|cff9a9a9a" .. L["Not in a dungeon: the fair share only counts in dungeons."] .. "|r")
        list:SetData({ { kind = "info", text = L["No fair share yet. It starts when you enter a dungeon in a group."], h = 40 } })
        return
    end

    for key, b in pairs(baseButtons) do b:SetActive(s.basis == key) end
    if selected then
        status:SetText(format(L["%s, %s %s to %s"], s.place or "?", ns.DayLabel(s.t), ns.Clock(s.t), ns.Clock(s.ended or s.t)))
    else
        status:SetText(format(L["%s, counting since %s"], s.place or "?", ns.DayLabel(s.t) .. " " .. ns.Clock(s.t)))
    end

    local r = self:Compute(s)
    local rows = {
        { kind = "head", text = L["LOOTED"], right = ns.Players(r.n) .. ", " .. format(L["%s in total"], ns.Money(r.total)), h = 26 },
        { kind = "cols", h = 20 },
    }
    for _, p in ipairs(r.rows) do
        rows[#rows + 1] = { kind = "player", name = p.name, c = p.c, value = p.value, share = p.share,
            after = p.after, inside = p.inside, net = p.net, left = p.left }
    end
    if #r.rows == 0 then rows[#rows + 1] = { kind = "info", text = L["Nothing looted yet."] } end
    rows[#rows + 1] = { kind = "head", text = L["EVENING OUT"], h = 30 }
    for _, t in ipairs(r.transfers) do rows[#rows + 1] = { kind = "transfer", t = t } end
    if #r.transfers == 0 then rows[#rows + 1] = { kind = "info", text = L["Nothing to share: everyone has the same."] } end
    list:SetData(rows, true)
end


local function Build()
    frame = St.Window("NibbelzLootShareFrame", 700, 480, L["Fair share"], "share")
    frame:Place({ "CENTER", UIParent, "CENTER", 60, 0 })
    St.Resizable(frame, 640, 400, 1400, 1000, function() Share:Refresh() end)
    frame:SetScale(ns.db.opts.scale or 1)
    frame:SetFrameStrata("HIGH")
    frame:Hide()
    tinsert(UISpecialFrames, "NibbelzLootShareFrame")

    local logo = frame.bar:CreateTexture(nil, "OVERLAY")
    logo:SetSize(16, 16)
    logo:SetPoint("LEFT", 10, 0)
    logo:SetTexture("Interface\\Icons\\INV_Misc_Coin_02")
    logo:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    frame.title:ClearAllPoints()
    frame.title:SetPoint("LEFT", logo, "RIGHT", 6, 0)

    -- Left: running share and history.
    local left = CreateFrame("Frame", nil, frame)
    left:SetPoint("TOPLEFT", 8, -36)
    left:SetPoint("BOTTOMLEFT", 8, 8)
    left:SetWidth(200)
    local lbg = St.Fill(left, St.INSET)
    lbg:SetAllPoints()
    St.Border(left, 0.06)
    local lt = St.Section(left, L["HISTORY"])
    lt:SetPoint("TOPLEFT", 10, -8)
    histList = St.List(left, 36, HistMake, HistFill)
    histList:SetPoint("TOPLEFT", 2, -24)
    histList:SetPoint("BOTTOMRIGHT", -2, 34)
    local clear = St.Button(left, L["Delete history"], 184, 24, function()
        local n = #History()
        if n == 0 then
            ns.Print(L["The fair share history is empty: a run moves there when you leave the dungeon or the group."])
            return
        end
        St.Confirm(format(L["Delete the whole fair share history (%d runs)? This cannot be undone."], n), function()
            wipe(History())
            selected = nil
            ns.Print(L["Fair share history deleted."])
            Share:Refresh()
        end)
    end)
    clear.danger = true
    clear:Paint()
    clear:SetPoint("BOTTOM", 0, 6)

    -- Right: the selected share.
    local x = 8 + 200 + 10
    status = St.Text(frame, 11)
    status:SetPoint("TOPLEFT", x, -38)
    status:SetPoint("RIGHT", frame, "RIGHT", -12, 0)
    status:SetTextColor(1, 1, 1, 0.8)
    local note = St.Text(frame, 10)
    note:SetPoint("TOPLEFT", status, "BOTTOMLEFT", 0, -4)
    note:SetPoint("RIGHT", frame, "RIGHT", -12, 0)
    note:SetWordWrap(true)
    note:SetText(L["Each item is shared among the players in the group when it dropped: whoever leaves early only shares until then."])
    note:SetTextColor(1, 1, 1, 0.5)

    baseButtons = {}
    local prev
    for _, b in ipairs(BASES) do
        local key = b.key
        local btn = St.Button(frame, b.label, 150, 22, function()
            local s = Shown()
            if s then s.basis = key end
            Share:Refresh()
        end)
        if prev then btn:SetPoint("LEFT", prev, "RIGHT", 4, 0) else btn:SetPoint("TOPLEFT", x, -84) end
        baseButtons[key] = btn
        prev = btn
    end

    local inset = CreateFrame("Frame", nil, frame)
    inset:SetPoint("TOPLEFT", x - 4, -114)
    inset:SetPoint("BOTTOMRIGHT", -8, 42)
    local bg = St.Fill(inset, St.INSET)
    bg:SetAllPoints()
    St.Border(inset, 0.06)
    list = St.List(inset, 22, Make, Fill)
    list:SetPoint("TOPLEFT", 2, -2)
    list:SetPoint("BOTTOMRIGHT", -2, 2)

    resetBtn = St.Button(frame, L["Start over"], 130, 24, function()
        St.Confirm(L["Start the running fair share over? What was counted so far is lost."], function()
            DeleteRun(nil)
        end)
    end)
    resetBtn:SetPoint("BOTTOMLEFT", x - 4, 10)
    deleteBtn = St.Button(frame, L["Delete marked run"], 150, 24, function()
        if selected then DeleteRun(selected) end
    end)
    deleteBtn.danger = true
    deleteBtn:Paint()
    deleteBtn:SetPoint("BOTTOMLEFT", x - 4, 10)
    postBtn = St.Button(frame, L["Post in group chat"], 170, 24, function() Share:Post() end)
    postBtn:SetPoint("BOTTOMRIGHT", -8, 10)
    local preview = St.Button(frame, L["Preview"], 100, 24, function() Share:AddPreview() end)
    preview:SetPoint("RIGHT", postBtn, "LEFT", -6, 0)

    frame:SetScript("OnShow", function() Share:Refresh() end)
end

function Share:Toggle()
    if not frame then return end
    frame:SetShown(not frame:IsShown())
    if frame:IsShown() then frame:Raise() end
end

function Share:ApplyScale()
    if frame then frame:SetScale(ns.db.opts.scale or 1) end
end

-------------------------------------------------------------------------------
--  Events: leaving the dungeon or the group closes the running share
-------------------------------------------------------------------------------
local function OnZone()
    local s = Active()
    local ctx = ns.ctx
    if ctx.inst then selected = nil end   -- in a dungeon: show the running share
    if not s then
        NewShare()
    elseif #s.events > 0 and not (s.key and s.key:sub(1, 2) == "i:") then
        -- Counted outside a dungeon (older version): drop it, don't keep it.
        Share:Reset()
        return
    elseif #s.events == 0 then
        -- Nothing looted yet: just follow the player.
        s.place, s.key = ctx.place, ctx.key
        SyncRoster(s)
    elseif ctx.key ~= s.key and (ctx.inst or (s.key and s.key:sub(1, 2) == "i:")) then
        -- Into a dungeon, out of one, or into another one.
        Share:Archive()
        return
    else
        SyncRoster(s)
    end
    Share:Refresh()
end

function Share:Init()
    Upgrade(ns.db.share)
    local h = History()
    for i = #h, 1, -1 do
        Upgrade(h[i])
        -- Runs counted outside dungeons (older versions) don't belong here.
        local key = h[i].key
        if not h[i].preview and not (type(key) == "string" and key:sub(1, 2) == "i:") then tremove(h, i) end
    end
    Build()
    if not Active() then NewShare() end
    ns.OnGroupLoot(OnLoot)
    local ev = CreateFrame("Frame")
    ev:RegisterEvent("PLAYER_ENTERING_WORLD")
    ev:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    ev:RegisterEvent("GROUP_ROSTER_UPDATE")
    ev:RegisterEvent("GROUP_LEFT")
    ev:SetScript("OnEvent", function(_, event)
        if event == "GROUP_LEFT" then
            Share:Archive()
        elseif event == "GROUP_ROSTER_UPDATE" then
            ns.Debounce("shareRoster", 1, function()
                local s = Active()
                if s then SyncRoster(s); Share:Refresh() end
            end)
        else
            C_Timer.After(0.5, OnZone)   -- after Core has updated the place
        end
    end)
end
