-- Reals.lua: Tarnished Undermine Reals. Every dungeon boss from Sunken Temple /
-- Blackrock Depths on gives them once per day (last bosses 3, the others 1; mini
-- bosses none, per Wowhead). This file notes which boss you already looted today
-- (per character, until the daily reset) and shows it in its own window (/reals).
-- Detection: the loot window (the corpse the Real lies on), else the last boss
-- killed when the currency goes up.
-- Boss lists: NaowhForever_DungeonJournal's dungeon data (NPC and encounter IDs).
local _, ns = ...
local St, L = ns.St, ns.L

local format, floor, max, min = string.format, math.floor, math.max, math.min
local tinsert = table.insert

local R = {}
ns.Reals = R

local CURRENCY = 3469
local ITEM = 226404

-- { dungeon, instance map ID, wing (or nil), bosses = { { npc(s), name, encounters, last, optional } } }
local DUNGEONS = {
    { "Sunken Temple", 109, nil, {
        { 8580, "Atal'alarion", { 3582, 2814 } },
        { 5721, "Dreamscythe", { 3588, 486 } },
        { 5720, "Weaver", { 3587, 487 } },
        { 5710, "Jammal'an the Prophet", { 3589, 488 } },
        { 5711, "Ogom the Wretched" },
        { 5719, "Morphaz", { 3586, 490 } },
        { 5722, "Hazzas", { 3585, 491 } },
        { 5709, "Shade of Eranikus", { 3584, 493 }, true },
        { 8443, "Avatar of Hakkar", { 3583, 492 }, false, true },
    } },
    { "Blackrock Depths", 230, nil, {
        { 9018, "High Interrogator Gerstahn", { 227 } },
        { 9025, "Lord Roccor", { 228 } },
        { 9319, "Houndmaster Grebmar", { 229 } },
        { { 9031, 9029, 9027, 9028, 9032, 9030 }, "Ring of Law" },
        { 9024, "Pyromancer Loregrain", { 231 } },
        { 9017, "Lord Incendius", { 232 } },
        { 9041, "Warder Stilgiss", { 233 } },
        { 9042, "Verek" },
        { 9056, "Fineous Darkvire", { 234 } },
        { 9016, "Bael'Gar", { 235 } },
        { 9033, "General Angerforge", { 236 } },
        { 8983, "Golem Lord Argelmach", { 237 } },
        { 9537, "Hurley Blackbreath", { 238 } },
        { 9502, "Phalanx", { 239 } },
        { 9543, "Ribbly Screwspigot", { 240 } },
        { 9499, "Plugger Spazzring", { 241 } },
        { 9156, "Ambassador Flamelash", { 242 } },
        { 9938, "Magmus", { 244 } },
        { 9019, "Emperor Dagran Thaurissan", { 2790 }, true },
        { 8929, "Princess Moira Bronzebeard", { 2789 }, false, true },
    } },
    { "Dire Maul", 429, "East", {
        { 14354, "Pusillin", { 2792 } },
        { 11490, "Zevrim Thornhoof", { 343 } },
        { 13280, "Hydrospawn", { 344 } },
        { 14327, "Lethtendris", { 345 } },
        { 11492, "Alzzin the Wildshaper", { 346 }, true },
        { 16097, "Isalien", nil, false, true },
    } },
    { "Dire Maul", 429, "West", {
        { 11489, "Tendris Warpwood", { 350 } },
        { 11488, "Illyanna Ravenoak", { 347 } },
        { 11487, "Magister Kalendris", { 348 } },
        { 11496, "Immol'thar", { 349 } },
        { 11486, "Prince Tortheldrin", { 361 }, true },
        { 14506, "Lord Hel'nurath", { 2793 }, false, true },
        { 14690, "Revanchion", nil, false, true },
    } },
    { "Dire Maul", 429, "North", {
        { 14326, "Guard Mol'dar", { 362 } },
        { 14322, "Stomper Kreeg", { 363 } },
        { 14321, "Guard Fengus", { 364 } },
        { 14323, "Guard Slip'kik", { 365 } },
        { 14325, "Captain Kromcrush", { 366 } },
        { 11501, "King Gordok", { 368 }, true },
        { 14324, "Cho'Rush the Observer", { 367 }, false, true },
    } },
    { "Lower Blackrock Spire", 229, nil, {
        { 9196, "Highlord Omokk", { 267 } },
        { 9236, "Shadow Hunter Vosh'gajin", { 268 } },
        { 9237, "War Master Voone", { 269 } },
        { 10596, "Mother Smolderweb", { 270 } },
        { 10584, "Urok Doomhowl", { 271 } },
        { 9736, "Quartermaster Zigris", { 272 } },
        { 10268, "Gizrul the Slavener", { 273 } },
        { 10220, "Halycon", { 274 } },
        { 9568, "Overlord Wyrmthalak", { 275 }, true },
        { 16080, "Mor Grayhoof", nil, false, true },
    } },
    { "Upper Blackrock Spire", 229, nil, {
        { 9816, "Pyroguard Emberseer", { 3062 } },
        { 10264, "Solakar Flamewreath" },
        { 10899, "Goraluk Anvilcrack" },
        { 10339, "Gyth" },
        { 10429, "Warchief Rend Blackhand", { 3063 } },
        { 10430, "The Beast", { 3068 } },
        { 10363, "General Drakkisath", { 3069 }, true },
        { 16042, "Lord Valthalak", { 3070 }, false, true },
    } },
    { "Scholomance", 289, nil, {
        { 10503, "Jandice Barov", { 2804 } },
        { 11622, "Rattlegore", { 2811 } },
        { 10433, "Marduk Blackpool", { 2809 } },
        { 10432, "Vectus", { 2813 } },
        { 10508, "Ras Frostwhisper", { 2810 } },
        { 10505, "Instructor Malicia", { 2803 } },
        { 11261, "Doctor Theolen Krastinov", { 2802 } },
        { 10901, "Lorekeeper Polkelt", { 2808 } },
        { 10507, "The Ravenian", { 2812 } },
        { 10504, "Lord Alexei Barov", { 2807 } },
        { 10502, "Lady Illucia Barov", { 2806 } },
        { 1853, "Darkmaster Gandling", { 2801 }, true },
        { 10506, "Kirtonos the Herald", { 2805 }, false, true },
        { 16118, "Kormok", { 3055 }, false, true },
    } },
    { "Stratholme", 329, "Main Gate", {
        { 10808, "Timmy the Cruel", { 474 } },
        { 10516, "The Unforgiven", { 472 } },
        { 10558, "Hearthsinger Forresten", { 473 } },
        { 10997, "Cannon Master Willey", { 475 } },
        { 10811, "Archivist Galford", { 477 } },
        { 10813, "Balnazzar", { 478 }, true },
        { 11032, "Malor the Zealous", { 476 }, false, true },
        { 11058, "Ezra Grimm", { 2797 }, false, true },
        { 11143, "Postmaster Malown", { 2798 }, false, true },
        { 14684, "Balzaphon", nil, false, true },
    } },
    { "Stratholme", 329, "Service Entrance", {
        { 10435, "Magistrate Barthilas", { 482 } },
        { 10436, "Baroness Anastari", { 479 } },
        { 10437, "Nerub'enkan", { 480 } },
        { 10438, "Maleki the Pallid", { 481 } },
        { 10439, "Ramstein the Gorger", { 483 } },
        { 10440, "Baron Rivendare", { 484 }, true },
    } },
    { "Blackmaw Hold", 2974, nil, {
        { 247195, "Withermaw", { 3315 } },
        { 247206, "Impaan the Imprisoner", { 3316 } },
        { 247209, "Elder Shaman Bloodmane", { 3327 } },
        { 247198, "Bonesnout the Unbroken", { 3322 } },
        { 247234, "Varrox Bleakhoof", { 3334 } },
        { 247207, "Blackmaw Behemoth", { 3323 } },
        { 247231, "Unbound Spirit", { 3336 }, true },
    } },
    { "Shaper's Terrace", 3001, nil, {
        { 253201, "Titanosaur", { 3498 } },
        { 261813, "Venomridge", { 3501 } },
        { 261812, "Thunderhoof", { 3500 } },
        { 262127, "Direhorn Matriarch", { 3507 } },
        { 261974, "Cinder", { 3503 } },
        { 262081, "Bolt", { 3505 } },
        { 262297, "Snowtalon", { 3597 } },
        { 272561, "Vitrix", { 3600 } },
        { 253218, "Izha'Rel and Tor'Rel", { 3499 } },
        { 261809, "Nanaya", { 3502 }, true },
    } },
}

