-- BattleHistory.lua: the past loot battles (ns.db.battles, newest first, the last
-- 30 are kept by Battle.lua). Click a battle to see its result, right-click it to
-- delete it. Options > Loot battle deletes all of them.
local _, ns = ...
local St, L = ns.St, ns.L

local format = string.format

local BH = {}
ns.BattleHistory = BH

local W, H = 440, 420
local frame, list, summary
local open = {}   -- battle id -> true: result unfolded

local function Battles() return ns.db.battles or {} end

local function PlayerCount(b)
    local n = 0
    for _ in pairs(b.joined or {}) do n = n + 1 end
    return n
end

-- The overall winner(s) of a battle, for the row: total points, else the best tipper.
local function Winner(b)
    local r = b.result
    if not r then return nil end
    if r.total then
        local names = {}
        for _, p in ipairs(r.total.list or {}) do
            if r.total.winners[p.name] then names[#names + 1] = p.name end
        end
        if #names > 0 then return table.concat(names, ", ") end
    end
    if r.tippers and r.tippers[1] then return r.tippers[1].name end
end

local function Build()
    local rows = {}
    for i, b in ipairs(Battles()) do
        rows[#rows + 1] = { kind = "battle", h = 38, b = b, index = i }
        if open[b.id] then
            local lines = ns.Battle.ResultLines(b)
            -- Line 1 is the heading ("Loot battle <place>:"), the row shows that already.
            for j = 2, #lines do rows[#rows + 1] = { kind = "line", h = 18, text = lines[j] } end
            if #lines <= 1 then rows[#rows + 1] = { kind = "line", h = 18, text = L["No result"] } end
        end
    end
    if #rows == 0 then rows[1] = { kind = "empty", h = 40 } end
    return rows
end

local function Delete(b)
    local battles = Battles()
    for i, x in ipairs(battles) do
        if x == b then
            table.remove(battles, i)
            break
        end
    end
    open[b.id] = nil
    BH:Refresh(true)
end

local function Make(l)
    local row = CreateFrame("Button", nil, l)
    St.RowBackground(row)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row.title = St.Text(row, 11)
    row.sub = St.Text(row, 10)
    row.value = St.Text(row, 11, "RIGHT")
    row.value:SetPoint("TOPRIGHT", -8, -5)
    row.sep = St.Fill(row, { 1, 1, 1, 0.07 }, "BORDER")
    row.sep:SetPoint("BOTTOMLEFT", 6, 1); row.sep:SetPoint("BOTTOMRIGHT", -6, 1); row.sep:SetHeight(1)
    row:SetScript("OnClick", function(self, button)
        local item = self.item
        if not (item and item.b) then return end
        if button == "RightButton" then
            St.ContextMenu({
                { L["Delete this battle"], function() Delete(item.b) end, true },
                { CANCEL or "Cancel", function() end },
            })
        else
            open[item.b.id] = not open[item.b.id] or nil
            BH:Refresh(true)
        end
    end)
    row:SetScript("OnEnter", function(self)
        self:PaintState(false)
        if self.item and self.item.b then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(L["Click: show the result"], 1, 1, 1)
            GameTooltip:AddLine(L["Right-click: delete this battle"], 0.7, 0.7, 0.7)
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
    row.title:ClearAllPoints()
    row.sub:Hide()
    row.sep:Hide()
    row.value:SetText("")
    row:EnableMouse(item.kind == "battle")
    row:PaintState(false)
    if item.kind == "empty" then
        row.title:SetPoint("CENTER")
        row.title:SetText(L["No loot battles yet"])
        row.title:SetTextColor(1, 1, 1, 0.45)
        return
    end
    if item.kind == "line" then
        row.title:SetPoint("LEFT", 24, 0)
        row.title:SetPoint("RIGHT", row, "RIGHT", -8, 0)
        row.title:SetText(item.text)
        row.title:SetTextColor(1, 1, 1, 0.75)
        return
    end
    local b = item.b
    row.title:SetPoint("TOPLEFT", 10, -5)
    row.title:SetPoint("RIGHT", row, "RIGHT", -150, 0)
    row.title:SetText((open[b.id] and "- " or "+ ") .. (b.place or "?") .. "  |cff9a9a9a" .. ns.Battle.ModeLabel(b) .. "|r")
    local r, g, bl = St.Accent()
    row.title:SetTextColor(r, g, bl, 1)
    row.sub:Show()
    row.sub:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -3)
    row.sub:SetPoint("RIGHT", row, "RIGHT", -8, 0)
    local parts = { ns.DayLabel(b.t) .. " " .. ns.Clock(b.t), ns.Players(PlayerCount(b)) }
    if (b.stake or 0) > 0 then parts[#parts + 1] = format(L["Stake: %s"], ns.Money(b.stake)) end
    row.sub:SetText("|cff9a9a9a" .. table.concat(parts, "  ·  ") .. "|r")
    local w = Winner(b)
    row.value:SetText(w and ("|cffffd100" .. w .. "|r") or "")
    row.sep:Show()
end

function BH:Refresh(keepOffset)
    if not (frame and frame:IsShown()) then return end
    list:SetData(Build(), keepOffset)
    local n = #Battles()
    summary:SetText(n == 1 and L["1 battle"] or format(L["%d battles"], n))
end

local function Init()
    frame = St.Window("NibbelzLootBattleHistoryFrame", W, H, L["Battle history"], "battleHistory")
    frame:Place({ "CENTER", UIParent, "CENTER", 260, 20 })
    St.Resizable(frame, 360, 260, 900, 1000, function() BH:Refresh(true) end)
    frame:SetScale(ns.db.opts.scale or 1)
    frame:SetFrameStrata("HIGH")
    frame:Hide()
    tinsert(UISpecialFrames, "NibbelzLootBattleHistoryFrame")

    local logo = frame.bar:CreateTexture(nil, "OVERLAY")
    logo:SetSize(16, 16)
    logo:SetPoint("LEFT", 10, 0)
    logo:SetTexture("Interface\\Icons\\Ability_DualWield")
    logo:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    frame.title:ClearAllPoints()
    frame.title:SetPoint("LEFT", logo, "RIGHT", 6, 0)

    summary = St.Text(frame, 10)
    summary:SetPoint("TOPLEFT", 12, -38)
    summary:SetPoint("RIGHT", frame, "RIGHT", -12, 0)
    summary:SetTextColor(1, 1, 1, St.DIM + 0.15)

    local inset = CreateFrame("Frame", nil, frame)
    inset:SetPoint("TOPLEFT", 8, -56)
    inset:SetPoint("BOTTOMRIGHT", -8, 8)
    local bg = St.Fill(inset, St.INSET)
    bg:SetAllPoints()
    St.Border(inset, 0.06)

    list = St.List(inset, 38, Make, Fill)
    list:SetPoint("TOPLEFT", 4, -4)
    list:SetPoint("BOTTOMRIGHT", -4, 14)

    frame:SetScript("OnShow", function() BH:Refresh() end)
end

function BH:Toggle()
    if not ns.db then return end
    if not frame then Init() end
    frame:SetShown(not frame:IsShown())
    if frame:IsShown() then frame:Raise() end
end

function BH:ApplyScale()
    if frame then frame:SetScale(ns.db.opts.scale or 1) end
end
