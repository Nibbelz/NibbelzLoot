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
local max, min = math.max, math.min

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

-- The quest items this enemy drops that you still need: { "Ghoul Ribs", ... } or nil.
function QM:Needs(unit)
    if not (C_TooltipInfo and C_TooltipInfo.GetUnit) then return nil end
    local ok, enemy = pcall(UnitCanAttack, "player", unit)
    if not ok or Plain(enemy, "boolean") ~= true then return nil end
    local okP, isPlayer = pcall(UnitIsPlayer, unit)
    if okP and Plain(isPlayer, "boolean") then return nil end
    local okT, data = pcall(C_TooltipInfo.GetUnit, unit)
    if not okT or type(data) ~= "table" or type(data.lines) ~= "table" then return nil end
    local items
    for i, line in ipairs(data.lines) do
        local name
        if QUEST_OBJECTIVE then
            if Plain(line.type) == QUEST_OBJECTIVE then name = LootObjective(line.leftText, Plain(line.completed)) end
        elseif i > 1 then
            -- Old clients without line types: any "x/y" line below the name.
            name = LootObjective(line.leftText)
        end
        if name then
            items = items or {}
            items[#items + 1] = name
        end
    end
    return items
end

-------------------------------------------------------------------------------
--  Tooltip line
-------------------------------------------------------------------------------
local function OnUnitTooltip(tooltip)
    if tooltip ~= GameTooltip or not Enabled() then return end
    local ok, _, unit = pcall(tooltip.GetUnit, tooltip)
    unit = ok and Plain(unit, "string") or nil
    if unit and QM:Needs(unit) then
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
    holder.moveBg:SetPoint("TOPLEFT", -6, 6)
    holder.moveBg:SetPoint("BOTTOMRIGHT", 6, -22)
    holder.moveBg:SetColorTexture(0.05, 0.82, 0.62, 0.25)
    holder.moveText = holder:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    holder.moveText:SetPoint("BOTTOM", holder, "TOP", 0, 10)
    holder.moveText:SetText(L["Drag to move"])
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
        s.border:SetColorTexture(0.05, 0.82, 0.62, 1)
        s.text = s:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        s.text:SetPoint("TOP", s, "BOTTOM", 0, -3)
        s.text:SetWidth(SIZE * 2.4)
        s.text:SetWordWrap(true)
        s.text:SetTextColor(1, 1, 1, 1)
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
        s:SetPoint("CENTER", holder, "CENTER", (i - (n + 1) / 2) * (SIZE + 14), 0)
        s.icon:SetTexture(ItemIcon(name))
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

local function Remember(unit)
    if not Enabled() then return end
    local guid = Plain(UnitGUID(unit), "string")
    if not guid or shown[guid] then return end
    local items = QM:Needs(unit)
    if items then watched[guid] = { items = items, seen = GetTime() } end
end

local function CheckDead(unit)
    local guid = Plain(UnitGUID(unit), "string")
    local w = guid and watched[guid]
    if not w then return end
    local ok, dead = pcall(UnitIsDead, unit)
    if not (ok and Plain(dead, "boolean")) then return end
    watched[guid] = nil
    shown[guid] = true
    if Opts().questIcon ~= false and not moving and Enabled() then QM:ShowIcons(w.items) end
end

-- Forget enemies seen long ago.
local function Prune()
    local now = GetTime()
    for guid, w in pairs(watched) do
        if now - w.seen > 600 then watched[guid] = nil end
    end
end

local events = CreateFrame("Frame")
for _, ev in ipairs({ "PLAYER_TARGET_CHANGED", "UPDATE_MOUSEOVER_UNIT", "NAME_PLATE_UNIT_ADDED",
    "NAME_PLATE_UNIT_REMOVED", "UNIT_HEALTH", "UNIT_FLAGS", "PLAYER_ENTERING_WORLD" }) do
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
    elseif event == "PLAYER_ENTERING_WORLD" then
        wipe(watched)
        wipe(shown)
    elseif type(unit) == "string" and (unit == "target" or unit == "focus" or unit:find("^nameplate")) then
        -- UNIT_HEALTH / UNIT_FLAGS / NAME_PLATE_UNIT_REMOVED: did a watched enemy die?
        if next(watched) then CheckDead(unit) end
    end
end)
C_Timer.NewTicker(60, Prune)