-- Lookups: NPC ID / encounter ID -> boss key (the first NPC ID).
local byNpc, byEncounter = {}, {}
for _, d in ipairs(DUNGEONS) do
    for _, b in ipairs(d[4]) do
        local npcs = type(b[1]) == "table" and b[1] or { b[1] }
        b.key = npcs[1]
        for _, id in ipairs(npcs) do byNpc[id] = b end
        for _, id in ipairs(b[3] or {}) do byEncounter[id] = b end
    end
end

-- The boss name in the client's language, from NaowhForever's journal when it has one.
local function BossName(b)
    local naowh = _G.NaowhForever
    local names = naowh and naowh.Journal and naowh.Journal.Names and naowh.Journal.Names.npcs
    return names and names[b.key] or b[2]
end

-------------------------------------------------------------------------------
--  Saved state (per character, valid until the daily reset)
-------------------------------------------------------------------------------
-- Start of the current game day (the last daily reset).
local function DayStart()
    local left = C_DateAndTime and C_DateAndTime.GetSecondsUntilDailyReset and C_DateAndTime.GetSecondsUntilDailyReset()
    left = ns.Plain(left, "number")
    if left then return time() + left - 86400 end
    local d = date("*t")
    return time({ year = d.year, month = d.month, day = d.day, hour = 0 })
