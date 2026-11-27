-- QuestMobs.lua: enemies you still have to loot for one of your quests.
--  * Tooltip: a line "Loot it for your quest".
--  * After you kill one: the icon of the quest item pops up on screen for a few
--    seconds (movable, size and time adjustable, can be switched off).
-- Detection: the game's own unit tooltip lists the quest objectives a unit counts
-- for ("Ghoul Ribs: 3/10"). An unfinished objective that is not a kill objective
-- ("... slain") means: loot this one. Switch on/off separately for dungeons
-- (opts.questLootDungeon) and outdoors (opts.questLootWorld).
local _, ns = ...
local L = ns.L

local QM = {}
ns.QuestMobs = QM

local ICON = "Interface\\Icons\\INV_Misc_Bag_10"
local Plain = function(v, kind) return ns.Plain(v, kind) end
local max, min, format = math.max, math.min, string.format

-- Kill objectives: the unit counts, but there is nothing to loot.
local KILL_WORDS = { "slain", "killed", "defeated", "getötet", "besiegt", "erschlagen", "vernichtet" }

local function Enabled()
    local o = ns.db and ns.db.opts
    if not o then return false end
    local inInstance, kind = IsInInstance()
    if inInstance then
        return o.questLootDungeon and (kind == "party" or kind == "raid") or false
    end
    return o.questLootWorld and true or false
end

local QUEST_OBJECTIVE = Enum and Enum.TooltipDataLineType and Enum.TooltipDataLineType.QuestObjective

-- The item name of an unfinished item objective ("Ghoul Ribs: 3/10" -> "Ghoul Ribs"), else nil.
local function LootObjective(text, completed)
    text = Plain(text, "string")
    if not text or completed == true then return nil end
    local have, need = text:match("(%d+)%s*/%s*(%d+)")
    if not have or tonumber(have) >= tonumber(need) then return nil end
    local lower = text:lower()
    for _, w in ipairs(KILL_WORDS) do
        if lower:find(w, 1, true) then return nil end
    end
    local name = text:gsub("%d+%s*/%s*%d+", ""):gsub("^%s*%-%s*", ""):gsub(":", ""):gsub("^%s+", ""):gsub("%s+$", "")
    return name ~= "" and name or "?"
end

-------------------------------------------------------------------------------
--  Your own quest log: the item objectives you still need. In a group the unit
--  tooltip also lists your group members' quests; only items in this list count.
-------------------------------------------------------------------------------
local mine        -- [item name] = true, rebuilt when the quest log changes
local function MyItems()
    if mine then return mine end
    mine = {}
    local Q = C_QuestLog
    if Q and Q.GetNumQuestLogEntries and Q.GetInfo and Q.GetQuestObjectives then
        for i = 1, Q.GetNumQuestLogEntries() or 0 do
            local info = Q.GetInfo(i)
            if info and not info.isHeader and info.questID then
                for _, o in ipairs(Q.GetQuestObjectives(info.questID) or {}) do
                    if o.type == "item" and not o.finished then
                        local name = LootObjective(o.text)
                        if name then mine[name] = true end
                    end
                end
            end
        end
    elseif GetNumQuestLogEntries and GetQuestLogLeaderBoard then
        -- Older quest log API.
        for i = 1, (GetNumQuestLogEntries()) or 0 do
            for j = 1, GetNumQuestLeaderBoards(i) or 0 do
                local text, kind, done = GetQuestLogLeaderBoard(j, i)
                if kind == "item" and not done then
                    local name = LootObjective(text)
                    if name then mine[name] = true end
                end
            end
        end
    end
    return mine
end
function QM:QuestLogChanged() mine = nil end

-------------------------------------------------------------------------------
--  Done: when the last item of a quest objective is looted, a short hint (and,
--  if switched on, a sound). opts.questDoneHint (on by default), opts.questDoneSound (off).
-------------------------------------------------------------------------------
local progress   -- ["questID:index"] = finished, for every item objective in your log

