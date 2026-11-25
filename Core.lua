-- Core.lua: reads the game's loot history, keeps the roll history and the visits
-- (one visit = one run through a dungeon or a stay in a zone).
local ADDON, ns = ...
_G.NibbelzLoot = ns
local L = ns.L

local format, floor, max, min = string.format, math.floor, math.max, math.min
local tinsert, tremove, sort, wipe = table.insert, table.remove, table.sort, wipe
local time, date = time, date

local MAX_RECORDS = 5000
local KEY_TTL = 2 * 60 * 60       -- a drop key from the game is only trusted this long
local VISIT_GAP = 60 * 60         -- same place, no zone change: still the same visit
local VISIT_REENTER = 10 * 60     -- left and came back this fast (died, ran back): same visit

-------------------------------------------------------------------------------
--  Roll states (Enum.EncounterLootDropRollState)
-------------------------------------------------------------------------------
local E = (Enum and Enum.EncounterLootDropRollState) or {}
local S = {
    NEED = E.NeedMainSpec or 0,
    OFF = E.NeedOffSpec or 1,
    XMOG = E.Transmog or 2,
    GREED = E.Greed or 3,
    NONE = E.NoRoll or 4,
    PASS = E.Pass or 5,
}
ns.S = S

local STATE_INFO = {
    [S.NEED]  = { key = "need",  label = L["Need"],     color = { 0.30, 0.85, 0.40 }, atlas = "lootroll-icon-need",     file = "Interface\\Buttons\\UI-GroupLoot-Dice-Up" },
    [S.OFF]   = { key = "need",  label = L["Need"],     color = { 0.30, 0.85, 0.40 }, atlas = "lootroll-icon-need",     file = "Interface\\Buttons\\UI-GroupLoot-Dice-Up" },
    [S.XMOG]  = { key = "xmog",  label = L["Transmog"], color = { 0.80, 0.55, 1.00 }, atlas = "lootroll-icon-transmog", file = "Interface\\Buttons\\UI-GroupLoot-DE-Up" },
    [S.GREED] = { key = "greed", label = L["Greed"],    color = { 1.00, 0.78, 0.20 }, atlas = "lootroll-icon-greed",    file = "Interface\\Buttons\\UI-GroupLoot-Coin-Up" },
    [S.PASS]  = { key = "pass",  label = L["Pass"],     color = { 0.95, 0.30, 0.28 }, atlas = "lootroll-icon-pass",     file = "Interface\\Buttons\\UI-GroupLoot-Pass-Up" },
    [S.NONE]  = { key = "wait",  label = L["waiting"],  color = { 0.62, 0.62, 0.62 } },
}
function ns.StateInfo(state)
    return STATE_INFO[state] or STATE_INFO[S.NONE]
end
function ns.Picked(state)
    return state == S.NEED or state == S.OFF or state == S.XMOG or state == S.GREED
end

-------------------------------------------------------------------------------
--  Helpers
-------------------------------------------------------------------------------
local isSecret = issecretvalue or function() return false end

-- A value we may read: not a secret (12.x restricted value) and of the wanted type.
local function Plain(v, kind)
    if v == nil or isSecret(v) then return nil end
    if kind and type(v) ~= kind then return nil end
    return v
end
ns.Plain = Plain

-------------------------------------------------------------------------------
--  Player names. WoW Forever characters have a surname: UnitName() gives the
--  first name and the surname apart, while chat, loot lines and the loot history
--  give "Name Surname". Everything here uses the one full spelling.
-------------------------------------------------------------------------------
local IS_FOREVER = (function()
    local v = select(4, GetBuildInfo())
    return type(v) == "number" and v >= 16000 and v < 20000
end)()
local SEP = (Constants and Constants.CharacterNameSeparatorConsts
    and Constants.CharacterNameSeparatorConsts.CHARACTERNAME_SURNAME_SEPARATOR) or " "
local fullByFirst = {}   -- "Nibbelz" -> "Nibbelz Starcaller" (also saved: NibbelzLootDB.names)

-- The full name for any spelling of a player's name ("-Realm" dropped).
function ns.Name(name)
    if type(name) ~= "string" or isSecret(name) or name == "" then return nil end
    name = name:match("^([^%-]+)") or name
    local at = name:find(SEP, 1, true)
    if at then
        local first = name:sub(1, at - 1)
        if fullByFirst[first] ~= name then
            fullByFirst[first] = name
            if ns.db and ns.db.names then ns.db.names[first] = name end
        end
        return name
    end
    return fullByFirst[name] or name
end

-- A unit's full name: "Name Surname" on WoW Forever.
function ns.UnitFullName(unit)
    local first, second = (UnitNameUnmodified or UnitName)(unit)
    first, second = Plain(first, "string"), Plain(second, "string")
    if not first or first == "" or first == UNKNOWNOBJECT then return nil end
    if IS_FOREVER and second and second ~= "" then return ns.Name(first .. SEP .. second) end
    return ns.Name(first)
end

function ns.MyName()
    return ns.UnitFullName("player") or UnitName("player")
end

local Short = ns.Name

function ns.Print(msg)
    print("|cff0cd29fNibbelz Loot|r " .. tostring(msg))
end

function ns.ClassColor(class)
    local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if c then return c.r, c.g, c.b end
    return 0.85, 0.85, 0.85
end

function ns.Hex(r, g, b)
    return format("|cff%02x%02x%02x", floor(r * 255 + 0.5), floor(g * 255 + 0.5), floor(b * 255 + 0.5))
end

-- A player's class from anything we have seen of them (group roster, rolls).
function ns.KnownClass(name)
    local players = ns.db and ns.db.players
    if not (players and name) then return nil end
    local p = players[name] or players[ns.Name(name) or name]
    return p and p.c
end

function ns.ClassName(name, class)
    class = class or ns.KnownClass(name)
    return ns.Hex(ns.ClassColor(class)) .. (name or "?") .. "|r"
end

function ns.QualityColor(q)
    local c = q and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
    if c then return c.r, c.g, c.b end
    return 1, 1, 1
end