end

local function CharKey()
    return ns.MyName() or "?"
end

local function Store()
    local db = ns.db
    db.reals = db.reals or {}
    local c = db.reals[CharKey()]
    if not c then
        c = { bosses = {} }
        db.reals[CharKey()] = c
    end
    -- A new day: forget yesterday's bosses.
    local start = DayStart()
    if (c.day or 0) < start - 60 then
        c.day = start
        c.bosses = {}
        c.reminded = {}
        c.total = 0
    end
    c.reminded = c.reminded or {}
    return c
end

-- When this boss gave you Reals today: { n = count, t = time } or nil.
function R:Looted(boss)
    return Store().bosses[boss.key]
end

local lastCommit = 0
local function Commit(boss, count, source)
    local c = Store()
    if boss then
        local e = c.bosses[boss.key]
        if e and source ~= "loot" then return end   -- already noted from the loot window
        c.bosses[boss.key] = { n = max(count or 1, e and e.n or 0), t = time() }
        -- This boss gives Reals: remember it for the reminder (all characters).
        if source == "loot" or source == "kill" then
            ns.db.realLearned = ns.db.realLearned or {}
            for _, id in ipairs(boss[3] or {}) do ns.db.realLearned[id] = boss.key end
        end
    end
    lastCommit = GetTime()
    if boss then R:Looting(boss) end
    R:Refresh()
end

-------------------------------------------------------------------------------
--  Detection
-------------------------------------------------------------------------------
local lastKill, lastKillAt = nil, 0
local seenGuid = {}

local function NpcFromGuid(guid)
    guid = ns.Plain(guid, "string")
    if not guid then return nil end
    local kind, _, _, _, _, id = strsplit("-", guid)
    if kind == "Creature" or kind == "Vehicle" then return tonumber(id) end
end

local function IsReal(slot)
    local link = ns.Plain(GetLootSlotLink(slot), "string")
    if link and (link:find("currency:" .. CURRENCY, 1, true) or link:find("item:" .. ITEM .. ":", 1, true)) then
        return true
    end
    local _, name = GetLootSlotInfo(slot)
    name = ns.Plain(name, "string")
    return name ~= nil and name:find("Undermine", 1, true) ~= nil
end

-- The loot window: a Real on a boss corpse = that boss is done for today.
local function ScanLoot()
    local n = ns.Plain(GetNumLootItems(), "number") or 0
    for slot = 1, n do
        -- Any loot window on the reminded boss's corpse ends the reminder.
        local src = GetLootSourceInfo and NpcFromGuid(GetLootSourceInfo(slot))
        if src then R:LootedNpc(src) end
        if IsReal(slot) then
            local _, _, qty = GetLootSlotInfo(slot)
            qty = ns.Plain(qty, "number") or 1
            local guid = GetLootSourceInfo and GetLootSourceInfo(slot)
            local npc = NpcFromGuid(guid)
            local boss = npc and byNpc[npc]
            if boss and not seenGuid[guid] then
                seenGuid[guid] = true
                Commit(boss, qty, "loot")
            end
        end
    end
end