-- "Plainstrider Meat: 7/7" / "7/7 Plainstrider Meat" -> "Plainstrider Meat"
local function ItemName(text)
    text = Plain(text, "string") or ""
    return (text:gsub("%d+%s*/%s*%d+", ""):gsub("^%s*%-%s*", ""):gsub(":", ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

local function Announce(title, item, questDone)
    local o = ns.db.opts
    if o.questDoneHint ~= false then
        local msg = questDone and format(L["%s: all items looted, quest complete!"], title)
            or format(L["%s: all %s looted"], title, item)
        if UIErrorsFrame and UIErrorsFrame.AddMessage then
            UIErrorsFrame:AddMessage(msg, 0.05, 0.82, 0.62, 1)
        else
            ns.Print(msg)
        end
    end
    if o.questDoneSound then
        local kit = SOUNDKIT and (SOUNDKIT.IG_QUEST_LIST_COMPLETE or SOUNDKIT.READY_CHECK)
        pcall(PlaySound, kit or 878, "Master")
    end
end

-- notify: compare with the last scan and announce objectives that just got done.
function QM:ScanProgress(notify)
    local Q = C_QuestLog
    if not (Q and Q.GetNumQuestLogEntries and Q.GetInfo and Q.GetQuestObjectives) then return end
    local now = {}
    for i = 1, Q.GetNumQuestLogEntries() or 0 do
        local info = Q.GetInfo(i)
        if info and not info.isHeader and info.questID then
            local objs = Q.GetQuestObjectives(info.questID) or {}
            local allDone = #objs > 0
            for _, o in ipairs(objs) do
                if not o.finished then allDone = false end
            end
            for j, o in ipairs(objs) do
                if o.type == "item" then
                    local key = info.questID .. ":" .. j
                    now[key] = o.finished and true or false
                    if notify and progress and progress[key] == false and o.finished then
                        Announce(info.title or "?", ItemName(o.text), allDone)
                    end
                end
            end
        end
    end
    progress = now
end

local QUEST_TITLE = Enum and Enum.TooltipDataLineType and Enum.TooltipDataLineType.QuestTitle
local QUEST_PLAYER = Enum and Enum.TooltipDataLineType and Enum.TooltipDataLineType.QuestPlayer

-- The quest items in a unit's tooltip data that YOU still need: { "Ghoul Ribs", ... } or nil.
local function ItemsFromData(data)
    if type(data) ~= "table" or type(data.lines) ~= "table" then return nil end
    local own = MyItems()
    local items
    local other = false   -- below a group member's name: their objectives, not yours
    for i, line in ipairs(data.lines) do
        local name
        local kind = Plain(line.type)
        if QUEST_TITLE and kind == QUEST_TITLE then
            other = false
        elseif QUEST_PLAYER and kind == QUEST_PLAYER then
            other = true
        elseif QUEST_OBJECTIVE then
            if kind == QUEST_OBJECTIVE and not other then
                name = LootObjective(line.leftText, Plain(line.completed))
            end
        elseif i > 1 then
            -- Old clients without line types: any "x/y" line below the name.
            name = LootObjective(line.leftText)
        end
        -- Only items from your own quest log.
        if name and not own[name] then name = nil end
        if name then
            items = items or {}
            items[#items + 1] = name
        end
    end
    return items
end

local function IsEnemyNpc(unit)
    local ok, enemy = pcall(UnitCanAttack, "player", unit)
    if not ok or Plain(enemy, "boolean") ~= true then return false end
    local okP, isPlayer = pcall(UnitIsPlayer, unit)
    return not (okP and Plain(isPlayer, "boolean"))
end

-- The quest items this enemy drops that you still need: { "Ghoul Ribs", ... } or nil.
function QM:Needs(unit)
    if not (C_TooltipInfo and C_TooltipInfo.GetUnit) or not IsEnemyNpc(unit) then return nil end
    local okT, data = pcall(C_TooltipInfo.GetUnit, unit)
    return okT and ItemsFromData(data) or nil
end

-------------------------------------------------------------------------------
--  Tooltip line
-------------------------------------------------------------------------------
-- Uses the tooltip's own data (no second tooltip scan for the same unit).
local function OnUnitTooltip(tooltip, data)
    if tooltip ~= GameTooltip or not Enabled() then return end
    local ok, _, unit = pcall(tooltip.GetUnit, tooltip)
    unit = ok and Plain(unit, "string") or nil
    if unit and IsEnemyNpc(unit) and ItemsFromData(data) then
        tooltip:AddLine("|T" .. ICON .. ":14:14:0:0:64:64:5:59:5:59|t |cff0cd29f" .. L["Loot it for your quest"] .. "|r")
    end
end
if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, OnUnitTooltip)
end

-------------------------------------------------------------------------------
--  Item icons
-------------------------------------------------------------------------------
local iconCache = {}

-- The icon of a quest item by its name: the item cache, else your bags, else a bag.
local function ItemIcon(name)
    if iconCache[name] then return iconCache[name] end
    local icon
    if C_Item and C_Item.GetItemInfoInstant then
        local ok, _, _, _, _, tex = pcall(C_Item.GetItemInfoInstant, name)
        if ok then icon = Plain(tex) end
    end
    if not icon and C_Container and C_Container.GetContainerNumSlots then
        for bag = 0, 4 do
            for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
                local info = C_Container.GetContainerItemInfo(bag, slot)
                local link = info and Plain(info.hyperlink, "string")
                if link and link:match("%[(.-)%]") == name then
                    icon = info.iconFileID
                    break
                end
            end
            if icon then break end
        end
    end
    if icon then iconCache[name] = icon end
    return icon or ICON
end

-------------------------------------------------------------------------------
--  On-screen icon
-------------------------------------------------------------------------------
local SIZE = 44
local holder, slots
local hideAt, moving = 0, false

local function Opts() return ns.db.opts end

local function SavePos()
    local point, _, relPoint, x, y = holder:GetPoint()
    ns.db.pos.questIcon = { point, relPoint, x, y }
end

local function CreateHolder()
    holder = CreateFrame("Frame", "NibbelzLootQuestIcon", UIParent)
    holder:SetSize(SIZE, SIZE)
    holder:SetFrameStrata("HIGH")
    holder:SetClampedToScreen(true)
    holder:SetMovable(true)
    holder:RegisterForDrag("LeftButton")
    holder:SetScript("OnDragStart", function(self) if moving then self:StartMoving() end end)
    holder:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        SavePos()
    end)
    local p = ns.db.pos.questIcon
    if type(p) == "table" and p[1] then
        holder:SetPoint(p[1], UIParent, p[2], p[3], p[4])
    else
        holder:SetPoint("CENTER", UIParent, "CENTER", 0, 160)
    end
    -- Shown while moving: a frame and a hint.
    holder.moveBg = holder:CreateTexture(nil, "BACKGROUND")
    holder.moveBg:SetPoint("TOPLEFT", -8, 8)
    holder.moveBg:SetPoint("BOTTOMRIGHT", 8, -40)
    local ar, ag, ab = ns.St.Accent()
    holder.moveBg:SetColorTexture(ar, ag, ab, 0.25)
    holder.moveText = holder:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    holder.moveText:SetPoint("BOTTOM", holder, "TOP", 0, 10)
    holder.moveText:SetText(L["Drag to move"])
    -- Only visible while moving (Options > "Move icon").
    holder.moveBg:Hide()
    holder.moveText:Hide()
    slots = {}
    holder:Hide()
    holder:SetScript("OnUpdate", function(self)
        if moving then return end
        local left = hideAt - GetTime()
        if left <= 0 then
            self:Hide()
        else
            self:SetAlpha(min(1, left / 0.6))   -- fade out over the last 0.6 s
        end
    end)
end

local function Slot(i)
    local s = slots[i]
    if not s then
        s = CreateFrame("Frame", nil, holder)
        s:SetSize(SIZE, SIZE)
        s.icon = s:CreateTexture(nil, "ARTWORK")
        s.icon:SetAllPoints()
        s.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        s.border = s:CreateTexture(nil, "BACKGROUND")
        s.border:SetPoint("TOPLEFT", -2, 2)
        s.border:SetPoint("BOTTOMRIGHT", 2, -2)
        -- Same look as the Undermine Real reminder (Reals.lua): accent frame,
        -- a gold line ("Loot it for your quest") and a white line (the item).
        s.label = s:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        s.label:SetPoint("TOP", s, "BOTTOM", 0, -4)
        s.text = s:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        s.text:SetPoint("TOP", s.label, "BOTTOM", 0, -2)
        s.text:SetWidth(SIZE * 3)
        s.text:SetWordWrap(true)
        slots[i] = s
    end
    return s
end

-- Show these quest items (names) for the set time.
function QM:ShowIcons(items, keep)
    if not holder then CreateHolder() end
    holder:SetScale(Opts().questIconScale or 1)
    local n = #items
    for i, name in ipairs(items) do
        local s = Slot(i)
        s:ClearAllPoints()
        s:SetPoint("CENTER", holder, "CENTER", (i - (n + 1) / 2) * (SIZE * 3 + 10), 0)
        s.icon:SetTexture(ItemIcon(name))
        s.border:SetColorTexture(ns.St.Accent())
        s.label:SetText(L["Loot it for your quest"])
        s.text:SetText(name)
        s:Show()
    end
    for i = n + 1, #slots do slots[i]:Hide() end
    hideAt = keep and math.huge or (GetTime() + (Opts().questIconTime or 3))
    holder:SetAlpha(1)
    holder:Show()
end

-- Options: the icon stays on screen and can be dragged until moving is switched off.
function QM:SetMoving(on)
    if not holder then CreateHolder() end
    moving = on
    holder:EnableMouse(on)
    holder.moveBg:SetShown(on)
    holder.moveText:SetShown(on)
    if on then
        QM:ShowIcons({ L["Quest item"] }, true)
    else
        holder:Hide()
    end
    return moving
end

function QM:IsMoving() return moving end

function QM:ApplyScale()
    if holder then holder:SetScale(Opts().questIconScale or 1) end
end

-------------------------------------------------------------------------------
--  Kill detection: remember quest enemies you saw (target, mouseover, nameplates)
--  and show their items when one of them dies.
-------------------------------------------------------------------------------
local watched = {}   -- guid -> { items, seen = time }
local shown = {}     -- guid -> true (only once per enemy)
local checked = {}   -- guid -> true: looked at, nothing to loot (until the quest log changes)
local deathEvents    -- frame for the death checks, listening only while something is watched

-- The death events (health, flags, plates going away) are only needed while a
-- quest enemy is watched: switched on and off to keep the event traffic low.
local function Listen(on)
    if not deathEvents then return end
    if on and not deathEvents.on then
        deathEvents:RegisterUnitEvent("UNIT_HEALTH", "target")
        deathEvents:RegisterEvent("UNIT_FLAGS")
        deathEvents:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
        deathEvents.on = true
    elseif not on and deathEvents.on then
        deathEvents:UnregisterAllEvents()
        deathEvents.on = false
    end
end

local function Remember(unit)
    if not Enabled() then return end
    local guid = Plain(UnitGUID(unit), "string")
    if not guid or shown[guid] or watched[guid] or checked[guid] then return end
    local items = QM:Needs(unit)
    if items then
        watched[guid] = { items = items, seen = GetTime() }
        Listen(true)
    else
        checked[guid] = true
    end
end

local function CheckDead(unit)
    local guid = Plain(UnitGUID(unit), "string")
    local w = guid and watched[guid]
    if not w then return end
    local ok, dead = pcall(UnitIsDead, unit)
    if not (ok and Plain(dead, "boolean")) then return end
    watched[guid] = nil
    shown[guid] = true
    if not next(watched) then Listen(false) end
    -- Only items your own quests still need right now (read fresh: the last one may
    -- have been looted a moment ago and the quest is done).
    mine = nil
    local own, items = MyItems(), {}
    for _, name in ipairs(w.items) do
        if own[name] then items[#items + 1] = name end
    end
    if #items > 0 and Opts().questIcon ~= false and not moving and Enabled() then QM:ShowIcons(items) end
end

-- Forget enemies seen long ago (and the "nothing to loot" notes, so they stay small).
local function Prune()
    local now = GetTime()
    for guid, w in pairs(watched) do
        if now - w.seen > 600 then watched[guid] = nil end
    end
    if not next(watched) then Listen(false) end
    wipe(checked)
end

deathEvents = CreateFrame("Frame")
deathEvents:SetScript("OnEvent", function(_, _, unit)
    if type(unit) == "string" and (unit == "target" or unit:find("^nameplate")) then
        -- Did a watched enemy die?
        CheckDead(unit)
    end
end)

local events = CreateFrame("Frame")
for _, ev in ipairs({ "PLAYER_TARGET_CHANGED", "UPDATE_MOUSEOVER_UNIT", "NAME_PLATE_UNIT_ADDED",
    "QUEST_LOG_UPDATE", "PLAYER_ENTERING_WORLD" }) do
    pcall(events.RegisterEvent, events, ev)
end
events:SetScript("OnEvent", function(_, event, unit)
    if not ns.db then return end
    if event == "PLAYER_TARGET_CHANGED" then
        Remember("target")
    elseif event == "UPDATE_MOUSEOVER_UNIT" then
        Remember("mouseover")
    elseif event == "NAME_PLATE_UNIT_ADDED" then
        Remember(unit)
    elseif event == "QUEST_LOG_UPDATE" then
        -- Quests changed: enemies checked before may count now (or no longer).
        wipe(checked)
        QM:QuestLogChanged()
        -- Did the last needed item of an objective just come in?
        ns.Debounce("questProgress", 0.2, function() QM:ScanProgress(true) end)
    elseif event == "PLAYER_ENTERING_WORLD" then
        wipe(watched)
        wipe(shown)
        wipe(checked)
        Listen(false)
        -- The starting point: nothing is announced for what is already done.
        if not progress then C_Timer.After(2, function() QM:ScanProgress(false) end) end
    end
end)
C_Timer.NewTicker(60, Prune)
