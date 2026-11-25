-- Battle.lua: the loot battle.
--
-- 1. Someone types /rolls battle and sets it up: the mode, the gold stake and the
--    categories, then starts it.
--      Contest:   players compete; whoever wins a category takes that part of the pot.
--      Tip game:  players also tip who wins each category; the best tipper takes the pot.
-- 2. Everyone decides whether to play: players with Nibbelz Loot get a window with
--    buttons, players without it type !join in group chat (and !tip <category> <name>).
-- 3. Joining (and tipping) is open until the first boss dies.
-- 4. When the dungeon's last boss dies (Bosses.lua) the battle is scored: winners
--    per category, and with a stake, who hands whom how much gold.
--
-- The addon never moves gold: it only shows who owes whom. Clients with the addon
-- share the battle through hidden addon messages and score it from the same loot.
local _, ns = ...
local St, L = ns.St, ns.L

local format, max, min, floor = string.format, math.max, math.min, math.floor
local sort, tinsert, concat = table.sort, table.insert, table.concat

local Battle = {}
ns.Battle = Battle

local PREFIX = "NibbelzLoot"
local KEEP_RESULTS = 30
local CHAT_TAG = "[Nibbelz Loot] "
local GOLD = 10000

-- Categories, in display order. alias = what players type after !tip.
local CATS = {
    { key = "total", label = L["Overall winner"],    kind = "points", alias = { "total", "gesamt", "overall" } },
    { key = "gold",  label = L["Most vendor value"], kind = "money",  alias = { "gold", "vendor", "haendler", "händler" } },
    { key = "ah",    label = L["Most AH value"],     kind = "money",  alias = { "ah", "auktion" } },
    { key = "wins",  label = L["Most rolls won"],    kind = "num",    alias = { "wins", "wuerfe", "würfe", "rolls" } },
    { key = "epic",  label = L["Most epic items"],   kind = "num",    alias = { "epic", "lila", "episch" } },
    { key = "blue",  label = L["Most blue items"],   kind = "num",    alias = { "blue", "blau", "rare" } },
    { key = "green", label = L["Most green items"],  kind = "num",    alias = { "green", "gruen", "grün" } },
    { key = "grey",  label = L["Most grey items"],   kind = "num",    alias = { "grey", "gray", "grau" } },
    { key = "roll",  label = L["Highest roll"],      kind = "num",    alias = { "roll", "wurf", "highroll" } },
    -- Extra bets. Damage, healing and the like come from the game's own damage
    -- meter (C_DamageMeter, read between fights); killing blows from PARTY_KILL.
    { key = "dmg",     extra = true, label = L["Most damage"],                kind = "big", meter = "DamageDone",           alias = { "dmg", "schaden", "damage" } },
    { key = "bossdmg", extra = true, label = L["Most boss damage"],           kind = "big",                                 alias = { "boss", "bossdmg", "bossschaden" } },
    { key = "heal",    extra = true, label = L["Most healing"],               kind = "big", meter = "HealingDone",          alias = { "heal", "heilung" } },
    { key = "kills",   extra = true, label = L["Most killing blows"],         kind = "num",                                 alias = { "kills", "lasthits", "lasthit" } },
    { key = "taken",   extra = true, label = L["Punching bag (damage taken)"], kind = "big", meter = "DamageTaken",         alias = { "taken", "tank", "pruegel" } },
    { key = "avoid",   extra = true, label = L["Stands in the fire"],         kind = "big", meter = "AvoidableDamageTaken", alias = { "feuer", "fire", "avoid" } },
    { key = "kicks",   extra = true, label = L["Most interrupts"],            kind = "num", meter = "Interrupts",           alias = { "kicks", "kick", "interrupt" } },
    { key = "dispels", extra = true, label = L["Most dispels"],               kind = "num", meter = "Dispels",              alias = { "dispel", "dispels" } },
    { key = "deaths",  extra = true, label = L["Floor inspector (deaths)"],   kind = "num", meter = "Deaths",               alias = { "tode", "deaths", "boden" } },
    { key = "needs",   extra = true, label = L["Greedy guts (most Need)"],    kind = "num",                                 alias = { "bedarf", "need" } },
    { key = "passes",  extra = true, label = L["Most modest (most passes)"],  kind = "num",                                 alias = { "pass", "passen" } },
    { key = "lowroll", extra = true, label = L["Unlucky (lowest roll)"],      kind = "num", low = true,                     alias = { "pech", "low", "lowroll" } },
}
local SCORE_KEYS = {}
for _, c in ipairs(CATS) do if c.key ~= "total" then SCORE_KEYS[#SCORE_KEYS + 1] = c.key end end
local CAT_BY_KEY, CAT_BY_ALIAS = {}, {}
for _, c in ipairs(CATS) do
    CAT_BY_KEY[c.key] = c
    for _, a in ipairs(c.alias) do CAT_BY_ALIAS[a] = c end
end
local POINTS = { 3, 2, 1 }   -- 1st, 2nd, 3rd place in a category, for the overall winner

local MODES = {
    race = { label = L["Contest"], note = L["Players compete. Whoever wins a category takes that part of the pot."] },
    tips = { label = L["Tip game"], note = L["Everyone tips who wins each category. The best tipper takes the pot."] },
}

local Plain = ns.Plain
local Short = ns.Name   -- every name as "Name Surname"
local function Me() return ns.MyName() end

-------------------------------------------------------------------------------
--  State: ns.db.battle is the current (or last) battle, ns.db.battles the past ones
-------------------------------------------------------------------------------
local function Current()
    return ns.db and ns.db.battle
end

function Battle:Active()
    local b = Current()
    return b and not b.done and b or nil
end

local function AddPlayer(b, name, class)
    if not name or name == "" then return end
    local p = b.players[name]
    if not p then
        p = {}
        b.players[name] = p
    end
    if class then p.c = class end
end

-- One key per player: names first seen without the surname move to the full name.
local function Canon(t, merge)
    if type(t) ~= "table" then return t end
    local out = {}
    for name, v in pairs(t) do
        local full = Short(name) or name
        if out[full] == nil then
            out[full] = v
        elseif merge then
            merge(out[full], v)
        end
    end
    return out
end

local function MergeLoot(into, from)
    for k, v in pairs(from) do into[k] = (into[k] or 0) + v end
end

local function CanonBattle(b)
    b.players = Canon(b.players, function(into, from) into.c = into.c or from.c end)
    b.joined = Canon(b.joined)
    b.loot = Canon(b.loot, MergeLoot)
    b.tips = Canon(b.tips)
    for _, tips in pairs(b.tips) do
        for key, name in pairs(tips) do tips[key] = Short(name) or name end
    end
end

local function AddRoster(b)
    for _, unit in ipairs(ns.GroupUnits()) do
        if UnitExists(unit) then
            local name = ns.UnitFullName(unit)
            local _, class = UnitClass(unit)
            if name then AddPlayer(b, name, Plain(class, "string")) end
        end
    end
    CanonBattle(b)
end

-- A player in the battle by what someone typed: full name or just the first name.
local function FindPlayer(b, typed)
    if not typed then return nil end
    typed = typed:lower()
    for name in pairs(b.players) do
        local lower = name:lower()
        if lower == typed or lower:match("^(%S+)") == typed then return name end
    end
end

local function CatList(cats)
    local keys = {}
    for _, c in ipairs(CATS) do if cats[c.key] then keys[#keys + 1] = c.key end end
    return concat(keys, ",")
end

local function NewBattle(id, started, host, cats, mode, stake)
    local ctx = ns.ctx
    local b = {
        id = id or (tostring(time()) .. "-" .. (Me() or "?")),
        t = started or time(),
        host = host or Me(),
        place = ctx.place, key = ctx.key, instanceID = ctx.instanceID,
        cats = cats, mode = MODES[mode] and mode or "race", stake = stake or 0,
        players = {}, joined = {}, loot = {}, tips = {},
    }
    AddRoster(b)
    ns.db.battle = b
    return b
end

local function JoinedCount(b)
    local n = 0
    for _ in pairs(b.joined) do n = n + 1 end
    return n
end

-------------------------------------------------------------------------------
--  Group sync: hidden addon messages, and chat commands for players without it
-------------------------------------------------------------------------------
local function Send(msg)
    local channel = ns.GroupChannel()
    if not (channel and C_ChatInfo and C_ChatInfo.SendAddonMessage) then return end
    pcall(C_ChatInfo.SendAddonMessage, PREFIX, msg, channel)
end

local function Say(text)
    local channel = ns.GroupChannel()
    if channel then pcall(SendChatMessage, CHAT_TAG .. text, channel) end
end

local function TipString(tips)
    local parts = {}
    for key, name in pairs(tips or {}) do
        if CAT_BY_KEY[key] then parts[#parts + 1] = key .. "=" .. name end
    end
    return concat(parts, ";")
end

local function SendState()
    local b = Battle:Active()
    if not b then return end
    if b.joined[Me()] then Send("J\t" .. b.id) end
    local tips = b.tips[Me()]
    if tips and next(tips) then Send("T\t" .. b.id .. "\t" .. TipString(tips)) end
end

local function SetJoined(b, name, on)
    b.joined[name] = on or nil
    if not on then b.tips[name] = nil end
end

local function SetTip(b, tipper, key, name)
    b.tips[tipper] = b.tips[tipper] or {}
    b.tips[tipper][key] = name
end

function Battle:Join(on)
    local b = self:Active()
    if not b or b.locked then return end
    SetJoined(b, Me(), on)
    Send((on and "J\t" or "L\t") .. b.id)
    self:Refresh()
end

local function OnAddonMessage(prefix, text, _, sender)
    if prefix ~= PREFIX then return end
    text, sender = Plain(text, "string"), Short(Plain(sender, "string"))
    if not (text and sender) or sender == Me() then return end
    local kind, id, rest = text:match("^(%a)\t([^\t]+)\t?(.*)$")
    if not kind then return end
    local b = Current()

    if kind == "S" then
        -- An invitation: "S id start cats mode stake".
        local started, cats, mode, stake = rest:match("^(%d+)\t([^\t]*)\t(%a+)\t(%d+)$")
        if b and not b.done and b.id == id then return end
        local catSet = {}
        for key in (cats or ""):gmatch("[^,]+") do if CAT_BY_KEY[key] then catSet[key] = true end end
        if not next(catSet) then return end
        b = NewBattle(id, tonumber(started), sender, catSet, mode, tonumber(stake))
        AddPlayer(b, sender)
        SetJoined(b, sender, true)
        Battle:ReadMeters(b)
        Battle:Tick()
        Battle:ShowInvite(sender)
        Send("Q\t" .. id)
    elseif not (b and not b.done and b.id == id) then
        return
    elseif kind == "J" then
        AddPlayer(b, sender)
        if not b.locked then SetJoined(b, sender, true) end
    elseif kind == "L" then
        if not b.locked then SetJoined(b, sender, false) end
    elseif kind == "T" then
        local tips = {}
        for key, name in rest:gmatch("(%a+)=([^;]+)") do
            if b.cats[key] then tips[key] = name end
        end
        if b.joined[sender] and not b.locked then b.tips[sender] = tips end
    elseif kind == "Q" then
        SendState()
    elseif kind == "E" then
        Battle:Finish("manual")
        return
    end
    Battle:Refresh()
end

-- !join, !leave, !tip <category> <name> in group chat (with or without the addon).
local function OnGroupChat(text, sender)
    text, sender = Plain(text, "string"), Short(Plain(sender, "string"))
    local b = Battle:Active()
    if not (text and sender and b) or text:sub(1, 1) ~= "!" then return end
    local cmd, rest = text:lower():match("^!(%S+)%s*(.-)%s*$")
    if cmd == "join" or cmd == "mitmachen" or cmd == "dabei" then
        if not b.locked then
            AddPlayer(b, sender)
            SetJoined(b, sender, true)
        end
    elseif cmd == "leave" or cmd == "raus" then
        if not b.locked then SetJoined(b, sender, false) end
    elseif (cmd == "tip" or cmd == "tipp") and b.mode == "tips" then
        local catWord, who = rest:match("^(%S+)%s+(.-)%s*$")
        local cat = catWord and CAT_BY_ALIAS[catWord]
        local name = FindPlayer(b, who)
        if cat and name and b.cats[cat.key] and b.joined[sender] and not b.locked then
            SetTip(b, sender, cat.key, name)
        end
    else
        return
    end
    Battle:Refresh()
end

-- Loot from Loot.lua: counted for everyone in the group; only players who joined score.
local function OnLoot(name, info)
    local b = Battle:Active()
    if not b then return end
    AddPlayer(b, name)
    local l = b.loot[name]
    if not l then
        l = { gold = 0, ah = 0, grey = 0, green = 0, blue = 0, epic = 0, items = 0 }
        b.loot[name] = l
    end
    l.items = l.items + info.count
    l.gold = l.gold + info.sell
    l.ah = l.ah + info.ah
    local q = info.quality
    local key = q and ((q >= 4 and "epic") or (q == 3 and "blue") or (q == 2 and "green") or (q == 0 and "grey"))
    if key then l[key] = l[key] + info.count end
    Battle:Refresh()
end

-------------------------------------------------------------------------------
--  The game's damage meter (C_DamageMeter). Its numbers are hidden from addons
--  during combat, so it is read between fights. The "Overall" session can reset
--  (new dungeon, by hand): what was counted before a reset is kept.
--  b.meter[key] = { base = {}, last = {}, acc = {} }; value = acc + last - base
-------------------------------------------------------------------------------
local function MeterReadable()
    if not (C_DamageMeter and C_DamageMeter.GetCombatSessionFromType and Enum.DamageMeterType
        and Enum.DamageMeterSessionType) then return false end
    if InCombatLockdown() then return false end
    if C_RestrictedActions and C_RestrictedActions.IsAddOnRestrictionActive and Enum.AddOnRestrictionType then
        local ok, on = pcall(C_RestrictedActions.IsAddOnRestrictionActive, Enum.AddOnRestrictionType.Combat)
        if ok and on then return false end
    end
    return true
end

-- { [name] = amount } of one meter type in a session.
local function ReadSession(session, typeName, sessionID)
    local t = Enum.DamageMeterType[typeName]
    if not t then return nil end
    local ok, s
    if sessionID then
        ok, s = pcall(C_DamageMeter.GetCombatSessionFromID, sessionID, t)
    else
        ok, s = pcall(C_DamageMeter.GetCombatSessionFromType, session, t)
    end
    if not ok or type(s) ~= "table" or type(s.combatSources) ~= "table" then return nil end
    local out = {}
    for _, src in ipairs(s.combatSources) do
        local name = Short(Plain(src.name, "string"))
        if name then
            local v = Plain(src.totalAmount, "number")
            if typeName == "Deaths" and not (v and v > 0) then v = 1 end
            if v then out[name] = (out[name] or 0) + v end
        end
    end
    return out
end

local function UpdateMeters(b)
    if not MeterReadable() then return end
    b.meter = b.meter or {}
    for _, cat in ipairs(CATS) do
        if cat.meter and b.cats[cat.key] then
            local cur = ReadSession(Enum.DamageMeterSessionType.Overall, cat.meter)
            if cur then
                local m = b.meter[cat.key]
                if not m then
                    -- First reading: what was there before the battle does not count.
                    m = { base = {}, last = {}, acc = {} }
                    for name, v in pairs(cur) do m.base[name], m.last[name] = v, v end
                    b.meter[cat.key] = m
                else
                    for name, last in pairs(m.last) do
                        local v = cur[name] or 0
                        if v < last then   -- the meter was reset: keep what was counted
                            m.acc[name] = (m.acc[name] or 0) + last - (m.base[name] or 0)
                            m.base[name] = 0
                        end
                    end
                    for name, v in pairs(cur) do
                        if m.base[name] == nil then m.base[name] = 0 end
                        m.last[name] = v
                    end
                    for name in pairs(m.last) do
                        if cur[name] == nil then m.last[name] = 0 end
                    end
                end
            end
        end
    end
    -- Boss damage: the newest session after a boss died is that fight.
    if b.cats.bossdmg and b.bossPending and C_DamageMeter.GetAvailableCombatSessions then
        local ok, sessions = pcall(C_DamageMeter.GetAvailableCombatSessions)
        if ok and type(sessions) == "table" and #sessions > 0 then
            local newest
            for _, s in ipairs(sessions) do
                local id = Plain(s.sessionID, "number")
                if id and (not newest or id > newest) then newest = id end
            end
            b.bossSessions = b.bossSessions or {}
            if newest and not b.bossSessions[newest] then
                local dmg = ReadSession(nil, "DamageDone", newest)
                if dmg then
                    b.bossSessions[newest] = true
                    b.bossDmg = b.bossDmg or {}
                    for name, v in pairs(dmg) do b.bossDmg[name] = (b.bossDmg[name] or 0) + v end
                    b.bossPending = nil
                end
            elseif newest then
                b.bossPending = nil
            end
        end
    end
end

function Battle:ReadMeters(b)
    UpdateMeters(b)
end

local function MeterValue(b, key, name)
    local m = b.meter and b.meter[key]
    if not m then return 0 end
    return max(0, (m.acc[name] or 0) + (m.last[name] or 0) - (m.base[name] or 0))
end

-- Killing blows: PARTY_KILL names the group member who landed it.
local function OnPartyKill(attackerGUID)
    local b = Battle:Active()
    attackerGUID = Plain(attackerGUID, "string")
    if not (b and attackerGUID and b.cats.kills) then return end
    for _, unit in ipairs(ns.GroupUnits()) do
        local guid = Plain(UnitGUID(unit), "string")
        if guid == attackerGUID then
            local name = ns.UnitFullName(unit)
            if name then
                b.kills = b.kills or {}
                b.kills[name] = (b.kills[name] or 0) + 1
            end
            return
        end
    end
end

-------------------------------------------------------------------------------
--  Scoring
-------------------------------------------------------------------------------
local function Scores(b)
    local s = {}
    local function P(name)
        if not b.joined[name] then return nil end
        local p = s[name]
        if not p then
            local info = b.players[name]
            p = { name = name, c = info and info.c, items = 0, points = 0 }
            for _, key in ipairs(SCORE_KEYS) do p[key] = 0 end
            s[name] = p
        end
        return p
    end
    for name in pairs(b.joined) do
        local p = P(name)
        for _, cat in ipairs(CATS) do
            if cat.meter then p[cat.key] = MeterValue(b, cat.key, name) end
        end
        p.bossdmg = b.bossDmg and b.bossDmg[name] or 0
        p.kills = b.kills and b.kills[name] or 0
    end
    for name in pairs(b.joined) do P(name) end
    for name, l in pairs(b.loot) do
        local p = P(name)
        if p then for k, v in pairs(l) do p[k] = (p[k] or 0) + v end end
    end
    local rolls = ns.db.rolls
    local stop = b.done or math.huge
    for i = #rolls, 1, -1 do
        local rec = rolls[i]
        if rec.t < b.t then break end
        if rec.t <= stop and not rec.demo then
            local w = rec.win and P(rec.win)
            if w then
                w.wins = w.wins + 1
                if rec.wc and not w.c then w.c = rec.wc end
            end
            for _, e in ipairs(rec.rolls or {}) do
                local p = P(e.n)
                if p then
                    if e.c and not p.c then p.c = e.c end
                    if e.r then
                        if e.r > p.roll then p.roll = e.r end
                        if p.lowroll == 0 or e.r < p.lowroll then p.lowroll = e.r end
                    end
                    if e.s == ns.S.NEED or e.s == ns.S.OFF then p.needs = p.needs + 1
                    elseif e.s == ns.S.PASS then p.passes = p.passes + 1 end
                end
            end
        end
    end
    return s
end

-- low = the smallest value wins (zero = nothing counted, always last).
local function Ranking(scores, key, low)
    local list = {}
    for _, p in pairs(scores) do list[#list + 1] = p end
    sort(list, function(a, b)
        local va, vb = a[key], b[key]
        if va ~= vb then
            if low then
                if va == 0 then return false end
                if vb == 0 then return true end
                return va < vb
            end
            return va > vb
        end
        return a.name < b.name
    end)
    local rank, last = 0, nil
    for i, p in ipairs(list) do
        if p[key] ~= last then rank, last = i, p[key] end
        p.rank = rank
    end
    return list
end

local function Snapshot(list, key)
    local out = {}
    for i, p in ipairs(list) do out[i] = { name = p.name, c = p.c, value = p[key], rank = p.rank } end
    return out
end

-- Who gets how much of the pot, and who hands whom how much.
local function Payout(b, result, scores)
    local players = {}
    for name in pairs(b.joined) do players[#players + 1] = name end
    local n = #players
    local stake = b.stake or 0
    if stake <= 0 or n < 2 then return nil end
    local pot = stake * n
    local won = {}
    for _, name in ipairs(players) do won[name] = 0 end

    local function Give(amount, winners)
        local list = {}
        for name in pairs(winners) do if won[name] then list[#list + 1] = name end end
        if #list == 0 then list = players end   -- nobody won it: everyone gets their part back
        local each = floor(amount / #list)
        for _, name in ipairs(list) do won[name] = won[name] + each end
    end

    if b.mode == "tips" then
        local best, winners = 0, {}
        for _, t in ipairs(result.tippers) do
            if t.right > best then best, winners = t.right, { [t.name] = true }
            elseif t.right == best and best > 0 then winners[t.name] = true end
        end
        Give(pot, best > 0 and winners or {})
    else
        local cats = {}
        for _, c in ipairs(CATS) do if b.cats[c.key] and result[c.key] then cats[#cats + 1] = c.key end end
        local part = floor(pot / max(1, #cats))
        for _, key in ipairs(cats) do Give(part, result[key].winners) end
    end

    local entries, rows = {}, {}
    for _, name in ipairs(players) do
        local p = scores[name] or b.players[name] or {}
        local e = { name = name, c = p.c, net = won[name] - stake, won = won[name] }
        entries[#entries + 1] = e
        rows[#rows + 1] = e
    end
    sort(rows, function(a, c)
        if a.net ~= c.net then return a.net > c.net end
        return a.name < c.name
    end)
    return { pot = pot, stake = stake, rows = rows, transfers = ns.Settle(entries) }
end

function Battle:Evaluate(b)
    local scores = Scores(b)
    local result = {}
    for _, cat in ipairs(CATS) do
        if cat.key ~= "total" and b.cats[cat.key] then
            local list = Ranking(scores, cat.key, cat.low)
            local winners = {}
            for _, p in ipairs(list) do
                if p[cat.key] > 0 then
                    if p.rank == 1 then winners[p.name] = true end
                    local pts = POINTS[p.rank]
                    if pts then p.points = p.points + pts end
                end
            end
            result[cat.key] = { list = Snapshot(list, cat.key), winners = winners }
        end
    end
    if b.cats.total then
        local list = Ranking(scores, "points")
        local winners = {}
        for _, p in ipairs(list) do if p.points > 0 and p.rank == 1 then winners[p.name] = true end end
        result.total = { list = Snapshot(list, "points"), winners = winners }
    end

    local tippers = {}
    if b.mode == "tips" then
        for tipper, tips in pairs(b.tips) do
            local right, count = 0, 0
            for key, name in pairs(tips) do
                if result[key] then
                    count = count + 1
                    if result[key].winners[name] then right = right + 1 end
                end
            end
            if count > 0 then tippers[#tippers + 1] = { name = tipper, right = right, count = count } end
        end
        sort(tippers, function(a, c)
            if a.right ~= c.right then return a.right > c.right end
            return a.name < c.name
        end)
    end
    result.tippers = tippers
    result.payout = Payout(b, result, scores)
    return result
end

-- 1234567 -> 1.23M, 45600 -> 45.6K
local function Big(v)
    v = v or 0
    if v >= 1e6 then return format("%.2fM", v / 1e6) end
    if v >= 1e4 then return format("%.1fK", v / 1e3) end
    return tostring(floor(v + 0.5))
end

local function FormatValue(cat, value)
    if cat.kind == "money" then return ns.Money(value) end
    if cat.kind == "points" then return format(L["%d pts"], value) end
    if cat.kind == "big" then return Big(value) end
    return tostring(value)
end

-------------------------------------------------------------------------------
--  Start / finish
-------------------------------------------------------------------------------
function Battle:Start(cats, mode, stake, invite)
    if not next(cats) then return end
    local b = NewBattle(nil, nil, Me(), cats, mode, stake)
    SetJoined(b, Me(), true)
    Send("S\t" .. b.id .. "\t" .. b.t .. "\t" .. CatList(cats) .. "\t" .. b.mode .. "\t" .. b.stake)
    if invite and ns.GroupChannel() then
        local labels = {}
        for _, c in ipairs(CATS) do if cats[c.key] then labels[#labels + 1] = c.alias[1] end end
        local stakeText = b.stake > 0 and format(L["Stake: %s per player. "], ns.ChatMoney(b.stake)) or ""
        if b.mode == "tips" then
            Say(format(L["Loot battle (tip game)! %sType !join to play, then !tip <category> <name> before the first boss dies."], stakeText))
        else
            Say(format(L["Loot battle (contest)! %sType !join to play before the first boss dies."], stakeText))
        end
        Say(L["Categories: "] .. concat(labels, ", "))
    end
    ns.Print(L["Loot battle started. Joining is open until the first boss dies."])
    UpdateMeters(b)   -- what the damage meter shows now does not count
    self:Tick()
    self:Refresh()
end

local function ResultLines(b, result)
    local lines = { format(L["Loot battle %s:"], b.place or "") }
    for _, cat in ipairs(CATS) do
        local entry = result[cat.key]
        if entry then
            local names = {}
            for _, p in ipairs(entry.list) do
                if entry.winners[p.name] then names[#names + 1] = p.name end
            end
            if #names > 0 then
                local top = entry.list[1]
                local value = cat.kind == "money" and ns.ChatMoney(top.value) or FormatValue(cat, top.value)
                lines[#lines + 1] = format("%s: %s (%s)", cat.label, concat(names, ", "), value)
            end
        end
    end
    if result.tippers[1] then
        local t = result.tippers[1]
        lines[#lines + 1] = format(L["Best tipper: %s (%d/%d)"], t.name, t.right, t.count)
    end
    local pay = result.payout
    if pay and #pay.transfers > 0 then
        local parts = {}
        for _, tr in ipairs(pay.transfers) do
            parts[#parts + 1] = format("%s -> %s %s", tr.from, tr.to, ns.ChatMoney(tr.amount))
        end
        lines[#lines + 1] = format(L["Pot %s: "], ns.ChatMoney(pay.pot)) .. concat(parts, ", ")
    end
    return lines
end

function Battle:Finish(reason)
    local b = self:Active()
    if not b then return end
    UpdateMeters(b)   -- last reading of the damage meter before the battle closes
    b.done = time()
    b.reason = reason
    local result = self:Evaluate(b)
    b.result = result
    ns.db.battles = ns.db.battles or {}
    tinsert(ns.db.battles, 1, b)
    while #ns.db.battles > KEEP_RESULTS do table.remove(ns.db.battles) end
    if reason == "manual" and b.host == Me() then Send("E\t" .. b.id) end

    local lines = ResultLines(b, result)
    ns.Print("|cffffd100" .. lines[1] .. "|r")
    for i = 2, #lines do print("  " .. lines[i]) end
    if ns.db.opts.battleAnnounce and b.host == Me() and ns.GroupChannel() then
        C_Timer.After(2, function()
            for _, line in ipairs(lines) do Say(line) end
        end)
    end
    if PlaySound and SOUNDKIT and SOUNDKIT.UI_EPICLOOT_TOAST then pcall(PlaySound, SOUNDKIT.UI_EPICLOOT_TOAST) end
    self.view = nil
    self.bottom = (result.payout and "pay") or nil
    self:Open()
end

local function Lock()
    local b = Battle:Active()
    if b and not b.locked then
        b.locked = time()
        Battle:Refresh()
    end
end

local function OnEncounterEnd(encounterID, name, success)
    if success ~= 1 and success ~= true then return end
    local b = Battle:Active()
    if not b then return end
    b.bossPending = true   -- read this fight's damage once combat is over
    local final = ns.FinalBoss(Plain(encounterID, "number"), Plain(name, "string"))
    if final and b.finalAt then return end   -- ENCOUNTER_END and BOSS_KILL both report it
    if final then
        C_Timer.After(1, Lock)
        b.boss = Plain(name, "string") or final.boss
        b.finalAt = time()
        ns.Print(format(L["%s is dead - the loot battle ends once the last rolls are done."], b.boss))
        Battle:Refresh()
    else
        Lock()
    end
end

-- After the last boss: wait until its rolls are settled (at most 2 minutes), then score.
local function CheckFinal()
    local b = Battle:Active()
    if not (b and b.finalAt) or time() - b.finalAt < 3 then return end
    local open = false
    for _, e in ipairs(ns.live) do
        if not e.rec.done and not e.rec.test then open = true end
    end
    -- Boss damage is read once combat is over: give it up to half a minute.
    if b.cats.bossdmg and b.bossPending and time() - b.finalAt < 30 then open = true end
    if not open or time() - b.finalAt > 120 then Battle:Finish("boss") end
end

-- A slow clock that only runs while a battle is going: waits for the end after
-- the last boss and keeps the window's minutes current. Stops by itself.
local ticker
local CHAT_EVENTS_LIST = {
    "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER", "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER",
    "CHAT_MSG_INSTANCE_CHAT", "CHAT_MSG_INSTANCE_CHAT_LEADER",
}
local function ListenChat(on)
    local ev = Battle.ev
    if not ev then return end
    for _, e in ipairs(CHAT_EVENTS_LIST) do
        if on then pcall(ev.RegisterEvent, ev, e) else pcall(ev.UnregisterEvent, ev, e) end
    end
end

function Battle:Tick()
    if ticker or not self:Active() then return end
    ListenChat(true)
    ticker = C_Timer.NewTicker(3, function()
        local b = Battle:Active()
        if not b then
            ticker:Cancel()
            ticker = nil
            ListenChat(false)
            return
        end
        if b.bossPending or b.finalAt then UpdateMeters(b) end
        CheckFinal()
        Battle:Refresh()   -- returns at once while the window is closed
    end)
end

-------------------------------------------------------------------------------
--  Tip menu
-------------------------------------------------------------------------------
local menu, blocker

local function CloseMenu()
    if menu then menu:Hide() end
    if blocker then blocker:Hide() end
end

local function OpenMenu(anchor, catKey)
    local b = Battle:Active()
    if not b or b.locked or not b.joined[Me()] then return end
    if not menu then
        blocker = CreateFrame("Button", nil, UIParent)
        blocker:SetAllPoints(UIParent)
        blocker:SetFrameStrata("FULLSCREEN")
        blocker:SetScript("OnClick", CloseMenu)
        menu = CreateFrame("Frame", nil, UIParent)
        menu:SetFrameStrata("FULLSCREEN_DIALOG")
        local bg = St.Fill(menu, { St.PANEL[1], St.PANEL[2], St.PANEL[3], 0.98 })
        bg:SetAllPoints()
        St.Border(menu, 0.2)
        menu.buttons = {}
    end
    local names = {}
    for name in pairs(b.joined) do
        local p = b.players[name]
        names[#names + 1] = { name = name, c = p and p.c }
    end
    sort(names, function(a, c) return a.name < c.name end)
    tinsert(names, { name = nil })
    for i, entry in ipairs(names) do
        local btn = menu.buttons[i]
        if not btn then
            btn = CreateFrame("Button", nil, menu)
            btn:SetHeight(20)
            btn.hl = St.Fill(btn, { 1, 1, 1, 0 })
            btn.hl:SetAllPoints()
            btn.text = St.Text(btn, 11)
            btn.text:SetPoint("LEFT", 8, 0)
            btn:SetScript("OnEnter", function(self) self.hl:SetColorTexture(1, 1, 1, 0.08) end)
            btn:SetScript("OnLeave", function(self) self.hl:SetColorTexture(1, 1, 1, 0) end)
            menu.buttons[i] = btn
        end
        btn:ClearAllPoints()
        btn:SetPoint("TOPLEFT", 2, -2 - (i - 1) * 20)
        btn:SetPoint("TOPRIGHT", -2, -2 - (i - 1) * 20)
        btn.text:SetText(entry.name and ns.ClassName(entry.name, entry.c) or ("|cff9a9a9a" .. L["No tip"] .. "|r"))
        btn:SetScript("OnClick", function()
            SetTip(b, Me(), catKey, entry.name)
            CloseMenu()
            SendState()
            Battle:Refresh()
        end)
        btn:Show()
    end
    for i = #names + 1, #menu.buttons do menu.buttons[i]:Hide() end
    menu:SetSize(170, #names * 20 + 4)
    menu:ClearAllPoints()
    menu:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, -2)
    blocker:Show()
    menu:Show()
end

-------------------------------------------------------------------------------
--  Invitation window (players with the addon)
-------------------------------------------------------------------------------
local invite

function Battle:ShowInvite(host)
    local b = self:Active()
    if not b then return end
    if not invite then
        invite = St.Window("NibbelzLootBattleInvite", 360, 190, L["Loot battle"], "battleInvite")
        invite:SetFrameStrata("DIALOG")
        invite.text = St.Text(invite, 12)
        invite.text:SetPoint("TOPLEFT", 14, -40)
        invite.text:SetPoint("RIGHT", invite, "RIGHT", -14, 0)
        invite.text:SetWordWrap(true)
        invite.info = St.Text(invite, 10)
        invite.info:SetPoint("TOPLEFT", invite.text, "BOTTOMLEFT", 0, -8)
        invite.info:SetPoint("RIGHT", invite, "RIGHT", -14, 0)
        invite.info:SetWordWrap(true)
        invite.info:SetTextColor(1, 1, 1, 0.65)
        local yes = St.Button(invite, L["Play"], 160, 26, function()
            Battle:Join(true)
            invite:Hide()
            Battle.view = nil
            Battle:Open()
        end)
        yes:SetActive(true)
        yes:SetPoint("BOTTOMLEFT", 14, 14)
        local no = St.Button(invite, L["Not this time"], 160, 26, function()
            Battle:Join(false)
            invite:Hide()
        end)
        no:SetPoint("BOTTOMRIGHT", -14, 14)
    end
    invite:Place({ "TOP", UIParent, "TOP", 0, -160 })
    local hostInfo = b.players[host]
    invite.text:SetText(format(L["%s starts a loot battle in %s. Do you want to play?"],
        ns.ClassName(host, hostInfo and hostInfo.c), b.place or "?"))
    local labels = {}
    for _, c in ipairs(CATS) do if b.cats[c.key] then labels[#labels + 1] = c.label end end
    local lines = { MODES[b.mode].label .. ": " .. MODES[b.mode].note }
    lines[#lines + 1] = b.stake > 0 and format(L["Stake: %s per player"], ns.Money(b.stake)) or L["No stake"]
    lines[#lines + 1] = concat(labels, ", ")
    invite.info:SetText(concat(lines, "\n"))
    invite:Show()
    if PlaySound and SOUNDKIT and SOUNDKIT.READY_CHECK then pcall(PlaySound, SOUNDKIT.READY_CHECK) end
end

-------------------------------------------------------------------------------
--  Main window: setup, running battle, result
-------------------------------------------------------------------------------
local W = 600
local frame, setup, main
local status, actionBtn, joinBtn, newBtn, catRows, bottomTitle, bottomList, tabPlayers, tabPay, tipHead
local COLS = { cat = 10, lead = 200, value = 360, tip = 450 }
local MAX_ROWS = 10
local setupCats, setupMode, setupStake, setupInvite = {}, "race", 0, true

local function CatTip(row)
    local b = Current()
    if not (b and row.cat) then return end
    local result = b.result or Battle:Evaluate(b)
    local entry = result[row.cat.key]
    if not entry then return end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:AddLine(row.cat.label, 1, 0.82, 0)
    local shown = 0
    for _, p in ipairs(entry.list) do
        if p.value > 0 and shown < 8 then
            shown = shown + 1
            GameTooltip:AddDoubleLine(p.rank .. ". " .. ns.ClassName(p.name, p.c), FormatValue(row.cat, p.value), 1, 1, 1, 1, 1, 1)
        end
    end
    if shown == 0 then GameTooltip:AddLine(L["Nobody yet"], 0.6, 0.6, 0.6) end
    if row.cat.key == "total" then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(L["1st place in a category: 3 points, 2nd: 2, 3rd: 1."], 0.7, 0.7, 0.7, true)
    end
    if b.mode == "tips" then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(format(L["Chat tip: !tip %s <name>"], row.cat.alias[1]), 0.6, 0.6, 0.6)
    end
    GameTooltip:Show()
end

local function BuildSetup(parent)
    local s = CreateFrame("Frame", nil, parent)
    s:SetPoint("TOPLEFT", 0, -30)
    s:SetPoint("BOTTOMRIGHT")
    local intro = St.Text(s, 11)
    intro:SetPoint("TOPLEFT", 12, -8)
    intro:SetPoint("RIGHT", s, "RIGHT", -12, 0)
    intro:SetWordWrap(true)
    intro:SetText(L["Set up the battle. Everyone in the group then decides to play: with the addon by button, without it by typing !join in group chat."])
    intro:SetTextColor(1, 1, 1, 0.75)

    -- Mode
    local y = 46
    local msec = St.Section(s, L["MODE"])
    msec:SetPoint("TOPLEFT", 12, -y)
    s.modeButtons = {}
    local race = St.Button(s, MODES.race.label, 140, 22, function() setupMode = "race"; s:Sync() end)
    race:SetPoint("TOPLEFT", 12, -(y + 16))
    local tips = St.Button(s, MODES.tips.label, 140, 22, function() setupMode = "tips"; s:Sync() end)
    tips:SetPoint("LEFT", race, "RIGHT", 4, 0)
    s.modeButtons.race, s.modeButtons.tips = race, tips
    s.modeNote = St.Text(s, 10)
    s.modeNote:SetPoint("TOPLEFT", 12, -(y + 42))
    s.modeNote:SetPoint("RIGHT", s, "RIGHT", -12, 0)
    s.modeNote:SetWordWrap(true)
    s.modeNote:SetTextColor(1, 1, 1, 0.6)
    y = y + 64

    -- Stake
    local ssec = St.Section(s, L["STAKE"])
    ssec:SetPoint("TOPLEFT", 12, -y)
    local box = CreateFrame("EditBox", nil, s)
    box:SetSize(70, 22)
    box:SetPoint("TOPLEFT", 12, -(y + 16))
    box:SetAutoFocus(false)
    box:SetNumeric(true)
    box:SetMaxLetters(5)
    box:SetFont(St.FontPath(), 12, "")
    box:SetJustifyH("RIGHT")
    box:SetTextInsets(6, 6, 0, 0)
    local bbg = St.Fill(box, { 0, 0, 0, 0.35 })
    bbg:SetAllPoints()
    St.Border(box, 0.3)
    box:SetScript("OnTextChanged", function(self)
        setupStake = (tonumber(self:GetText()) or 0) * GOLD
    end)
    box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    s.stakeBox = box
    local unit = St.Text(s, 11)
    unit:SetPoint("LEFT", box, "RIGHT", 6, 0)
    unit:SetText(L["gold per player (0 = no stake)"])
    unit:SetTextColor(1, 1, 1, 0.7)
    local snote = St.Text(s, 10)
    snote:SetPoint("TOPLEFT", 12, -(y + 44))
    snote:SetPoint("RIGHT", s, "RIGHT", -12, 0)
    snote:SetWordWrap(true)
    snote:SetText(L["The addon never moves gold: at the end it shows who hands whom how much."])
    snote:SetTextColor(1, 1, 1, 0.5)
    y = y + 66

    -- Categories: loot ones, then the extra bets (damage meter, kills, rolls).
    s.checks = {}
    local function Group(title, extra)
        local sec = St.Section(s, title)
        sec:SetPoint("TOPLEFT", 12, -y)
        local i = 0
        for _, cat in ipairs(CATS) do
            if (cat.extra or false) == extra then
                i = i + 1
                local col, rowN = (i - 1) % 2, floor((i - 1) / 2)
                local c = St.Checkbox(s, cat.label, function(on) setupCats[cat.key] = on or nil end)
                c:SetPoint("TOPLEFT", 12 + col * 290, -(y + 18) - rowN * 22)
                c:SetWidth(270)
                c:SetHeight(20)
                s.checks[cat.key] = c
            end
        end
        y = y + 18 + floor((i + 1) / 2) * 22 + 8
    end
    Group(L["CATEGORIES"], false)
    Group(L["EXTRA BETS"], true)
    local meterNote = St.Text(s, 10)
    meterNote:SetPoint("TOPLEFT", 12, -y + 4)
    meterNote:SetPoint("RIGHT", s, "RIGHT", -12, 0)
    meterNote:SetWordWrap(true)
    meterNote:SetText(L["Damage, healing, interrupts and deaths come from the game's damage meter, read between fights."])
    meterNote:SetTextColor(1, 1, 1, 0.45)
    y = y + 22

    s.invite = St.Checkbox(s, L["Post the invitation in group chat (for players without the addon)"], function(on) setupInvite = on end)
    s.invite:SetPoint("TOPLEFT", 12, -y)
    s.invite:SetWidth(560)
    y = y + 34

    local start = St.Button(s, L["Start battle"], 200, 28, function()
        s.stakeBox:ClearFocus()
        if not next(setupCats) then
            ns.Print(L["Pick at least one category."])
            return
        end
        local cats = {}
        for k, v in pairs(setupCats) do cats[k] = v end
        Battle.view = nil
        Battle.bottom = nil
        Battle:Start(cats, setupMode, setupStake, setupInvite)
    end)
    start:SetActive(true)
    start:SetPoint("TOPLEFT", 12, -y)
    s.last = St.Button(s, L["Show last result"], 160, 28, function()
        Battle.view = nil
        Battle:Refresh()
    end)
    s.last:SetPoint("LEFT", start, "RIGHT", 8, 0)
    s.height = y + 28 + 14

    function s:Sync()
        for key, btn in pairs(self.modeButtons) do btn:SetActive(key == setupMode) end
        self.modeNote:SetText(MODES[setupMode].note)
        for key, c in pairs(self.checks) do c:SetChecked(setupCats[key]) end
        if not self.stakeBox:HasFocus() then self.stakeBox:SetText(tostring(floor(setupStake / GOLD))) end
        self.invite:SetChecked(setupInvite)
        self.last:SetShown(Current() ~= nil)
    end
    return s
end

local function BuildRows(parent)
    catRows = {}
    for i, cat in ipairs(CATS) do
        local row = CreateFrame("Frame", nil, parent)
        row:SetHeight(26)
        row:EnableMouse(true)
        row.cat = cat
        row.bg = St.Fill(row, { 1, 1, 1, 0 })
        row.bg:SetAllPoints()
        row.label = St.Text(row, 11)
        row.label:SetPoint("LEFT", COLS.cat, 0)
        row.label:SetWidth(COLS.lead - COLS.cat - 6)
        row.label:SetText(cat.label)
        if cat.key == "total" then row.label:SetTextColor(1, 0.82, 0) end
        row.crown = row:CreateTexture(nil, "OVERLAY")
        row.crown:SetSize(13, 13)
        row.crown:SetPoint("LEFT", COLS.lead, 0)
        row.crown:SetTexture("Interface\\GroupFrame\\UI-Group-LeaderIcon")
        row.lead = St.Text(row, 11)
        row.lead:SetPoint("LEFT", COLS.lead + 16, 0)
        row.lead:SetWidth(COLS.value - COLS.lead - 20)
        row.value = St.Text(row, 11, "RIGHT")
        row.value:SetPoint("RIGHT", row, "LEFT", COLS.tip - 10, 0)
        row.value:SetWidth(COLS.tip - COLS.value)
        row.tip = St.Button(row, L["Pick"], 130, 20, function(self) OpenMenu(self, cat.key) end)
        row.tip:SetPoint("LEFT", COLS.tip, 0)
        row.tipText = St.Text(row, 11)
        row.tipText:SetPoint("LEFT", COLS.tip + 6, 0)
        row.tipText:SetWidth(130)
        row:SetScript("OnEnter", CatTip)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        catRows[i] = row
    end
end

local function ListMake(l)
    local row = CreateFrame("Frame", nil, l)
    row.name = St.Text(row, 11)
    row.name:SetPoint("LEFT", 10, 0)
    row.name:SetWidth(260)
    row.text = St.Text(row, 10, "RIGHT")
    row.text:SetPoint("LEFT", 275, 0)
    row.text:SetPoint("RIGHT", -10, 0)
    return row
end

local function ListFill(row, item)
    row.name:SetText(item.label)
    row.text:SetText(item.text)
end

local function BuildMain(parent)
    local m = CreateFrame("Frame", nil, parent)
    m:SetPoint("TOPLEFT", 0, -30)
    m:SetPoint("BOTTOMRIGHT")

    status = St.Text(m, 11)
    status:SetPoint("TOPLEFT", 12, -8)
    status:SetPoint("RIGHT", m, "RIGHT", -180, 0)
    status:SetJustifyV("TOP")
    status:SetWordWrap(true)
    status:SetHeight(50)
    status:SetTextColor(1, 1, 1, 0.8)

    actionBtn = St.Button(m, L["End and score now"], 160, 22, function()
        if Battle:Active() then Battle:Finish("manual") end
    end)
    actionBtn:SetPoint("TOPRIGHT", -10, -6)
    joinBtn = St.Button(m, L["Play"], 160, 22, function()
        local b = Battle:Active()
        if b then Battle:Join(not b.joined[Me()]) end
    end)
    joinBtn:SetPoint("TOPRIGHT", -10, -32)
    newBtn = St.Button(m, L["New battle"], 160, 22, function()
        Battle.view = "setup"
        Battle:Refresh()
    end)
    newBtn:SetPoint("TOPRIGHT", -10, -6)
    newBtn:SetActive(true)

    local inset = CreateFrame("Frame", nil, m)
    inset:SetPoint("TOPLEFT", 8, -62)
    inset:SetPoint("TOPRIGHT", -8, -62)
    inset:SetHeight(26 + #CATS * 26 + 4)
    m.inset = inset
    local bg = St.Fill(inset, St.INSET)
    bg:SetAllPoints()
    St.Border(inset, 0.06)
    local header = CreateFrame("Frame", nil, inset)
    header:SetPoint("TOPLEFT"); header:SetPoint("TOPRIGHT"); header:SetHeight(24)
    local hline = St.Fill(header, { 1, 1, 1, 0.08 }, "BORDER")
    hline:SetPoint("BOTTOMLEFT", 4, 0); hline:SetPoint("BOTTOMRIGHT", -4, 0); hline:SetHeight(1)
    local function Head(text, x, justify, w)
        local fs = St.Text(header, 10, justify)
        fs:SetText(text)
        fs:SetTextColor(1, 1, 1, 0.55)
        if justify == "RIGHT" then fs:SetPoint("RIGHT", header, "LEFT", x + w, 0) else fs:SetPoint("LEFT", x, 0) end
        return fs
    end
    Head(L["Category"], COLS.cat, "LEFT")
    Head(L["Leading / winner"], COLS.lead, "LEFT")
    Head(L["Value"], COLS.value, "RIGHT", COLS.tip - 10 - COLS.value)
    tipHead = Head(L["Your tip"], COLS.tip, "LEFT")

    -- The category rows scroll once there are more than MAX_ROWS of them.
    local scroll = CreateFrame("ScrollFrame", nil, inset)
    scroll:SetPoint("TOPLEFT", 0, -26)
    scroll:SetPoint("TOPRIGHT", 0, -26)
    scroll:SetHeight(26)
    if scroll.SetClipsChildren then scroll:SetClipsChildren(true) end
    local child = CreateFrame("Frame", nil, scroll)
    child:SetSize(W - 16, 26)
    scroll:SetScrollChild(child)
    local thumb = scroll:CreateTexture(nil, "OVERLAY")
    thumb:SetWidth(3)
    thumb:Hide()
    function scroll:Update(delta)
        local range = max(0, child:GetHeight() - self:GetHeight())
        local pos = min(range, max(0, self:GetVerticalScroll() + (delta or 0)))
        self:SetVerticalScroll(pos)
        if range <= 0 then thumb:Hide() return end
        local h = self:GetHeight()
        local th = max(20, h * h / child:GetHeight())
        thumb:SetHeight(th)
        thumb:ClearAllPoints()
        thumb:SetPoint("TOPRIGHT", self, "TOPRIGHT", -2, -(h - th) * pos / range)
        local r, g, b = St.Accent()
        thumb:SetColorTexture(r, g, b, 0.7)
        thumb:Show()
    end
    local function Wheel(_, delta) scroll:Update(-delta * 26 * 2) end
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", Wheel)
    m.scroll, m.child = scroll, child
    BuildRows(child)
    for _, row in ipairs(catRows) do
        row:EnableMouseWheel(true)
        row:SetScript("OnMouseWheel", Wheel)
    end

    m.bottom = CreateFrame("Frame", nil, m)
    m.bottom:SetPoint("TOPLEFT", inset, "BOTTOMLEFT", 0, -34)
    m.bottom:SetPoint("BOTTOMRIGHT", -8, 8)
    local bbg = St.Fill(m.bottom, St.INSET)
    bbg:SetAllPoints()
    St.Border(m.bottom, 0.06)
    tabPlayers = St.Button(m, L["Players"], 140, 22, function() Battle.bottom = "players"; Battle:Refresh() end)
    tabPlayers:SetPoint("BOTTOMLEFT", m.bottom, "TOPLEFT", 0, 6)
    tabPay = St.Button(m, L["Payout"], 140, 22, function() Battle.bottom = "pay"; Battle:Refresh() end)
    tabPay:SetPoint("LEFT", tabPlayers, "RIGHT", 4, 0)
    bottomTitle = St.Text(m, 10, "RIGHT")
    bottomTitle:SetPoint("BOTTOMRIGHT", m.bottom, "TOPRIGHT", -4, 10)
    bottomTitle:SetPoint("LEFT", tabPay, "RIGHT", 8, 0)
    bottomTitle:SetTextColor(1, 1, 1, 0.55)
    bottomList = St.List(m.bottom, 20, ListMake, ListFill)
    bottomList:SetPoint("TOPLEFT", 2, -2)
    bottomList:SetPoint("BOTTOMRIGHT", -2, 2)
    return m
end

local function PlayerItems(b, result)
    local items, names = {}, {}
    for name in pairs(b.joined) do names[#names + 1] = name end
    local tipped = {}
    for _, t in ipairs(result.tippers) do tipped[t.name] = t end
    local points = {}
    if result.total then for _, p in ipairs(result.total.list) do points[p.name] = p.value end end
    sort(names, function(a, c)
        if b.mode == "tips" and b.done then
            local ra, rc = tipped[a] and tipped[a].right or -1, tipped[c] and tipped[c].right or -1
            if ra ~= rc then return ra > rc end
        elseif points[a] ~= points[c] then
            return (points[a] or 0) > (points[c] or 0)
        end
        return a < c
    end)
    for _, name in ipairs(names) do
        local p = b.players[name]
        local text
        if b.mode == "tips" then
            local tips = b.tips[name] or {}
            local count = 0
            for key in pairs(tips) do if b.cats[key] then count = count + 1 end end
            if b.done then
                local t = tipped[name]
                text = t and format(L["%d of %d right"], t.right, t.count) or L["no tips"]
            elseif name == Me() then
                local parts = {}
                for _, c in ipairs(CATS) do if tips[c.key] then parts[#parts + 1] = c.alias[1] .. ": " .. tips[c.key] end end
                text = #parts > 0 and concat(parts, ", ") or L["no tips"]
            else
                -- Others' tips stay hidden until the end, so nobody copies them.
                text = count > 0 and format(L["%d tips placed"], count) or L["no tips"]
            end
        else
            text = points[name] and format(L["%d pts"], points[name]) or L["playing"]
        end
        items[#items + 1] = { label = ns.ClassName(name, p and p.c), text = "|cffbbbbbb" .. text .. "|r" }
    end
    for name in pairs(b.players) do
        if not b.joined[name] then
            items[#items + 1] = { label = "|cff777777" .. name .. "|r",
                text = "|cff777777" .. (b.locked and L["not playing"] or L["has not joined (!join)"]) .. "|r" }
        end
    end
    if #items == 0 then items[1] = { label = "|cff666666-|r", text = "" } end
    return items
end

local function PayItems(b, result)
    local pay = result.payout
    if not pay then
        return { { label = "|cff9a9a9a" .. L["No stake in this battle (or fewer than 2 players)."] .. "|r", text = "" } }
    end
    local items = {
        { label = "|cffffd100" .. L["Pot"] .. "|r", text = format(L["%s (%s per player)"], ns.Money(pay.pot), ns.Money(pay.stake)) },
    }
    for _, tr in ipairs(pay.transfers) do
        items[#items + 1] = { label = ns.ClassName(tr.from, tr.fc) .. "  |cff9a9a9a" .. L["gives"] .. "|r  " .. ns.ClassName(tr.to, tr.tc),
            text = ns.Money(tr.amount) }
    end
    if #pay.transfers == 0 then
        items[#items + 1] = { label = "|cff9a9a9a" .. L["Nobody owes anybody anything."] .. "|r", text = "" }
    end
    items[#items + 1] = { label = " ", text = "" }
    for _, e in ipairs(pay.rows) do
        local net = e.net
        local d = net > 0 and ("|cff66dd66+" .. ns.Money(net) .. "|r") or (net < 0 and ("|cffff6655-" .. ns.Money(-net) .. "|r") or "|cff9a9a9a+/- 0|r")
        items[#items + 1] = { label = ns.ClassName(e.name, e.c), text = d }
    end
    return items
end

function Battle:Refresh()
    if not frame or not frame:IsShown() then return end
    local b = Current()
    if not b or self.view == "setup" then
        setup:Show(); main:Hide()
        setup:Sync()
        frame:SetHeight(setup.height + 30)
        return
    end
    setup:Hide(); main:Show()

    local active = not b.done
    local result = b.done and b.result or self:Evaluate(b)
    local joined = b.joined[Me()] and true or false
    local tipsMode = b.mode == "tips"

    local lines = {}
    local stakeText = b.stake > 0 and format(L["stake %s, pot %s"], ns.Money(b.stake), ns.Money(b.stake * JoinedCount(b))) or L["no stake"]
    if b.done then
        lines[1] = format(L["Finished: %s, %s"], b.place or "?", ns.DayLabel(b.done) .. " " .. ns.Clock(b.done))
        lines[2] = MODES[b.mode].label .. "  ·  " .. stakeText .. (b.boss and ("  ·  " .. b.boss) or "")
    else
        lines[1] = format(L["%s's battle in %s, running for %d min"], b.host or "?", b.place or "?", floor((time() - b.t) / 60))
        local boss = ns.FinalBossNames(b.instanceID)
        lines[2] = MODES[b.mode].label .. "  ·  " .. stakeText .. "  ·  " ..
            (boss and format(L["Ends when %s dies"], boss) or L["No known last boss here: end it with the button."])
        lines[3] = b.locked and ("|cffff6655" .. L["Joining is closed."] .. "|r")
            or ("|cff66dd66" .. (tipsMode and L["Join and tip until the first boss dies."] or L["Join until the first boss dies."]) .. "|r")
    end
    status:SetText(concat(lines, "\n"))
    actionBtn:SetShown(active and b.host == Me())
    newBtn:SetShown(not active)
    joinBtn:SetShown(active and not b.locked)
    joinBtn.text:SetText(joined and L["Leave"] or L["Play"])
    joinBtn:SetActive(not joined)
    tipHead:SetShown(tipsMode)

    local y = 0
    for _, row in ipairs(catRows) do
        local entry = b.cats[row.cat.key] and result[row.cat.key]
        if entry then
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", 0, -y)
            row:SetPoint("TOPRIGHT", 0, -y)
            row.bg:SetColorTexture(1, 1, 1, (y / 26) % 2 == 0 and 0.025 or 0)
            row:Show()
            y = y + 26
            local names = {}
            for _, p in ipairs(entry.list) do
                if entry.winners[p.name] then names[#names + 1] = ns.ClassName(p.name, p.c) end
            end
            if #names > 0 then
                row.crown:Show()
                row.crown:SetVertexColor(b.done and 1 or 0.7, b.done and 0.82 or 0.7, b.done and 0 or 0.7)
                row.lead:SetText(concat(names, ", "))
                row.value:SetText(FormatValue(row.cat, entry.list[1].value))
            else
                row.crown:Hide()
                row.lead:SetText("|cff666666-|r")
                row.value:SetText("")
            end
            local tip = (b.tips[Me()] or {})[row.cat.key]
            local canTip = tipsMode and active and not b.locked and joined
            row.tip:SetShown(canTip)
            row.tipText:SetShown(tipsMode and not canTip)
            if canTip then
                local info = tip and b.players[tip]
                row.tip.text:SetText(tip and ns.ClassName(tip, info and info.c) or L["Pick"])
            elseif tip then
                local mark = ""
                if b.done then
                    mark = entry.winners[tip] and ("|cff66dd66  " .. L["right"] .. "|r") or ("|cffff6655  " .. L["wrong"] .. "|r")
                end
                local info = b.players[tip]
                row.tipText:SetText(ns.ClassName(tip, info and info.c) .. mark)
            else
                row.tipText:SetText("|cff666666" .. (joined and L["no tip"] or "-") .. "|r")
            end
        else
            row:Hide()
        end
    end
    -- At most MAX_ROWS categories visible; the rest scrolls.
    local visible = min(max(y, 26), MAX_ROWS * 26)
    main.child:SetHeight(max(y, 1))
    main.scroll:SetHeight(visible)
    main.scroll:Update()
    main.inset:SetHeight(26 + visible + 4)

    local hasPay = b.stake and b.stake > 0
    if not self.bottom or (self.bottom == "pay" and not hasPay) then self.bottom = "players" end
    tabPlayers:SetActive(self.bottom == "players")
    tabPay:SetActive(self.bottom == "pay")
    tabPay:SetShown(hasPay and true or false)
    if self.bottom == "pay" then
        bottomTitle:SetText(b.done and L["Result"] or L["If it ended now"])
        bottomList:SetData(PayItems(b, result), true)
    else
        bottomTitle:SetText(format(L["%d playing"], JoinedCount(b)))
        bottomList:SetData(PlayerItems(b, result), true)
    end
    frame:SetHeight(30 + 62 + main.inset:GetHeight() + 34 + 150)
end

local function Build()
    frame = St.Window("NibbelzLootBattleFrame", W, 560, L["Loot battle"], "battle")
    frame:Place({ "CENTER", UIParent, "CENTER", -40, 40 })
    frame:SetScale(ns.db.opts.scale or 1)
    frame:SetFrameStrata("HIGH")
    frame:Hide()
    tinsert(UISpecialFrames, "NibbelzLootBattleFrame")

    local logo = frame.bar:CreateTexture(nil, "OVERLAY")
    logo:SetSize(16, 16)
    logo:SetPoint("LEFT", 10, 0)
    logo:SetTexture("Interface\\Icons\\Ability_DualWield")
    logo:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    frame.title:ClearAllPoints()
    frame.title:SetPoint("LEFT", logo, "RIGHT", 6, 0)

    setup = BuildSetup(frame)
    main = BuildMain(frame)
    -- No category is ticked at first: the host picks what the battle is about.

    frame:SetScript("OnShow", function() Battle:Refresh() end)
    frame:SetScript("OnHide", CloseMenu)
end

function Battle:Open()
    if not frame then return end
    frame:Show()
    frame:Raise()
    self:Refresh()
end

-- /rolls battle: the running battle, or the setup for a new one.
function Battle:Command()
    if not frame then return end
    if frame:IsShown() then
        frame:Hide()
        return
    end
    self.view = self:Active() and nil or "setup"
    self:Open()
end

function Battle:Toggle()
    if not frame then return end
    if frame:IsShown() then frame:Hide() else self:Open() end
end

function Battle:ApplyScale()
    if frame then frame:SetScale(ns.db.opts.scale or 1) end
end

-------------------------------------------------------------------------------
--  Events
-------------------------------------------------------------------------------
local lastKey

local function OnZone()
    local ctx = ns.ctx
    local b = Battle:Active()
    if b and b.key and b.key:sub(1, 2) == "i:" and ctx.key ~= b.key then
        Battle:Finish("left")
    end
    if ctx.inst and ctx.key ~= lastKey and not Battle:Active() and ns.db.opts.battleOffer
        and IsInGroup and IsInGroup() then
        ns.Print(L["New dungeon: start a loot battle with /rolls battle."])
    end
    lastKey = ctx.key
end

local CHAT_EVENTS = {
    CHAT_MSG_PARTY = true, CHAT_MSG_PARTY_LEADER = true, CHAT_MSG_RAID = true,
    CHAT_MSG_RAID_LEADER = true, CHAT_MSG_INSTANCE_CHAT = true, CHAT_MSG_INSTANCE_CHAT_LEADER = true,
}

function Battle:Init()
    -- Battles saved by an older version had no mode or stake.
    for _, b in ipairs({ ns.db.battle, unpack(ns.db.battles or {}) }) do
        if type(b) == "table" then
            b.mode = MODES[b.mode] and b.mode or "tips"
            b.stake = b.stake or 0
            b.cats = b.cats or {}
            b.joined = b.joined or {}
        end
    end
    Build()
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
        pcall(C_ChatInfo.RegisterAddonMessagePrefix, PREFIX)
    end
    lastKey = ns.ctx.key
    ns.OnGroupLoot(OnLoot)
    local ev = CreateFrame("Frame")
    for _, e in ipairs({ "CHAT_MSG_ADDON", "ENCOUNTER_END", "BOSS_KILL", "PARTY_KILL", "PLAYER_REGEN_ENABLED",
        "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "GROUP_ROSTER_UPDATE" }) do
        pcall(ev.RegisterEvent, ev, e)
    end
    -- Group chat (!join, !tip) is only listened to while a battle runs: see Battle:Tick.
    Battle.ev = ev
    ev:SetScript("OnEvent", function(_, event, ...)
        if CHAT_EVENTS[event] then
            local text, sender = ...
            OnGroupChat(text, sender)
        elseif event == "CHAT_MSG_ADDON" then
            OnAddonMessage(...)
        elseif event == "ENCOUNTER_END" then
            local id, name, _, _, success = ...
            OnEncounterEnd(id, name, success)
        elseif event == "BOSS_KILL" then
            local id, name = ...
            OnEncounterEnd(id, name, 1)
        elseif event == "PARTY_KILL" then
            OnPartyKill((...))
        elseif event == "PLAYER_REGEN_ENABLED" then
            -- The damage meter is readable again shortly after a fight.
            if Battle:Active() then
                C_Timer.After(1.5, function()
                    local b = Battle:Active()
                    if b then UpdateMeters(b); Battle:Refresh() end
                end)
            end
        elseif event == "GROUP_ROSTER_UPDATE" then
            if Battle:Active() then
                ns.Debounce("battleRoster", 1, function()
                    local b = Battle:Active()
                    if b then AddRoster(b); Battle:Refresh() end
                end)
            end
        else
            C_Timer.After(0.5, OnZone)   -- after Core has updated the place
        end
    end)
    self:Tick()
    ns.Listen(function()
        if frame:IsShown() then ns.Debounce("battle", 0.5, function() Battle:Refresh() end) end
    end)
    C_Timer.After(5, function()
        local b = Battle:Active()
        if b then
            AddRoster(b)
            Send("Q\t" .. b.id)
            SendState()
            Battle:Refresh()
        end
        -- The last finished battle too: one entry per player.
        local last = Current()
        if last and last.done then
            CanonBattle(last)
            if last.result then last.result = Battle:Evaluate(last) end
        end
    end)
end
