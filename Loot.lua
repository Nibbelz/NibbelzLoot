-- Loot.lua: who in the group looted what, read from the game's loot lines
-- ("X receives loot: [item]x2."), with each item's quality, vendor and AH value.
-- The fair share window and the loot battle listen to it. Also: ns.Settle, the
-- "who hands whom how much" sum both of them use.
local _, ns = ...

local floor, min, sort, tinsert = math.floor, math.min, table.sort, table.insert
local Plain = ns.Plain

local GetItemInfo = (C_Item and C_Item.GetItemInfo) or _G.GetItemInfo
local GetItemInfoInstant = (C_Item and C_Item.GetItemInfoInstant) or _G.GetItemInfoInstant

local function Short(name)
    if not name then return nil end
    if Ambiguate then return Ambiguate(name, "short") end
    return (name:gsub("%-.*$", ""))
end

-- The client's own loot lines turned into patterns (works in every language).
local PATTERNS = {}
local function AddPattern(global, isSelf, hasCount)
    local text = _G[global]
    if type(text) ~= "string" then return end
    local pattern = text:gsub("[%(%)%.%+%-%*%?%[%]%^%$]", "%%%0")
        :gsub("%%%d*%%?%$?s", "(.+)")
        :gsub("%%%d*%%?%$?d", "(%%d+)")
    tinsert(PATTERNS, { "^" .. pattern .. "$", isSelf, hasCount })
end
AddPattern("LOOT_ITEM_SELF_MULTIPLE", true, true)
AddPattern("LOOT_ITEM_SELF", true, false)
AddPattern("LOOT_ITEM_MULTIPLE", false, true)
AddPattern("LOOT_ITEM", false, false)

local listeners = {}

