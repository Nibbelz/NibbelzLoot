-- Minimap.lua: a round minimap button with a gold coin. Left-click: options,
-- Shift + left-click: roll history, right-click: loot roll window, drag: move it.
-- Named like other addon buttons so EllesmereUI's minimap button bar can collect it.
local _, ns = ...
local L = ns.L

local format, max, min, sqrt, rad, deg, cos, sin = string.format, math.max, math.min, math.sqrt, math.rad, math.deg, math.cos, math.sin
local atan2 = math.atan2 or atan2

local MM = {}
ns.Minimap = MM

local ICON = "Interface\\Icons\\INV_Misc_Coin_01"
local button

-- Which quadrants of the minimap are round (LibDBIcon's table), for square minimaps.
local SHAPES = {
    ["ROUND"] = { true, true, true, true },
    ["SQUARE"] = { false, false, false, false },
    ["CORNER-TOPLEFT"] = { false, false, false, true },
    ["CORNER-TOPRIGHT"] = { false, false, true, false },
    ["CORNER-BOTTOMLEFT"] = { false, true, false, false },
    ["CORNER-BOTTOMRIGHT"] = { true, false, false, false },
    ["SIDE-LEFT"] = { false, true, false, true },
    ["SIDE-RIGHT"] = { true, false, true, false },
    ["SIDE-TOP"] = { false, false, true, true },
    ["SIDE-BOTTOM"] = { true, true, false, false },
    ["TRICORNER-TOPLEFT"] = { false, true, true, true },
    ["TRICORNER-TOPRIGHT"] = { true, false, true, true },
    ["TRICORNER-BOTTOMLEFT"] = { true, true, false, true },
    ["TRICORNER-BOTTOMRIGHT"] = { true, true, true, false },
}

local function Place(angle)
    local a = rad(angle or 200)
    local x, y, q = cos(a), sin(a), 1
    if x < 0 then q = q + 1 end
    if y > 0 then q = q + 2 end
    local shape = (GetMinimapShape and GetMinimapShape()) or "ROUND"
    local quad = SHAPES[shape] or SHAPES.ROUND
    local w = Minimap:GetWidth() / 2 + 5
    local h = Minimap:GetHeight() / 2 + 5
    if quad[q] then
        x, y = x * w, y * h
    else
        local dw, dh = sqrt(2 * w * w) - 10, sqrt(2 * h * h) - 10
        x = max(-w, min(x * dw, w))
        y = max(-h, min(y * dh, h))
    end
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

local function OnDragUpdate()
    local mx, my = Minimap:GetCenter()
    local px, py = GetCursorPosition()
    local scale = Minimap:GetEffectiveScale()
    px, py = px / scale, py / scale
    ns.db.opts.minimapAngle = deg(atan2(py - my, px - mx)) % 360
    Place(ns.db.opts.minimapAngle)
end

-------------------------------------------------------------------------------
--  Tooltip (also used by the addon compartment entry)
-------------------------------------------------------------------------------
function ns.FillTooltip(tip)
    tip:AddLine("|cffffd100Nibbelz|r Loot")
    local db = ns.db
    if db then
        local today = ns.DayKey(time())
        local v = ns.CurrentVisit()
        local runWon, runGold, dayGold, allGold = 0, 0, 0, 0
        local runAH, dayAH, allAH = 0, 0, 0
        for _, rec in ipairs(db.rolls) do
            if rec.mw then
                local sell, ah = rec.sell or 0, ns.AH(rec) or 0
                allGold, allAH = allGold + sell, allAH + ah
                if ns.DayKey(rec.t) == today then dayGold, dayAH = dayGold + sell, dayAH + ah end
                if v and rec.v == v.id then
                    runWon = runWon + 1
                    runGold, runAH = runGold + sell, runAH + ah
                end
            end
        end
        local function Value(gold, ah)
            if ah > 0 then return ns.Money(gold) .. "  |cff9a9a9aAH|r " .. ns.Money(ah) end
            return ns.Money(gold)
        end
        tip:AddLine(" ")
        if v then
            tip:AddDoubleLine(format("%s: %s", L["This run"], v.place), Value(runGold, runAH), 1, 1, 1, 1, 1, 1)
            tip:AddLine("|cff9a9a9a" .. format(L["won %d"], runWon) .. "|r")
        end
        tip:AddDoubleLine(L["Gold won"] .. " (" .. L["Today"] .. ")", Value(dayGold, dayAH), 1, 1, 1, 1, 1, 1)
        tip:AddDoubleLine(L["Gold won"] .. " (" .. L["Total"] .. ")", Value(allGold, allAH), 1, 1, 1, 1, 1, 1)
    end
    tip:AddLine(" ")
    tip:AddLine(L["Left-click: options"], 0.8, 0.8, 0.8)
    tip:AddLine(L["Shift + left-click: roll history"], 0.8, 0.8, 0.8)
    tip:AddLine(L["Right-click: loot roll window"], 0.8, 0.8, 0.8)
    tip:AddLine(L["Ctrl-click: group stats"], 0.8, 0.8, 0.8)
    tip:AddLine(L["Alt-click: loot battle"], 0.8, 0.8, 0.8)
    tip:AddLine(L["Middle-click: fair share"], 0.8, 0.8, 0.8)
    tip:AddLine(L["Drag: move the button"], 0.8, 0.8, 0.8)
end

-------------------------------------------------------------------------------
--  Button
-------------------------------------------------------------------------------
local function Build()
    button = CreateFrame("Button", "NibbelzLootMinimapButton", Minimap)
    button:SetSize(31, 31)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(8)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp", "MiddleButtonUp")
    button:RegisterForDrag("LeftButton")
    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    local bg = button:CreateTexture(nil, "BACKGROUND")
    bg:SetSize(20, 20)
    bg:SetPoint("TOPLEFT", 7, -5)
    bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")

    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetSize(17, 17)
    icon:SetPoint("TOPLEFT", 7, -6)
    icon:SetTexture(ICON)
    icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
    button.icon = icon

    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

    button:SetScript("OnClick", function(_, which)
        if IsControlKeyDown() then
            ns.GroupStats:Toggle()
        elseif IsAltKeyDown() then
            ns.Battle:Command()
        elseif which == "MiddleButton" then
            ns.Share:Toggle()
        elseif which == "RightButton" then
            ns.Live:Toggle()
        elseif IsShiftKeyDown() then
            ns.History:Toggle()   -- Shift + left-click: roll history
        else
            ns.Options:Toggle()   -- left-click: options
        end
    end)
    button:SetScript("OnMouseDown", function() icon:SetTexCoord(0.1, 0.9, 0.1, 0.9) end)
    button:SetScript("OnMouseUp", function() icon:SetTexCoord(0.05, 0.95, 0.05, 0.95) end)
    button:SetScript("OnDragStart", function(self)
        GameTooltip:Hide()
        self:SetScript("OnUpdate", OnDragUpdate)
    end)
    button:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
        icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
    end)
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        ns.FillTooltip(GameTooltip)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

function MM:Init()
    if not Minimap then return end
    Build()
    Place(ns.db.opts.minimapAngle)
    button:SetShown(not ns.db.opts.minimapHide)
end

function MM:SetShown(show)
    ns.db.opts.minimapHide = not show
    if button then button:SetShown(show) end
end

function MM:Toggle()
    self:SetShown(ns.db.opts.minimapHide)
    ns.Print(format(L["Minimap button: %s"], ns.db.opts.minimapHide and L["off"] or L["on"]))
end