-- The currency went up without a Real seen in a loot window: the last boss killed.
local function OnGain(change)
    if GetTime() - lastCommit < 5 then return end
    if lastKill and GetTime() - lastKillAt < 600 then
        -- Learn the boss only when the Real came soon after the kill.
        Commit(lastKill, change, GetTime() - lastKillAt < 180 and "kill" or "late")
        lastKill = nil
    end
end

-------------------------------------------------------------------------------
--  Reminder: after the day's first kill of a boss that drops Reals, a blinking
--  Real on screen until you loot the boss (or the set time runs out / right-click).
--  Movable, size and time adjustable, can be switched off (like the quest item icon).
-------------------------------------------------------------------------------
-- Encounters that drop a Real once a day: encounter ID -> the boss's NPC ID (whose
-- corpse you loot). The list as in NaowhForever's Undermine Real Reminder data.
local DROPS = {
    -- Blackrock Depths
    [234] = 9056, [232] = 9017, [238] = 9537, [239] = 9502, [236] = 9033, [237] = 8983,
    [242] = 9156, [244] = 9938, [2790] = 9019,
    -- Lower Blackrock Spire
    [267] = 9196, [268] = 9236, [269] = 9237, [270] = 10596, [271] = 10584, [273] = 10268,
    [274] = 10220, [275] = 9568,
    -- Upper Blackrock Spire
    [3062] = 9816, [3063] = 10429, [3068] = 10430, [3069] = 10363,
    -- Dire Maul
    [2792] = 14354, [345] = 14327, [344] = 13280, [343] = 11490, [346] = 11492, [368] = 11501,
    [350] = 11489, [348] = 11487, [347] = 11488, [349] = 11496, [361] = 11486,
    -- Scholomance
    [2809] = 10433, [2813] = 10432, [2802] = 11261, [2803] = 10505, [2808] = 10901, [2807] = 10504,
    [2812] = 10507, [2806] = 10502, [2805] = 10506, [2801] = 1853, [2804] = 10503, [2811] = 11622,
    [2810] = 10508,
    -- Stratholme
    [472] = 10516, [2798] = 11143, [474] = 10808, [475] = 10997, [477] = 10811, [482] = 10435,
    [480] = 10437, [481] = 10438, [479] = 10436, [483] = 10439, [484] = 10440,
    -- Blackmaw Hold (seen in game: Blackmaw Behemoth gives a Real)
    [3315] = 247195, [3316] = 247206, [3327] = 247209, [3322] = 247198, [3334] = 247234,
    [3323] = 247207, [3336] = 247231,
    -- Shaper's Terrace
    [3498] = 253201, [3501] = 261813, [3500] = 261812, [3507] = 262127, [3503] = 261974,
    [3505] = 262081, [3597] = 262297, [3600] = 272561, [3499] = 253218, [3502] = 261809,
}

-- Does this encounter drop a Real? The list above, plus bosses that gave you one
-- in game (learned: ns.db.realLearned, encounter ID -> NPC ID, for all characters).
local function DropNpc(id)
    if DROPS[id] then return DROPS[id] end
    local learned = ns.db and ns.db.realLearned
    return learned and learned[id]
end

local REAL_ICON = "Interface\\Icons\\INV_Misc_Coin_17"
local STAY = 61                  -- realIconTime: 1-60 seconds, STAY = until looted
local remind, remindHide = nil, 0
local pending = {}               -- NPC ID -> boss name: killed, not looted yet

local function Debug(msg)
    if ns.db and ns.db.opts.realDebug then ns.Print("|cff9a9a9a[Reals]|r " .. msg) end
end
local remindMoving = false

local function RealIcon()
    local ok, ci = pcall(C_CurrencyInfo.GetCurrencyInfo, CURRENCY)
    local icon = ok and type(ci) == "table" and ns.Plain(ci.iconFileID) or nil
    if not icon and C_Item and C_Item.GetItemIconByID then
        local okI, tex = pcall(C_Item.GetItemIconByID, ITEM)
        icon = okI and ns.Plain(tex) or nil
    end
    return icon or REAL_ICON
end