-- fn(name, info): info = { link, count, quality, sell (all of them), ah (all of them) }
function ns.OnGroupLoot(fn)
    listeners[#listeners + 1] = fn
end

local function Dispatch(name, link, count)
    local function Apply()
        local _, _, quality, _, _, _, _, _, _, _, sell = GetItemInfo(link)
        local ah = ns.AHLookup((GetItemInfoInstant(link)), link)
        local info = { link = link, count = count, quality = quality,
            sell = (sell or 0) * count, ah = (ah or 0) * count }
        for i = 1, #listeners do listeners[i](name, info) end
    end
    if GetItemInfo(link) or not (Item and Item.CreateFromItemLink) then
        Apply()
    else
        local ok, item = pcall(Item.CreateFromItemLink, Item, link)
        if ok and item and not item:IsItemEmpty() then item:ContinueOnItemLoad(Apply) else Apply() end
    end
end

local function OnLoot(text)
    -- Solo nobody needs it: no fair share, no battle. Skip the work.
    if not (IsInGroup() or (ns.Battle and ns.Battle:Active())) then return end
    text = Plain(text, "string")   -- the game hides some chat from addons in fights
    if not text then return end
    for _, p in ipairs(PATTERNS) do
        local a, c, d = text:match(p[1])
        if a then
            local name, link, count
            if p[2] then
                name, link, count = ns.MyName(), a, p[3] and c or 1
            else
                name, link, count = ns.Name(a), c, p[3] and d or 1
            end
            if name and link and link:find("|Hitem:", 1, true) then
                Dispatch(name, link, tonumber(count) or 1)
            end
            return
        end
    end
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("CHAT_MSG_LOOT")
ev:SetScript("OnEvent", function(_, _, text) OnLoot(text) end)

-------------------------------------------------------------------------------
--  Hiding the game's roll lines in chat ("X has selected Need for: [item]",
--  "Greed Roll - 54 for [item] by X", "X won: [item]", "Everyone passed on...").
--  The roll window shows all of that. Built from the client's own LOOT_ROLL_*
--  texts, so it works in every language; other loot lines stay.
-------------------------------------------------------------------------------
local ROLL_PATTERNS
local function BuildRollPatterns()
    ROLL_PATTERNS = {}
    local seen = {}
    local function Add(text)
        if type(text) ~= "string" or text == "" or seen[text] then return end
        seen[text] = true
        -- Only real chat lines: a placeholder and enough fixed words around it.
        -- (A bare "%s" would otherwise hide every loot line.)
        local fixed = text:gsub("%%%d*%$?[sd]", ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
        if not text:find("%", 1, true) or #fixed < 8 then return end
        local pattern = text:gsub("[%(%)%.%+%-%*%?%[%]%^%$]", "%%%0")
            :gsub("%%%d*%%?%$?s", ".+")
            :gsub("%%%d*%%?%$?d", "%%d+")
        ROLL_PATTERNS[#ROLL_PATTERNS + 1] = "^" .. pattern .. "$"
    end
    -- Every LOOT_ROLL_* text the client has (need, greed, pass, rolled, won...).
    pcall(function()
        for key, text in pairs(_G) do
            if type(key) == "string" and key:sub(1, 10) == "LOOT_ROLL_" then Add(text) end
        end
    end)
end

-- The game asks once per chat window for the same line: remember the last answer.
local lastText, lastHide = nil, false
local function RollLineFilter(_, _, text, ...)
    if not (ns.db and ns.db.opts.hideRollChat) then return false end
    if type(text) ~= "string" or (issecretvalue and issecretvalue(text)) then return false end
    if text == lastText then return lastHide end
    if not ROLL_PATTERNS then BuildRollPatterns() end
    local hide = false
    for i = 1, #ROLL_PATTERNS do
        if text:find(ROLL_PATTERNS[i]) then
            hide = true   -- true = don't show it
            break
        end
    end
    lastText, lastHide = text, hide
    return hide
end

local AddFilter = ChatFrame_AddMessageEventFilter
    or (ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter)
if AddFilter then AddFilter("CHAT_MSG_LOOT", RollLineFilter) end

-- Who hands whom how much. entries: { name, c, net } with net > 0 = gets money,
-- net < 0 = pays. Fewest hand-overs: the biggest payer to the biggest receiver.
function ns.Settle(entries)
    local payers, takers = {}, {}
    for _, e in ipairs(entries) do
        local net = floor(e.net + 0.5)
        if net < 0 then payers[#payers + 1] = { e = e, left = -net }
        elseif net > 0 then takers[#takers + 1] = { e = e, left = net } end
    end
    sort(payers, function(a, b) return a.left > b.left end)
    sort(takers, function(a, b) return a.left > b.left end)
    local transfers = {}
    local i, j = 1, 1
    while payers[i] and takers[j] do
        local amount = min(payers[i].left, takers[j].left)
        if amount > 0 then
            transfers[#transfers + 1] = { from = payers[i].e.name, fc = payers[i].e.c,
                to = takers[j].e.name, tc = takers[j].e.c, amount = amount }
        end
        payers[i].left = payers[i].left - amount
        takers[j].left = takers[j].left - amount
        if payers[i].left <= 0 then i = i + 1 end
        if takers[j].left <= 0 then j = j + 1 end
    end
    return transfers
end

-- Plain chat money: 12g 3s 4c
function ns.ChatMoney(copper)
    copper = floor(copper or 0)
    local g, s, c = floor(copper / 10000), floor(copper / 100) % 100, copper % 100
    if g > 0 then return string.format("%dg %ds %dc", g, s, c) end
    if s > 0 then return string.format("%ds %dc", s, c) end
    return string.format("%dc", c)
end

-- Group chat channel for the current group, or nil.
function ns.GroupChannel()
    if IsInGroup and LE_PARTY_CATEGORY_INSTANCE and IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then return "INSTANCE_CHAT" end
    if IsInRaid and IsInRaid() then return "RAID" end
    if IsInGroup and IsInGroup() then return "PARTY" end
end

function ns.GroupUnits()
    local units = { "player" }
    if IsInRaid and IsInRaid() then
        for i = 1, GetNumGroupMembers() do units[#units + 1] = "raid" .. i end
    elseif IsInGroup and IsInGroup() then
        for i = 1, GetNumSubgroupMembers() do units[#units + 1] = "party" .. i end
    end
    return units
end