-- Vendor value as coins: 12g 34s 5c with the game's coin icons.
local GOLD = "|TInterface\\MoneyFrame\\UI-GoldIcon:0:0:2:0|t"
local SILVER = "|TInterface\\MoneyFrame\\UI-SilverIcon:0:0:2:0|t"
local COPPER = "|TInterface\\MoneyFrame\\UI-CopperIcon:0:0:2:0|t"
function ns.Money(copper)
    copper = floor(copper or 0)
    if copper <= 0 then return "0" .. COPPER end
    local g, s, c = floor(copper / 10000), floor(copper / 100) % 100, copper % 100
    local parts = {}
    if g > 0 then parts[#parts + 1] = (BreakUpLargeNumbers and BreakUpLargeNumbers(g) or g) .. GOLD end
    if s > 0 then parts[#parts + 1] = s .. SILVER end
    if c > 0 and g < 100 then parts[#parts + 1] = c .. COPPER end
    return table.concat(parts, " ")
end

-- Plain text money for chat lines: 12g 34s 5c
function ns.MoneyPlain(copper)
    copper = floor(copper or 0)
    local g, s, c = floor(copper / 10000), floor(copper / 100) % 100, copper % 100
    if g > 0 then return format("|cffffd700%dg|r |cffc7c7cf%ds|r |cffeda55f%dc|r", g, s, c) end
    if s > 0 then return format("|cffc7c7cf%ds|r |cffeda55f%dc|r", s, c) end
    return format("|cffeda55f%dc|r", c)
end

local WEEKDAYS_DE = { "So", "Mo", "Di", "Mi", "Do", "Fr", "Sa" }
local WEEKDAYS_EN = { "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat" }

function ns.DayKey(t)
    return date("%Y-%m-%d", t)
end

function ns.DayLabel(t)
    local key = ns.DayKey(t)
    local now = time()
    if key == ns.DayKey(now) then return L["Today"] end
    if key == ns.DayKey(now - 86400) then return L["Yesterday"] end
    local wd = tonumber(date("%w", t)) + 1
    if ns.IS_DE then return WEEKDAYS_DE[wd] .. " " .. date("%d.%m.", t) end
    return WEEKDAYS_EN[wd] .. " " .. date("%m/%d", t)
end

-- "1 player" / "5 players"
function ns.Players(n)
    if n == 1 then return L["1 player"] end
    return format(L["%d players"], n)
end

function ns.Clock(t)
    return date("%H:%M", t)
end

-------------------------------------------------------------------------------
--  Change notification (the windows listen)
-------------------------------------------------------------------------------
local listeners = {}
function ns.Listen(fn) listeners[#listeners + 1] = fn end

-- Runs fn once, delay seconds after the first of a burst of calls (roster changes
-- come in bursts of many events).
local debounced = {}
function ns.Debounce(key, delay, fn)
    if debounced[key] then return end
    debounced[key] = true
    C_Timer.After(delay, function()
        debounced[key] = nil
        fn()
    end)
end

local notifyQueued = false
function ns.Notify()
    if notifyQueued then return end
    notifyQueued = true
    C_Timer.After(0, function()
        notifyQueued = false
        for i = 1, #listeners do listeners[i]() end
    end)
end

-------------------------------------------------------------------------------
--  Saved data
-------------------------------------------------------------------------------
local DB
local byId, visitById = {}, {}
ns.byId, ns.visitById = byId, visitById

ns.STAY_OPEN = 61   -- liveStay value past the 60 seconds: the roll window stays open

local DEFAULTS = {
    autoShow = true,     -- open the roll window when a new roll starts
    scale = 1,
    minimapAngle = 200,  -- where the minimap button sits (degrees)
    minimapHide = false,
    battleOffer = true,      -- remind of /rolls battle when entering a dungeon in a group
    battleAnnounce = false,  -- post the battle result in group chat
    sound100 = true,         -- play a sound when someone rolls a 100
    hideRollChat = true,     -- hide the game's roll lines in chat (Loot.lua)
    autoClose = true,        -- close the roll window once every roll is done
    theme = "nibbelz",       -- window style (Style.lua), applied at load
}

local function InitDB()
    NibbelzLootDB = NibbelzLootDB or {}
    DB = NibbelzLootDB
    DB.rolls = DB.rolls or {}
    DB.visits = DB.visits or {}
    DB.keys = DB.keys or {}
    DB.nextId = DB.nextId or 1
    DB.nextVisit = DB.nextVisit or 1
    DB.opts = DB.opts or {}
    for k, v in pairs(DEFAULTS) do
        if DB.opts[k] == nil then DB.opts[k] = v end
    end
    -- Once: switch to the Nibbelz style (the look of Nibbelz Debuff Gradiant).
    if not DB.opts.nibbelzStyle then
        DB.opts.nibbelzStyle = true
        DB.opts.theme = "nibbelz"
    end
    -- How long the roll window stays open after the last roll: 0 = it never opens by
    -- itself, 1-60 seconds, STAY_OPEN = it stays open. Replaces autoShow / autoClose.
    if DB.opts.liveStay == nil then
        if DB.opts.autoShow == false then
            DB.opts.liveStay = 0
        elseif DB.opts.autoClose == false then
            DB.opts.liveStay = ns.STAY_OPEN
        else
            DB.opts.liveStay = 5
        end
    end
    DB.opts.hideStats = DB.opts.hideStats or {}
    DB.pos = DB.pos or {}
    DB.players = DB.players or {}
    DB.names = DB.names or {}
    ns.db = DB
    for first, full in pairs(DB.names) do fullByFirst[first] = full end
    -- Players saved under their first name only: move them to the full name.
    for name, p in pairs(DB.players) do
        local full = fullByFirst[name]
        if full and full ~= name then
            local into = DB.players[full] or {}
            into.c = into.c or p.c
            into.g = into.g or p.g
            into.last = math.max(into.last or 0, p.last or 0)
            DB.players[full] = into
            DB.players[name] = nil
        end
    end

    for _, rec in ipairs(DB.rolls) do byId[rec.id] = rec end
    for _, v in ipairs(DB.visits) do visitById[v.id] = v end

    local now = time()
    for key, k in pairs(DB.keys) do
        if type(k) ~= "table" or now - (k.t or 0) > KEY_TTL then DB.keys[key] = nil end
    end
end

local function PruneOld()
    local extra = #DB.rolls - MAX_RECORDS
    if extra <= 0 then return end
    for _ = 1, extra do
        local rec = tremove(DB.rolls, 1)
        byId[rec.id] = nil
    end
    local used = {}
    for _, rec in ipairs(DB.rolls) do used[rec.v] = true end
    for i = #DB.visits, 1, -1 do
        local v = DB.visits[i]
        if not used[v.id] and v.id ~= DB.cur then
            visitById[v.id] = nil
            tremove(DB.visits, i)
        end
    end
end

-------------------------------------------------------------------------------
--  Where we are: one visit per dungeon run / zone stay
-------------------------------------------------------------------------------
local ctx = { place = L["Unknown"], key = "?", changed = false }
ns.ctx = ctx

local function UpdateContext()
    if not DB then return end
    local name, itype, _, _, _, _, _, instanceID = GetInstanceInfo()
    local inInstance = itype == "party" or itype == "raid" or itype == "scenario"
    local place
    if inInstance then
        place = name
    else
        place = GetRealZoneText and GetRealZoneText() or name
    end
    if not place or place == "" then place = name or L["Unknown"] end
    ctx.place, ctx.inst = place, inInstance
    ctx.instanceID = inInstance and instanceID or nil
    ctx.key = inInstance and ("i:" .. tostring(instanceID or name)) or ("z:" .. place)
    if DB.lastKey ~= ctx.key then
        -- Left a dungeon: its rolls leave the roll window (they stay in the history).
        if type(DB.lastKey) == "string" and DB.lastKey:sub(1, 2) == "i:" then
            ns.ClearLive()
        end
        DB.lastKey = ctx.key
        ctx.changed = true
    end
end

function ns.CurrentVisit()
    return DB and DB.cur and visitById[DB.cur]
end

local function EnsureVisit(now)
    local v = ns.CurrentVisit()
    local reuse = v and v.key == ctx.key and (
        (not ctx.changed and now - v.last < VISIT_GAP) or (now - v.last < VISIT_REENTER))
    if not reuse then
        v = { id = DB.nextVisit, key = ctx.key, place = ctx.place, inst = ctx.inst or nil, t = now, last = now }
        DB.nextVisit = DB.nextVisit + 1
        tinsert(DB.visits, v)
        visitById[v.id] = v
        DB.cur = v.id
    end
    ctx.changed = false
    v.last = now
    ns.CaptureRoster(v)
    return v
end

-------------------------------------------------------------------------------
--  Money looted (coins from mobs and chests, your share of the group's coins)
-------------------------------------------------------------------------------
-- "%d Gold" -> "(%d+) Gold", from the game's own (localized) strings.
local coinPatterns
local function CoinPatterns()
    if coinPatterns then return coinPatterns end
    coinPatterns = {}
    for i, g in ipairs({ _G.GOLD_AMOUNT or "%d Gold", _G.SILVER_AMOUNT or "%d Silver", _G.COPPER_AMOUNT or "%d Copper" }) do
        local p = g:gsub("[%(%)%.%+%-%*%?%[%]%^%$]", "%%%0"):gsub("%%d", "(%%d+)")
        coinPatterns[i] = { p, i == 1 and 10000 or (i == 2 and 100 or 1) }
    end
    return coinPatterns
end

local function ParseCoins(msg)
    local total, found = 0, false
    for _, cp in ipairs(CoinPatterns()) do
        local n = msg:match(cp[1])
        if n then
            total = total + tonumber(n) * cp[2]
            found = true
        end
    end
    return found and total or nil
end

function ns.AddMoney(copper)
    if not DB or not copper or copper <= 0 then return end
    local now = time()
    local v = ns.CurrentVisit()
    if not (v and v.key == ctx.key and now - v.last < VISIT_GAP) then v = EnsureVisit(now) end
    v.money = (v.money or 0) + copper
    v.last = now
    ns.Notify()
end

-- The chat line can be unreadable (secret) in combat: then the next rise of the
-- player's money right after it is taken instead.
local lastMoney, moneyPendingUntil = nil, 0
local function OnMoneyChat(msg)
    local copper = Plain(msg, "string") and ParseCoins(msg)
    if copper then
        ns.AddMoney(copper)
    else
        moneyPendingUntil = GetTime() + 2
    end
end

local function OnPlayerMoney()
    local now = GetMoney()
    local delta = lastMoney and (now - lastMoney) or 0
    lastMoney = now
    if delta > 0 and GetTime() < moneyPendingUntil then
        moneyPendingUntil = 0
        ns.AddMoney(delta)
    end
end

-------------------------------------------------------------------------------
--  Group members and their guilds (for the group stats window)
-------------------------------------------------------------------------------
local function GroupUnits()
    local units = { "player" }
    if IsInRaid and IsInRaid() then
        for i = 1, GetNumGroupMembers() do units[#units + 1] = "raid" .. i end
    elseif IsInGroup and IsInGroup() then
        for i = 1, GetNumSubgroupMembers() do units[#units + 1] = "party" .. i end
    end
    return units
end

-- Remembers who is in the group (class, guild) and marks them in the visit.
function ns.CaptureRoster(v)
    if not DB then return end
    local now = time()
    for _, unit in ipairs(GroupUnits()) do
        if UnitExists(unit) then
            local name = ns.UnitFullName(unit)
            if name then
                local _, class = UnitClass(unit)
                local guild = Plain(GetGuildInfo(unit), "string")
                local p = DB.players[name]
                if not p then
                    p = {}
                    DB.players[name] = p
                end
                p.c = Plain(class, "string") or p.c
                if guild then p.g = guild end
                p.last = now
                if v then
                    v.m = v.m or {}
                    v.m[name] = true
                end
            end
        end
    end
end

local function OnRoster()
    local v = ns.CurrentVisit()
    -- Only the visit we are still in: same place, not long ago.
    if v and v.key == ctx.key and time() - v.last < VISIT_GAP then
        ns.CaptureRoster(v)
    else
        ns.CaptureRoster(nil)
    end
end

-------------------------------------------------------------------------------
--  Items
-------------------------------------------------------------------------------
local GetItemInfo = (C_Item and C_Item.GetItemInfo) or _G.GetItemInfo
local GetItemInfoInstant = (C_Item and C_Item.GetItemInfoInstant) or _G.GetItemInfoInstant
local waiting = {}

function ns.ItemID(rec)
    if not rec.iid then rec.iid = (GetItemInfoInstant(rec.link)) end
    return rec.iid
end

-- Auction house prices. Each source: available() and price(itemID, link) -> copper or nil.
-- "auto" asks them in this order and takes the first price found.
local function Num(ok, v)
    if ok and type(v) == "number" and v > 0 then return floor(v) end
end
local function ItemLink(itemID, link)
    return link or select(2, GetItemInfo(itemID))
end
ns.AH_SOURCES = {
    {   -- TradeSkillMaster: AuctionDB market value, else min buyout
        key = "tsm", label = "TradeSkillMaster",
        available = function() return _G.TSM_API and type(TSM_API.GetCustomPriceValue) == "function" end,
        price = function(id)
            local item = "i:" .. id
            return Num(pcall(TSM_API.GetCustomPriceValue, "dbmarket", item))
                or Num(pcall(TSM_API.GetCustomPriceValue, "dbminbuyout", item))
        end,
    },
    {   -- Auctionator: last scanned price
        key = "auctionator", label = "Auctionator",
        available = function()
            local api = _G.Auctionator and Auctionator.API and Auctionator.API.v1
            return api and type(api.GetAuctionPriceByItemID) == "function"
        end,
        price = function(id, link)
            local api = Auctionator.API.v1
            local p = Num(pcall(api.GetAuctionPriceByItemID, "NibbelzLoot", id))
            if not p and type(api.GetAuctionPriceByItemLink) == "function" then
                link = ItemLink(id, link)
                if link then p = Num(pcall(api.GetAuctionPriceByItemLink, "NibbelzLoot", link)) end
            end
            return p
        end,
    },
    {   -- Auctioneer: market value
        key = "auctioneer", label = "Auctioneer",
        available = function()
            return _G.AucAdvanced and AucAdvanced.API and type(AucAdvanced.API.GetMarketValue) == "function"
        end,
        price = function(id, link)
            link = ItemLink(id, link)
            if not link then return nil end
            return Num(pcall(AucAdvanced.API.GetMarketValue, link))
        end,
    },
    {   -- NaowhForever: its own scans or the prices shipped in NaowhForever_AuctionData
        key = "naowh", label = "NaowhForever",
        available = function()
            return _G.NaowhForever and type(NaowhForever.AuctionPrice) == "function"
        end,
        price = function(id) return Num(pcall(NaowhForever.AuctionPrice, id)) end,
    },
}

local ahMiss = {}
-- After switching the price source: items without a price may find one now.
function ns.ResetAHMisses() wipe(ahMiss) end

function ns.AHLookup(itemID, link)
    if not itemID then return nil end
    local want = DB and DB.opts.ahSource or "auto"
    for _, src in ipairs(ns.AH_SOURCES) do
        if (want == "auto" or want == src.key) and src.available() then
            local p = src.price(itemID, link)
            if p then return p end
        end
    end
    return nil
end

function ns.HasAH()
    for _, src in ipairs(ns.AH_SOURCES) do
        if src.available() then return true end
    end
    return false
end

-- The AH price of a record: taken when the item dropped; older records look it up once.
function ns.AH(rec)
    if rec.ah then return rec.ah end
    if ahMiss[rec] then return nil end
    local price = ns.AHLookup(ns.ItemID(rec), rec.link)
    if price then
        rec.ah = price
    else
        ahMiss[rec] = true
    end
    return price
end

-- A change counter per record (not saved): windows redraw a record only when it moved.
ns.version = setmetatable({}, { __mode = "k" })
local function Touch(rec)
    ns.version[rec] = (ns.version[rec] or 0) + 1
end
ns.Touch = Touch

function ns.FillItem(rec)
    local name, _, quality, _, _, _, _, _, _, icon, sell = GetItemInfo(rec.link)
    if name then
        rec.n, rec.q, rec.icon, rec.sell = name, quality, icon or rec.icon, sell or 0
        Touch(rec)
        return true
    end
    local id, _, _, _, instantIcon = GetItemInfoInstant(rec.link)
    rec.icon = rec.icon or instantIcon
    rec.n = rec.n or rec.link:match("%[(.-)%]") or ("item:" .. tostring(id))
    if not rec.q then
        local hex = rec.link:match("|c(%x%x%x%x%x%x%x%x)")
        if hex and ITEM_QUALITY_COLORS then
            for q, c in pairs(ITEM_QUALITY_COLORS) do
                if c.hex and c.hex:lower():find(hex:lower(), 1, true) then rec.q = q break end
            end
        end
    end
    if waiting[rec] or not (Item and Item.CreateFromItemLink) then return false end
    waiting[rec] = true
    local ok, item = pcall(Item.CreateFromItemLink, Item, rec.link)
    if ok and item and not item:IsItemEmpty() then
        item:ContinueOnItemLoad(function()
            waiting[rec] = nil
            if ns.FillItem(rec) then ns.Notify() end
        end)
    end
    return false
end

-------------------------------------------------------------------------------
--  Reading a drop from the game's loot history
-------------------------------------------------------------------------------
local function PlayHundred()
    if not (PlaySound and SOUNDKIT) then return end
    local kit = SOUNDKIT.UI_LEGENDARY_LOOT_TOAST or SOUNDKIT.UI_EPICLOOT_TOAST or SOUNDKIT.RAID_WARNING
    if kit then pcall(PlaySound, kit, "Master") end
end

local function ReadRolls(rec, info, quiet)
    local me = ns.MyName()
    -- Who had a 100 already, so the sound plays once per player and item.
    local had = {}
    for _, e in ipairs(rec.rolls or {}) do
        if e.r == 100 then had[e.n] = true end
    end
    local rolls = {}
    local list = Plain(info.rollInfos, "table") or {}
    for i = 1, #list do
        local r = list[i]
        local name = Short(Plain(r.playerName, "string"))
        if name then
            local e = {
                n = name,
                c = Plain(r.playerClass, "string"),
                s = Plain(r.state, "number") or S.NONE,
                r = Plain(r.roll, "number"),
            }
            if Plain(r.isWinner, "boolean") then e.w = true end
            if Plain(r.isSelf, "boolean") or name == me then e.me = true end
            rolls[#rolls + 1] = e
            -- Remember the class for colouring the name everywhere.
            if e.c then
                local p = DB.players[name]
                if not p then
                    p = {}
                    DB.players[name] = p
                end
                p.c = e.c
            end
            if e.r == 100 and not had[name] and not quiet and DB.opts.sound100 then
                PlayHundred()
                ns.Print(format(L["%s rolled a 100 on %s!"], ns.ClassName(name, e.c), rec.n or "?"))
            end
        end
    end
    rec.rolls = rolls
    Touch(rec)

    rec.win, rec.wc, rec.ws, rec.wr, rec.mw = nil, nil, nil, nil, nil
    local w = Plain(info.winner, "table")
    local wname = w and Plain(w.playerName, "string")
    if wname then
        rec.win = Short(wname)
        rec.wc = Plain(w.playerClass, "string")
        rec.ws = Plain(w.state, "number")
        rec.wr = Plain(w.roll, "number")
        if Plain(w.isSelf, "boolean") or rec.win == me then rec.mw = true end
    else
        for _, e in ipairs(rolls) do
            if e.w then rec.win, rec.wc, rec.ws, rec.wr = e.n, e.c, e.s, e.r end
        end
    end
    rec.ap = Plain(info.allPassed, "boolean") or nil
    rec.done = (rec.win ~= nil or rec.ap) or nil

    rec.my, rec.mr = nil, nil
    for _, e in ipairs(rolls) do
        if e.me then
            rec.my, rec.mr = e.s, e.r
            if e.w then rec.mw = true end
        end
    end
end

-------------------------------------------------------------------------------
--  Live rolls (what the roll window shows)
-------------------------------------------------------------------------------
ns.live = {}

local function LiveEntry(rec)
    for _, e in ipairs(ns.live) do
        if e.rec == rec then return e end
    end
    local e = { rec = rec, seen = GetTime() }
    tinsert(ns.live, e)
    return e
end

local function ReadTimer(e, info)
    local start, duration = Plain(info.startTime, "number"), Plain(info.duration, "number")
    if not (start and duration and duration > 0) then return end
    -- Some builds report milliseconds.
    if duration > 1000 then start, duration = start / 1000, duration / 1000 end
    e.start, e.dur = start, duration
end

-- Empties the roll window: after a dungeon, on leaving the group, or when the
-- game clears its loot history. Drops from before stay out, even if the game
-- reports them again (after a /reload, for example); the history keeps them all.
function ns.ClearLive()
    wipe(ns.live)
    if DB then DB.liveSince = time() end
    ns.Notify()
end

local function OnDrop(encounterID, lootListID, quiet)
    if not (DB and C_LootHistory and C_LootHistory.GetSortedInfoForDrop) then return end
    encounterID, lootListID = Plain(encounterID, "number"), Plain(lootListID, "number")
    if not (encounterID and lootListID) then return end
    local ok, info = pcall(C_LootHistory.GetSortedInfoForDrop, encounterID, lootListID)
    if not ok or type(info) ~= "table" then return end
    local link = Plain(info.itemHyperlink, "string")
    if not link or not link:find("|H", 1, true) then return end

    local now = time()
    local key = encounterID .. ":" .. lootListID
    local k = DB.keys[key]
    local rec = k and k.link == link and byId[k.id]
    if rec and now - rec.t > KEY_TTL then rec = nil end
    local isNew = not rec
    if isNew then
        local v = EnsureVisit(now)
        rec = { id = DB.nextId, t = now, v = v.id, link = link }
        DB.nextId = DB.nextId + 1
        tinsert(DB.rolls, rec)
        byId[rec.id] = rec
        DB.keys[key] = { id = rec.id, link = link, t = now }
        ns.FillItem(rec)
        rec.ah = ns.AHLookup(ns.ItemID(rec), rec.link)   -- AH price at the time of the drop
        PruneOld()
    else
        local v = visitById[rec.v]
        if v then v.last = max(v.last, now) end
    end
    ReadRolls(rec, info, quiet)

    -- Rolls from before the roll window was last emptied only go to the history.
    if rec.t < (DB.liveSince or 0) then
        ns.Notify()
        return
    end
    local e = LiveEntry(rec)
    ReadTimer(e, info)
    if rec.done then
        e.settled = e.settled or GetTime()
    else
        e.settled = nil
    end
    if isNew and not quiet and not rec.done and (DB.opts.liveStay or 5) > 0 and ns.Live then
        ns.Live:Open()
    end
    ns.Notify()
end

local function OnEncounter(encounterID, quiet)
    encounterID = Plain(encounterID, "number")
    if not (encounterID and C_LootHistory and C_LootHistory.GetSortedDropsForEncounter) then return end
    local ok, drops = pcall(C_LootHistory.GetSortedDropsForEncounter, encounterID)
    if not ok or type(drops) ~= "table" then return end
    for _, drop in ipairs(drops) do
        OnDrop(encounterID, drop.lootListID, quiet)
    end
end

-- After a /reload the game still knows the open drops: pick them up again.
local function SyncAll()
    if not (C_LootHistory and C_LootHistory.GetAllEncounterInfos) then return end
    local ok, encounters = pcall(C_LootHistory.GetAllEncounterInfos)
    if not ok or type(encounters) ~= "table" then return end
    for _, enc in ipairs(encounters) do
        OnEncounter(enc.encounterID, true)
    end
end

-------------------------------------------------------------------------------
--  Sums used by both windows
-------------------------------------------------------------------------------
function ns.Status(rec)
    if rec.ap then return "|cff9a9a9a" .. L["Everyone passed"] .. "|r" end
    if rec.win then
        local label = rec.ws and ns.StateInfo(rec.ws).label or ""
        return format(L["%s won with %s %s"], ns.ClassName(rec.win, rec.wc), label, rec.wr and tostring(rec.wr) or "")
    end
    local waitingOn, leader = 0, nil
    for _, e in ipairs(rec.rolls or {}) do
        if e.s == S.NONE then waitingOn = waitingOn + 1 end
        if e.r and not leader then leader = e end
    end
    if leader and waitingOn > 0 then
        return format(L["%s leads with %d, waiting on %d"], ns.ClassName(leader.n, leader.c), leader.r, waitingOn)
    elseif leader then
        return format(L["%s leads with %d"], ns.ClassName(leader.n, leader.c), leader.r)
    elseif waitingOn > 0 then
        return "|cff9a9a9a" .. format(L["Waiting on %d"], waitingOn) .. "|r"
    end
    return "|cff9a9a9a" .. L["Rolling..."] .. "|r"
end

-- items, visits, won, gold won, vendor value of all, need, greed, pass
function ns.Sum(recs)
    local t = { items = 0, visits = 0, won = 0, gold = 0, ah = 0, all = 0, allAH = 0, need = 0, greed = 0, pass = 0 }
    local seen = {}
    for _, rec in ipairs(recs) do
        t.items = t.items + 1
        if not seen[rec.v] then seen[rec.v] = true; t.visits = t.visits + 1 end
        t.all = t.all + (rec.sell or 0)
        local ah = ns.AH(rec) or 0
        t.allAH = t.allAH + ah
        if rec.mw then
            t.won = t.won + 1
            t.gold = t.gold + (rec.sell or 0)
            t.ah = t.ah + ah
        end
        if rec.my == S.NEED or rec.my == S.OFF then t.need = t.need + 1
        elseif rec.my == S.GREED or rec.my == S.XMOG then t.greed = t.greed + 1
        elseif rec.my == S.PASS then t.pass = t.pass + 1 end
    end
    return t
end

-------------------------------------------------------------------------------
--  Test rolls (window preview) and demo history
-------------------------------------------------------------------------------
local DEMO_ITEMS = { 12640, 11815, 13965, 13209, 14047, 4306, 2589, 7005 }
local DEMO_PLAYERS = {
    { "Syntux", "PALADIN" }, { "Wenokah", "PRIEST" }, { "Aldrin", "WARRIOR" },
    { "Apnotix", "MAGE" }, { "Mirelle", "ROGUE" },
}
local DEMO_PLACES = { "Razorfen Downs", "Scarlet Monastery", "Uldaman", "Stranglethorn Vale" }

local function WithItems(ids, done)
    local left = #ids
    local links = {}
    local function finish()
        for i, id in ipairs(ids) do
            links[i] = links[i] or select(2, GetItemInfo(id)) or ("item:" .. id)
        end
        done(links)
    end
    if not (Item and Item.CreateFromItemID) then return finish() end
    local finished = false
    for i, id in ipairs(ids) do
        Item:CreateFromItemID(id):ContinueOnItemLoad(function()
            links[i] = select(2, GetItemInfo(id))
            left = left - 1
            if left == 0 and not finished then finished = true; finish() end
        end)
    end
    C_Timer.After(3, function()
        if not finished then finished = true; finish() end
    end)
end

local function FakeRolls(rec, progress)
    local me = ns.MyName() or "You"
    local _, myClass = UnitClass("player")
    local players = { { me, myClass, true } }
    for i = 1, 4 do players[#players + 1] = DEMO_PLAYERS[i + 1] end
    local rolls = {}
    for i, p in ipairs(players) do
        local seed = (rec.id * 7 + i * 13) % 100
        local state = S.NONE
        if progress >= i then
            state = (seed % 5 == 0) and S.PASS or ((seed % 3 == 0) and S.NEED or S.GREED)
        end
        rolls[i] = { n = p[1], c = p[2], s = state, me = p[3] or nil }
        if state ~= S.NONE and state ~= S.PASS and progress > #players then
            rolls[i].r = (seed * 37 + 11) % 100 + 1
        end
    end
    -- Need beats Greed, then the higher roll.
    sort(rolls, function(a, b)
        local function rank(e)
            if e.s == S.NEED then return 1 elseif e.s == S.GREED then return 2 elseif e.s == S.PASS then return 3 end
            return 4
        end
        if rank(a) ~= rank(b) then return rank(a) < rank(b) end
        return (a.r or 0) > (b.r or 0)
    end)
    rec.rolls = rolls
    Touch(rec)
    rec.win, rec.wc, rec.ws, rec.wr, rec.mw, rec.ap, rec.done = nil, nil, nil, nil, nil, nil, nil
    if progress > #players then
        local first = rolls[1]
        if first.s == S.PASS then
            rec.ap = true
        else
            first.w = true
            rec.win, rec.wc, rec.ws, rec.wr = first.n, first.c, first.s, first.r
            rec.mw = first.me
        end
        rec.done = true
    end
    for _, e in ipairs(rolls) do
        if e.me then rec.my, rec.mr = e.s, e.r end
    end
end

local testTickers = {}

-- Removes the preview rolls from the roll window (they are never in the history).
function ns.ClearTest()
    for _, t in ipairs(testTickers) do t:Cancel() end
    wipe(testTickers)
    for i = #ns.live, 1, -1 do
        if ns.live[i].rec.test then tremove(ns.live, i) end
    end
    ns.Print(L["Test rolls removed."])
    ns.Notify()
end

function ns.TestRolls()
    WithItems({ DEMO_ITEMS[1], DEMO_ITEMS[2], DEMO_ITEMS[4] }, function(links)
        for i, link in ipairs(links) do
            local rec = { id = 900000 + i, t = time(), v = 0, link = link, test = true }
            ns.FillItem(rec)
            FakeRolls(rec, 0)
            local e = LiveEntry(rec)
            e.start, e.dur = GetTime(), 30 + i * 8
            local step = 0
            local ticker
            ticker = C_Timer.NewTicker(1.2 + i * 0.4, function()
                step = step + 1
                FakeRolls(rec, step)
                if rec.done then
                    e.settled = GetTime()
                    ticker:Cancel()
                end
                ns.Notify()
            end)
            testTickers[#testTickers + 1] = ticker
        end
        if ns.Live then ns.Live:Open() end
        ns.Notify()
    end)
end

local DEMO_GUILDS = { Wenokah = "Nachtwache", Aldrin = "Nachtwache", Apnotix = "Sturmfels" }

function ns.AddDemo()
    for _, p in ipairs(DEMO_PLAYERS) do
        if not DB.players[p[1]] then DB.players[p[1]] = { c = p[2], g = DEMO_GUILDS[p[1]], demo = true } end
    end
    WithItems(DEMO_ITEMS, function(links)
        local now = time()
        local n = 0
        for day = 0, 2 do
            for p = 1, (day == 1 and 2 or 1) do
                local place = DEMO_PLACES[((day + p) % #DEMO_PLACES) + 1]
                local start = now - day * 86400 - p * 5400
                local v = { id = DB.nextVisit, key = "demo:" .. place, place = place, inst = true, t = start, last = start, demo = true,
                    money = math.random(2000, 90000) }
                DB.nextVisit = DB.nextVisit + 1
                tinsert(DB.visits, v)
                visitById[v.id] = v
                for i = 1, 6 do
                    n = n + 1
                    local rec = { id = DB.nextId, t = start + i * 240, v = v.id, link = links[(n % #links) + 1], demo = true }
                    DB.nextId = DB.nextId + 1
                    ns.FillItem(rec)
                    FakeRolls(rec, 99)
                    v.last = rec.t
                    tinsert(DB.rolls, rec)
                    byId[rec.id] = rec
                end
            end
        end
        sort(DB.rolls, function(a, b) return a.t < b.t end)
        ns.Print(L["Demo data added. /rolls cleardemo removes it."])
        ns.Notify()
    end)
end

function ns.ClearDemo()
    for i = #DB.rolls, 1, -1 do
        if DB.rolls[i].demo then byId[DB.rolls[i].id] = nil; tremove(DB.rolls, i) end
    end
    for i = #DB.visits, 1, -1 do
        if DB.visits[i].demo then visitById[DB.visits[i].id] = nil; tremove(DB.visits, i) end
    end
    ns.Print(L["Demo data removed."])
    ns.Notify()
end

function ns.ClearHistory()
    wipe(DB.rolls); wipe(DB.visits); wipe(DB.keys); wipe(byId); wipe(visitById); wipe(ns.live)
    DB.cur = nil
    ns.Print(L["History cleared."])
    ns.Notify()
end

-- Everyone you rolled with since a time: runs together, items won, their vendor
-- and AH value. Guild and class come from the group roster (DB.players).
function ns.PlayerStats(since)
    since = since or 0
    local me = ns.MyName()
    local players, list = {}, {}
    local function P(name, class)
        local p = players[name]
        if not p then
            local info = DB.players[name]
            p = { name = name, c = class or (info and info.c), g = info and info.g,
                runs = 0, items = 0, gold = 0, ah = 0, seen = {}, me = name == me or nil }
            players[name] = p
            list[#list + 1] = p
        end
        if class and not p.c then p.c = class end
        return p
    end
    local function Seen(p, vid)
        if not p.seen[vid] then
            p.seen[vid] = true
            p.runs = p.runs + 1
        end
    end
    for _, v in ipairs(DB.visits) do
        if v.t >= since and v.m then
            for name in pairs(v.m) do Seen(P(name), v.id) end
        end
    end
    for _, rec in ipairs(DB.rolls) do
        if rec.t >= since then
            for _, e in ipairs(rec.rolls or {}) do Seen(P(e.n, e.c), rec.v) end
            if rec.win then
                local p = P(rec.win, rec.wc)
                Seen(p, rec.v)
                p.items = p.items + 1
                p.gold = p.gold + (rec.sell or 0)
                p.ah = p.ah + (ns.AH(rec) or 0)
            end
        end
    end
    for _, p in ipairs(list) do p.seen = nil end
    return list
end

-- Head to head: only the runs where ALL the given players were in the group
-- together count. A run one of them did without the others is left out.
function ns.CompareStats(names, since)
    since = since or 0
    local present = {}
    local function Mark(vid, name)
        local s = present[vid]
        if not s then
            s = {}
            present[vid] = s
        end
        s[name] = true
    end
    for _, v in ipairs(DB.visits) do
        if v.t >= since and v.m then
            for name in pairs(v.m) do Mark(v.id, name) end
        end
    end
    for _, rec in ipairs(DB.rolls) do
        if rec.t >= since then
            for _, e in ipairs(rec.rolls or {}) do Mark(rec.v, e.n) end
            if rec.win then Mark(rec.v, rec.win) end
        end
    end

    local common, runs, placeCount = {}, 0, {}
    for vid, s in pairs(present) do
        local all = true
        for _, name in ipairs(names) do
            if not s[name] then
                all = false
                break
            end
        end
        if all then
            common[vid] = true
            runs = runs + 1
            local v = visitById[vid]
            local place = v and v.place or L["Unknown"]
            placeCount[place] = (placeCount[place] or 0) + 1
        end
    end

    local me = ns.MyName()
    local byName, players = {}, {}
    for _, name in ipairs(names) do
        local info = DB.players[name]
        local p = { name = name, c = info and info.c, g = info and info.g, runs = runs,
            items = 0, gold = 0, ah = 0, needs = 0, rolls = 0, rollSum = 0, best = 0,
            won = {}, me = name == me or nil }
        byName[name] = p
        players[#players + 1] = p
    end
    for _, rec in ipairs(DB.rolls) do
        if common[rec.v] then
            local w = rec.win and byName[rec.win]
            if w then
                w.items = w.items + 1
                w.gold = w.gold + (rec.sell or 0)
                w.ah = w.ah + (ns.AH(rec) or 0)
                w.won[#w.won + 1] = rec
            end
            for _, e in ipairs(rec.rolls or {}) do
                local p = byName[e.n]
                if p then
                    if e.c and not p.c then p.c = e.c end
                    if e.s == S.NEED or e.s == S.OFF then p.needs = p.needs + 1 end
                    if e.r then
                        p.rolls = p.rolls + 1
                        p.rollSum = p.rollSum + e.r
                        if e.r > p.best then p.best = e.r end
                    end
                end
            end
        end
    end

    local places = {}
    for place, n in pairs(placeCount) do places[#places + 1] = { place = place, n = n } end
    sort(places, function(a, b)
        if a.n ~= b.n then return a.n > b.n end
        return a.place < b.place
    end)
    return { runs = runs, places = places, players = players }
end

-- Gold won per place, for chat and the stats page.
function ns.GoldByPlace(recs)
    local places, list = {}, {}
    for _, rec in ipairs(recs) do
        local v = visitById[rec.v]
        local place = v and v.place or L["Unknown"]
        local p = places[place]
        if not p then
            p = { place = place, runs = 0, won = 0, gold = 0, ah = 0, items = 0, seen = {} }
            places[place] = p
            list[#list + 1] = p
        end
        p.items = p.items + 1
        if not p.seen[rec.v] then p.seen[rec.v] = true; p.runs = p.runs + 1 end
        if rec.mw then
            p.won = p.won + 1
            p.gold = p.gold + (rec.sell or 0)
            p.ah = p.ah + (ns.AH(rec) or 0)
        end
    end
    sort(list, function(a, b)
        if a.gold ~= b.gold then return a.gold > b.gold end
        return a.place < b.place
    end)
    return list
end

function ns.PrintGold()
    ns.Print(L["Gold won per place:"])
    local total = 0
    for _, p in ipairs(ns.GoldByPlace(DB.rolls)) do
        total = total + p.gold
        print(format("  %s: %s  (%s, %s)", p.place, ns.MoneyPlain(p.gold),
            format(L["won %d"], p.won), p.runs == 1 and L["1 run"] or format(L["%d runs"], p.runs)))
    end
    print(format("  |cffffffff%s:|r %s", L["Total"], ns.MoneyPlain(total)))
end

-------------------------------------------------------------------------------
--  Slash commands and addon compartment
-------------------------------------------------------------------------------
StaticPopupDialogs["NIBBELZLOOT_RESET"] = {
    text = L["Delete the whole roll history?"],
    button1 = YES, button2 = NO,
    OnAccept = function() ns.ClearHistory() end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

local function Help()
    ns.Print(L["Commands:"])
    print("  /rolls  (/nl) - " .. L["toggle the loot roll window"])
    print("  /rolls options - " .. L["open the options"])
    print("  /rolls history  (/rollhistory) - " .. L["open the roll history"])
    print("  /rolls players - " .. L["group stats: who won how much"])
    print("  /rolls battle - " .. L["loot battle: tip who wins each category"])
    print("  /rolls gold - " .. L["gold won per dungeon in chat"])
    print("  /rolls test | cleartest - " .. L["preview the window with fake rolls / remove them"])
    print("  /rolls share  (/fairshare) - " .. L["fair share: who gives whom how much"])
    print("  /rolls demo | cleardemo - " .. L["add / remove demo history"])
    print("  /rolls auto - " .. L["open the window on new rolls"])
    print("  /rolls scale 0.8-1.5 - " .. L["window size"])
    print("  /rolls minimap - " .. L["show / hide the minimap button"])
    print("  /rolls reset - " .. L["delete the history"])
end

SLASH_NIBBELZLOOT1 = "/rolls"
SLASH_NIBBELZLOOT2 = "/nibbelz"
SlashCmdList.NIBBELZLOOT = function(msg)
    local cmd, arg = (msg or ""):lower():match("^%s*(%S*)%s*(.-)%s*$")
    if cmd == "" then
        ns.Live:Toggle()
    elseif cmd == "history" or cmd == "h" then
        ns.History:Toggle()
    elseif cmd == "battle" or cmd == "duel" then
        ns.Battle:Command()
    elseif cmd == "group" or cmd == "players" or cmd == "stats" then
        ns.GroupStats:Toggle()
    elseif cmd == "options" or cmd == "config" or cmd == "opt" then
        ns.Options:Toggle()
    elseif cmd == "gold" then
        ns.PrintGold()
    elseif cmd == "test" then
        ns.TestRolls()
    elseif cmd == "cleartest" then
        ns.ClearTest()
    elseif cmd == "share" or cmd == "fair" then
        ns.Share:Toggle()
    elseif cmd == "demo" then
        ns.AddDemo()
    elseif cmd == "cleardemo" then
        ns.ClearDemo()
    elseif cmd == "auto" then
        if (DB.opts.liveStay or 5) > 0 then
            DB.opts.liveStayLast = DB.opts.liveStay
            DB.opts.liveStay = 0
        else
            DB.opts.liveStay = DB.opts.liveStayLast or 5
        end
        ns.Print(format(L["Auto-show on new rolls: %s"], DB.opts.liveStay > 0 and L["on"] or L["off"]))
    elseif cmd == "scale" then
        local s = tonumber(arg)
        if s then
            DB.opts.scale = min(1.5, max(0.6, s))
            ns.Live:ApplyScale()
            ns.History:ApplyScale()
            ns.GroupStats:ApplyScale()
            ns.Battle:ApplyScale()
            ns.Share:ApplyScale()
        end
        ns.Print(format(L["Scale: %s"], tostring(DB.opts.scale)))
    elseif cmd == "minimap" then
        ns.Minimap:Toggle()
    elseif cmd == "reset" then
        StaticPopup_Show("NIBBELZLOOT_RESET")
    else
        Help()
    end
    ns.Options:Sync()
end

-- /nl: the loot roll window. Only if no other addon (or the game) already uses /nl.
local function SlashTaken(cmd)
    for key in pairs(SlashCmdList) do
        for i = 1, 10 do
            local v = _G["SLASH_" .. key .. i]
            if v == nil then break end
            if type(v) == "string" and v:lower() == cmd then return key end
        end
    end
end
do
    local owner = SlashTaken("/nl")
    if owner and owner ~= "NIBBELZLOOTNL" then
        C_Timer.After(5, function() ns.Print(format(L["/nl is already used by %s - use /rolls instead."], owner)) end)
    else
        SLASH_NIBBELZLOOTNL1 = "/nl"
        SlashCmdList.NIBBELZLOOTNL = function() ns.Live:Toggle() end
    end
end

SLASH_NIBBELZLOOTSHARE1 = "/fairshare"
SlashCmdList.NIBBELZLOOTSHARE = function() ns.Share:Toggle() end

SLASH_NIBBELZLOOTBATTLE1 = "/lootbattle"
SlashCmdList.NIBBELZLOOTBATTLE = function() ns.Battle:Command() end

SLASH_NIBBELZLOOTHISTORY1 = "/rollhistory"
SlashCmdList.NIBBELZLOOTHISTORY = function() ns.History:Toggle() end

function NibbelzLoot_OnAddonCompartmentClick(_, button)
    if IsControlKeyDown() then
        ns.GroupStats:Toggle()
    elseif IsAltKeyDown() then
        ns.Battle:Command()
    elseif button == "RightButton" then
        ns.Live:Toggle()
    elseif IsShiftKeyDown() then
        ns.History:Toggle()   -- Shift + left-click: roll history
    else
        ns.Options:Toggle()   -- left-click: options
    end
end

function NibbelzLoot_OnAddonCompartmentEnter(_, frame)
    GameTooltip:SetOwner(frame or UIParent, "ANCHOR_LEFT")
    ns.FillTooltip(GameTooltip)
    GameTooltip:Show()
end

function NibbelzLoot_OnAddonCompartmentLeave()
    GameTooltip:Hide()
end

-------------------------------------------------------------------------------
--  Events
-------------------------------------------------------------------------------
local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("ZONE_CHANGED_NEW_AREA")
events:RegisterEvent("GROUP_LEFT")
events:RegisterEvent("GROUP_ROSTER_UPDATE")
events:RegisterEvent("CHAT_MSG_MONEY")
events:RegisterEvent("PLAYER_MONEY")
for _, ev in ipairs({ "LOOT_HISTORY_UPDATE_DROP", "LOOT_HISTORY_UPDATE_ENCOUNTER", "LOOT_HISTORY_CLEAR_HISTORY" }) do
    pcall(events.RegisterEvent, events, ev)
end

events:SetScript("OnEvent", function(_, event, a1, a2)
    if event == "ADDON_LOADED" then
        if a1 ~= ADDON then return end
        InitDB()
        ns.St.ApplyTheme(DB.opts.theme)   -- before any window is built
        if ns.Live then ns.Live:Init() end
        if ns.History then ns.History:Init() end
        if ns.GroupStats then ns.GroupStats:Init() end
        if ns.Minimap then ns.Minimap:Init() end
        if ns.Share then ns.Share:Init() end
        if ns.Battle then ns.Battle:Init() end
        if ns.Options then ns.Options:Init() end
    elseif event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA" then
        UpdateContext()
        if event == "PLAYER_ENTERING_WORLD" then
            SyncAll()
            lastMoney = GetMoney()
        end
        OnRoster()
        ns.Notify()
    elseif event == "GROUP_ROSTER_UPDATE" then
        ns.Debounce("coreRoster", 1, OnRoster)
    elseif event == "CHAT_MSG_MONEY" then
        if DB then OnMoneyChat(a1) end
    elseif event == "PLAYER_MONEY" then
        OnPlayerMoney()
    elseif event == "LOOT_HISTORY_UPDATE_DROP" then
        OnDrop(a1, a2)
    elseif event == "LOOT_HISTORY_UPDATE_ENCOUNTER" then
        OnEncounter(a1)
    elseif event == "LOOT_HISTORY_CLEAR_HISTORY" or event == "GROUP_LEFT" then
        ns.ClearLive()
    end
end)