local function CreateReminder()
    local SIZE = 44   -- same look as the quest item icon (QuestMobs.lua)
    remind = CreateFrame("Button", "NibbelzLootRealReminder", UIParent)
    remind:SetSize(SIZE, SIZE)
    remind:SetFrameStrata("HIGH")
    remind:SetClampedToScreen(true)
    remind:SetMovable(true)
    remind:RegisterForDrag("LeftButton")
    remind:RegisterForClicks("RightButtonUp")
    remind:SetScript("OnDragStart", function(self) if remindMoving then self:StartMoving() end end)
    remind:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relPoint, x, y = self:GetPoint()
        ns.db.pos.realIcon = { point, relPoint, x, y }
    end)
    -- Right-click: dismiss.
    remind:SetScript("OnClick", function() if not remindMoving then R:HideReminder() end end)
    local p = ns.db.pos.realIcon
    if type(p) == "table" and p[1] then
        remind:SetPoint(p[1], UIParent, p[2], p[3], p[4])
    else
        remind:SetPoint("CENTER", UIParent, "CENTER", 0, 230)
    end
    remind.border = remind:CreateTexture(nil, "BACKGROUND")
    remind.border:SetPoint("TOPLEFT", -2, 2)
    remind.border:SetPoint("BOTTOMRIGHT", 2, -2)
    remind.border:SetColorTexture(St.Accent())
    remind.icon = remind:CreateTexture(nil, "ARTWORK")
    remind.icon:SetAllPoints()
    remind.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    remind.label = remind:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    remind.label:SetPoint("TOP", remind, "BOTTOM", 0, -4)
    remind.sub = remind:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    remind.sub:SetPoint("TOP", remind.label, "BOTTOM", 0, -2)
    remind.moveBg = remind:CreateTexture(nil, "BACKGROUND", nil, -1)
    remind.moveBg:SetPoint("TOPLEFT", -8, 8)
    remind.moveBg:SetPoint("BOTTOMRIGHT", 8, -40)
    local ar, ag, ab = St.Accent()
    remind.moveBg:SetColorTexture(ar, ag, ab, 0.25)
    -- Blink.
    local blink = remind:CreateAnimationGroup()
    blink:SetLooping("BOUNCE")
    local fade = blink:CreateAnimation("Alpha")
    fade:SetFromAlpha(1)
    fade:SetToAlpha(0.35)
    fade:SetDuration(0.6)
    remind.blink = blink
    remind:SetScript("OnUpdate", function(self)
        if not remindMoving and remindHide > 0 and GetTime() >= remindHide then R:HideReminder() end
    end)
    remind:Hide()
end

-- name: the boss to show under the icon (nil = the first one still pending).
function R:ShowReminder(name, preview)
    if not preview and ns.db.opts.realIcon == false then return end
    if not remind then CreateReminder() end
    if not name then
        local _, n = next(pending)
        name = n
    end
    remind:SetScale(ns.db.opts.realIconScale or 1)
    remind.icon:SetTexture(RealIcon())
    remind.label:SetText(L["Loot your Real!"])
    remind.sub:SetText(name or L["Boss"])
    local t = ns.db.opts.realIconTime or STAY
    remindHide = (preview or t >= STAY) and 0 or (GetTime() + t)
    remind.moveBg:SetShown(remindMoving)
    remind:EnableMouse(true)
    remind:Show()
    if remindMoving then remind.blink:Stop() else remind.blink:Play() end
end

function R:HideReminder(keepPending)
    if not keepPending then wipe(pending) end
    if remind then
        remind.blink:Stop()
        remind:Hide()
    end
end

-- A loot window on this NPC's corpse: that boss is looted, no need to remind any more.
function R:LootedNpc(npc)
    if not (npc and pending[npc]) then return end
    pending[npc] = nil
    Debug("looted " .. npc)
    if remindMoving then return end
    if next(pending) then
        R:ShowReminder()          -- another boss is still waiting
    else
        R:HideReminder()
    end
end

-- Kept for the loot detection (a Real seen on this boss).
function R:Looting(boss)
    local npcs = type(boss[1]) == "table" and boss[1] or { boss[1] }
    for _, npc in ipairs(npcs) do R:LootedNpc(npc) end
end

-- A boss died: on its first kill today, remind to loot the Real.
local function OnBossKill(id, name)
    local npc = DropNpc(id)
    if not npc then
        Debug(format("encounter %d (%s): drops no Real", id, tostring(name)))
        return
    end
    local c = Store()
    if c.reminded[id] then
        Debug(format("encounter %d (%s): already killed today", id, tostring(name)))
        return
    end
    c.reminded[id] = true
    local boss = byNpc[npc]
    pending[npc] = boss and BossName(boss) or name or "?"
    Debug(format("encounter %d (%s): reminder", id, tostring(name)))
    R:ShowReminder(pending[npc])
