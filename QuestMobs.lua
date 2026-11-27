-- QuestMobs.lua: marks enemies you still have to loot for one of your quests.
-- A loot-bag icon sits next to their nameplate, and their tooltip gets a line.
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

-- Is this objective line unfinished and about an item (not a kill)?
local function LootObjective(text, completed)
    text = Plain(text, "string")
    if not text or completed == true then return false end
    local have, need = text:match("(%d+)%s*/%s*(%d+)")
    if have and tonumber(have) >= tonumber(need) then return false end
    local lower = text:lower()
    for _, w in ipairs(KILL_WORDS) do
        if lower:find(w, 1, true) then return false end
    end
    return have ~= nil
end

-- true when the unit is an enemy that drops something one of your quests still needs.
function QM:Needs(unit)
    if not (C_TooltipInfo and C_TooltipInfo.GetUnit) then return false end
    local ok, enemy = pcall(UnitCanAttack, "player", unit)
    if not ok or Plain(enemy, "boolean") ~= true then return false end
    local okP, isPlayer = pcall(UnitIsPlayer, unit)
    if okP and Plain(isPlayer, "boolean") then return false end
    local okD, dead = pcall(UnitIsDead, unit)
    if okD and Plain(dead, "boolean") then return false end
    local okT, data = pcall(C_TooltipInfo.GetUnit, unit)
    if not okT or type(data) ~= "table" or type(data.lines) ~= "table" then return false end
    for i, line in ipairs(data.lines) do
        if QUEST_OBJECTIVE then
            if Plain(line.type) == QUEST_OBJECTIVE and LootObjective(line.leftText, Plain(line.completed)) then
                return true
            end
        elseif i > 1 and LootObjective(line.leftText) then
            -- Old clients without line types: any "x/y" line below the name.
            return true
        end
    end
    return false
end

-------------------------------------------------------------------------------
--  Nameplates
-------------------------------------------------------------------------------
local function PlateFor(unit)
    if not (C_NamePlate and C_NamePlate.GetNamePlateForUnit) then return nil end
    local ok, plate = pcall(C_NamePlate.GetNamePlateForUnit, unit)
    if not ok or not plate or (plate.IsForbidden and plate:IsForbidden()) then return nil end
    return plate
end

local function Mark(plate, on)
    local f = plate.NibbelzQuestLoot
    if not on then
        if f then f:Hide() end
        return
    end
    if not f then
        f = CreateFrame("Frame", nil, plate)
        f:SetSize(18, 18)
        f:SetPoint("RIGHT", plate, "LEFT", 2, 0)
        f:SetFrameStrata("HIGH")
        local tex = f:CreateTexture(nil, "OVERLAY")
        tex:SetAllPoints()
        tex:SetTexture(ICON)
        tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        local border = f:CreateTexture(nil, "OVERLAY", nil, 1)
        border:SetPoint("TOPLEFT", -1, 1)
        border:SetPoint("BOTTOMRIGHT", 1, -1)
        border:SetColorTexture(0.05, 0.82, 0.62, 0.9)
        border:SetDrawLayer("ARTWORK")
        plate.NibbelzQuestLoot = f
    end
    f:Show()
end

local function UpdateUnit(unit)
    local plate = PlateFor(unit)
    if not plate then return end
    Mark(plate, Enabled() and QM:Needs(unit))
end

function QM:UpdateAll()
    if not (C_NamePlate and C_NamePlate.GetNamePlates) then return end
    local ok, plates = pcall(C_NamePlate.GetNamePlates)
    if not ok or type(plates) ~= "table" then return end
    for _, plate in ipairs(plates) do
        local unit = plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit)
        if unit then
            UpdateUnit(unit)
        elseif plate.NibbelzQuestLoot then
            plate.NibbelzQuestLoot:Hide()
        end
    end
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
--  Events
-------------------------------------------------------------------------------
local events = CreateFrame("Frame")
for _, ev in ipairs({ "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED", "QUEST_LOG_UPDATE",
    "UNIT_QUEST_LOG_CHANGED", "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "UNIT_FLAGS" }) do
    pcall(events.RegisterEvent, events, ev)
end
events:SetScript("OnEvent", function(_, event, unit)
    if not ns.db then return end
    if event == "NAME_PLATE_UNIT_ADDED" then
        UpdateUnit(unit)
    elseif event == "NAME_PLATE_UNIT_REMOVED" then
        local plate = PlateFor(unit)
        if plate then Mark(plate, false) end
    elseif event == "UNIT_FLAGS" then
        -- Died (or changed sides): the plate goes away or must lose its icon.
        if type(unit) == "string" and unit:find("^nameplate") then UpdateUnit(unit) end
    else
        -- Quest progress changed: objectives may be done now.
        ns.Debounce("questMobs", 0.3, function() QM:UpdateAll() end)
    end
end)