end

-- /reals test: show the reminder for a few seconds.
function R:TestReminder()
    R:ShowReminder(L["Boss"], true)
    remindHide = GetTime() + 8
end

-- /reals debug: print what happens on boss kills.
function R:ToggleDebug()
    ns.db.opts.realDebug = not ns.db.opts.realDebug or nil
    ns.Print("Reals debug: " .. (ns.db.opts.realDebug and "on" or "off"))
end

-- Options: the icon stays on screen and can be dragged until moving is switched off.
function R:SetReminderMoving(on)
    remindMoving = on
    if on then
        R:ShowReminder(nil, true)
    else
        R:HideReminder()
    end
    return remindMoving
end

function R:IsReminderMoving() return remindMoving end

function R:ApplyReminderScale()
    if remind then remind:SetScale(ns.db.opts.realIconScale or 1) end
end

local events = CreateFrame("Frame")
for _, ev in ipairs({ "LOOT_READY", "LOOT_OPENED", "ENCOUNTER_END", "CURRENCY_DISPLAY_UPDATE", "PLAYER_ENTERING_WORLD" }) do
    pcall(events.RegisterEvent, events, ev)
end
events:SetScript("OnEvent", function(_, event, a1, a2, a3, a4, a5)
    if not ns.db then return end
    if event == "LOOT_READY" or event == "LOOT_OPENED" then
        ScanLoot()
    elseif event == "ENCOUNTER_END" then
        local id, success = ns.Plain(a1, "number"), ns.Plain(a5)
        Debug(format("ENCOUNTER_END %s %s success=%s", tostring(id), tostring(ns.Plain(a2)), tostring(success)))
        if id and (success == 1 or success == true) then
            local boss = byEncounter[id]
            if boss then lastKill, lastKillAt = boss, GetTime() end
            OnBossKill(id, ns.Plain(a2, "string"))
        end
    elseif event == "CURRENCY_DISPLAY_UPDATE" then
        local id, change = ns.Plain(a1, "number"), ns.Plain(a3, "number")
        if id == CURRENCY and change and change > 0 then OnGain(change) end
        R:Refresh(true)
    elseif event == "PLAYER_ENTERING_WORLD" then
        wipe(seenGuid)
        if not remindMoving and not IsInInstance() then R:HideReminder() end   -- left the dungeon
        R:ResetFolds()   -- a new dungeon: it opens unfolded again
        R:Refresh(true)
    end
end)

-------------------------------------------------------------------------------
--  Window
-------------------------------------------------------------------------------
local W, H = 400, 520
local frame, list, info, hideCheck
local opened = {}   -- unfolded dungeons (by list index); all folded at first
local search = ""   -- dungeon or boss name (lower case)

function R:ResetFolds() wipe(opened) end

local zoneNames = {}
local function DungeonName(d)
    local name = zoneNames[d[2]]
    if not name then
        local ok, z = pcall(GetRealZoneText, d[2])
        z = ok and ns.Plain(z, "string") or nil
        name = (z and z ~= "") and z or d[1]
        zoneNames[d[2]] = name
    end
    if d[3] then return name .. " - " .. L[d[3]] end
    return name
end

local function CurrentInstance()
    local _, kind, _, _, _, _, _, id = GetInstanceInfo()
    if kind == "party" or kind == "raid" then return ns.Plain(id, "number") end
end

local function Countdown(sec)
    sec = max(0, floor(sec))
    local h, m = floor(sec / 3600), floor(sec % 3600 / 60)
    if h > 0 then return format("%dh %02dm", h, m) end
    return format("%dm", m)
end

local function Build()
    local hide = ns.db.opts.realsHideLooted
    local looted = Store().bosses   -- once per rebuild, not once per boss
    local here = CurrentInstance()
    local order = {}
    for i, d in ipairs(DUNGEONS) do order[#order + 1] = i end
    -- The dungeon you are in comes first.
    table.sort(order, function(a, b)
        local ha, hb = DUNGEONS[a][2] == here, DUNGEONS[b][2] == here
        if ha ~= hb then return ha end
        return a < b
    end)
    local rows, today, bossesDone = {}, 0, 0
    for _, i in ipairs(order) do
        local d = DUNGEONS[i]
        local done, total, got = 0, 0, 0
        for _, b in ipairs(d[4]) do
            local e = looted[b.key]
            if not b[5] then total = total + 1 end
            if e then
                done = done + (b[5] and 0 or 1)
                got = got + e.n
            end
        end
        today = today + got
        bossesDone = bossesDone + done
        -- Search: a matching dungeon shows all its bosses, else only the matching bosses.
        local dungeonHit = search == "" or DungeonName(d):lower():find(search, 1, true) ~= nil
            or d[1]:lower():find(search, 1, true) ~= nil
        local bosses = {}
        for _, b in ipairs(d[4]) do
            local e = looted[b.key]
            local hit = dungeonHit or BossName(b):lower():find(search, 1, true) ~= nil
                or b[2]:lower():find(search, 1, true) ~= nil
            if hit and not (hide and e) then bosses[#bosses + 1] = { kind = "boss", h = 22, b = b, e = e } end
        end
        if dungeonHit or #bosses > 0 then
            -- While searching, matches are unfolded; the dungeon you are in is unfolded
            -- unless you folded it; otherwise only what you opened.
            local open = (search ~= "") or opened[i] == true or (d[2] == here and opened[i] ~= false)
            rows[#rows + 1] = { kind = "hdr", h = 26, d = d, idx = i, done = done, total = total,
                here = d[2] == here, open = open }
            if open then
                for _, r in ipairs(bosses) do rows[#rows + 1] = r end
            end
        end
    end
    if #rows == 0 then rows[1] = { kind = "empty", h = 40 } end
    return rows, today, bossesDone
end

local function Make(l)
    local row = CreateFrame("Button", nil, l)
    St.RowBackground(row)
    row.check = row:CreateTexture(nil, "OVERLAY")
    row.check:SetSize(14, 14)
    row.name = St.Text(row, 11)
    row.value = St.Text(row, 11, "RIGHT")
    row.value:SetPoint("RIGHT", -8, 0)
    row.sep = St.Fill(row, { 1, 1, 1, 0.07 }, "BORDER")
    row.sep:SetPoint("BOTTOMLEFT", 6, 1); row.sep:SetPoint("BOTTOMRIGHT", -6, 1); row.sep:SetHeight(1)
    row:SetScript("OnClick", function(self)
        local item = self.item
        if item and item.kind == "hdr" then
            opened[item.idx] = not item.open
            R:Refresh(true)
        end
    end)
    row:SetScript("OnEnter", function(self)
        self:PaintState(false)
        local item = self.item
        if item and item.kind == "boss" then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(BossName(item.b))
            if item.e then
                GameTooltip:AddLine(format(L["Looted today at %s: %d Reals"], date("%H:%M", item.e.t), item.e.n), 1, 1, 1)
            else
                GameTooltip:AddLine(format(L["Not looted today. Drops %d Real(s)."], item.b[4] and 3 or 1), 1, 1, 1)
            end
            if item.b[5] then GameTooltip:AddLine(L["Optional boss: may not drop Reals."], 0.6, 0.6, 0.6, true) end
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
    row.name:ClearAllPoints()
    row.sep:Hide()
    row.check:Hide()
    row:PaintState(false)
    if item.kind == "empty" then
        row.name:SetPoint("CENTER")
        row.name:SetText(L["Nothing matches"])
        row.name:SetTextColor(1, 1, 1, 0.45)
        row.value:SetText("")
        return
    end
    if item.kind == "hdr" then
        row.name:SetPoint("LEFT", 8, 0)
        row.name:SetPoint("RIGHT", row, "RIGHT", -70, 0)
        local r, g, b = St.Accent()
        row.name:SetText((item.open and "- " or "+ ") .. DungeonName(item.d)
            .. (item.here and ("  |cff9a9a9a(" .. L["you are here"] .. ")|r") or ""))
        row.name:SetTextColor(r, g, b, 1)
        row.value:SetText(format("%d / %d", item.done, item.total))
        if item.done >= item.total and item.total > 0 then
            row.value:SetTextColor(r, g, b, 1)
        else
            row.value:SetTextColor(1, 1, 1, 0.6)
        end
        row.sep:Show()
        return
    end
    local b, e = item.b, item.e
    row.check:Show()
    row.check:SetPoint("LEFT", 14, 0)
    if e then
        row.check:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
        row.check:SetAlpha(1)
    else
        row.check:SetTexture("Interface\\RaidFrame\\ReadyCheck-Waiting")
        row.check:SetAlpha(0.35)
    end
    row.name:SetPoint("LEFT", row.check, "RIGHT", 6, 0)
    row.name:SetPoint("RIGHT", row, "RIGHT", -90, 0)
    row.name:SetText(BossName(b) .. (b[5] and ("  |cff777777(" .. L["optional"] .. ")|r") or ""))
    if e then
        row.name:SetTextColor(1, 1, 1, 0.55)
        local r, g, bl = St.Accent()
        row.value:SetText(format("+%d  |cff9a9a9a%s|r", e.n, date("%H:%M", e.t)))
        row.value:SetTextColor(r, g, bl, 1)
    else
        row.name:SetTextColor(1, 1, 1, 0.9)
        row.value:SetText(format("|cff777777%d|r", b[4] and 3 or 1))
    end
end

function R:Refresh(keepOffset)
    if not (frame and frame:IsShown()) then return end
    local rows, today, bossesDone = Build()
    list:SetData(rows, keepOffset)
    local have, cap = "?", nil
    if C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo then
        local ok, ci = pcall(C_CurrencyInfo.GetCurrencyInfo, CURRENCY)
        if ok and type(ci) == "table" then
            have = ns.Plain(ci.quantity, "number") or "?"
            cap = ns.Plain(ci.maxQuantity, "number")
            if cap == 0 then cap = nil end
        end
    end
    local left = DayStart() + 86400 - time()
    info:SetText(format(L["You have %s%s Reals  ·  today +%d from %d bosses  ·  reset in %s"],
        tostring(have), cap and (" / " .. cap) or "", today, bossesDone, Countdown(left)))
end

local function Init()
    frame = St.Window("NibbelzLootRealsFrame", W, H, L["Undermine Reals"], "reals")
    frame:Place({ "CENTER", UIParent, "CENTER", -300, 0 })
    St.Resizable(frame, 340, 260, 800, 1000, function() R:Refresh(true) end)
    frame:SetScale(ns.db.opts.scale or 1)
    frame:SetFrameStrata("HIGH")
    frame:Hide()
    tinsert(UISpecialFrames, "NibbelzLootRealsFrame")

    local logo = frame.bar:CreateTexture(nil, "OVERLAY")
    logo:SetSize(16, 16)
    logo:SetPoint("LEFT", 10, 0)
    logo:SetTexture("Interface\\Icons\\INV_Misc_Coin_17")
    logo:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    frame.title:ClearAllPoints()
    frame.title:SetPoint("LEFT", logo, "RIGHT", 6, 0)

    info = St.Text(frame, 10)
    info:SetPoint("TOPLEFT", 12, -38)
    info:SetPoint("RIGHT", frame, "RIGHT", -12, 0)
    info:SetWordWrap(true)
    info:SetTextColor(1, 1, 1, St.DIM + 0.2)

    hideCheck = St.Checkbox(frame, L["Hide looted bosses"], function(on)
        ns.db.opts.realsHideLooted = on
        R:Refresh(true)
    end)
    hideCheck:SetPoint("TOPLEFT", 8, -58)
    hideCheck:SetWidth(180)

    local searchBox = St.Search(frame, 170, 20, L["Search dungeon or boss"], function(text)
        text = (text or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
        if text ~= search then
            search = text
            R:Refresh()
        end
    end)
    searchBox:SetPoint("TOPRIGHT", -8, -58)

    local inset = CreateFrame("Frame", nil, frame)
    inset:SetPoint("TOPLEFT", 8, -86)
    inset:SetPoint("BOTTOMRIGHT", -8, 8)
    local bg = St.Fill(inset, St.INSET)
    bg:SetAllPoints()
    St.Border(inset, 0.06)

    list = St.List(inset, 22, Make, Fill)
    list:SetPoint("TOPLEFT", 4, -4)
    list:SetPoint("BOTTOMRIGHT", -4, 14)

    frame:SetScript("OnShow", function()
        hideCheck:SetChecked(ns.db.opts.realsHideLooted)
        R:Refresh()
    end)
    -- The reset countdown: once a minute.
    C_Timer.NewTicker(60, function() R:Refresh(true) end)
end

function R:Toggle()
    if not ns.db then return end
    if not frame then Init() end
    frame:SetShown(not frame:IsShown())
    if frame:IsShown() then frame:Raise() end
end

function R:ApplyScale()
    if frame then frame:SetScale(ns.db.opts.scale or 1) end
end
