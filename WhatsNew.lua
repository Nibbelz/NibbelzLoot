-- WhatsNew.lua: after an update, a small window at login with the latest changes,
-- short: what is new or changed and how to use it. Shown once per new version
-- (ns.db.seenVersion); /rolls news opens it again any time.
-- A fresh install shows nothing (there is nothing "new" yet).
local ADDON_NAME, ns = ...
local St, L = ns.St, ns.L

local format, max, min = string.format, math.max, math.min

local WN = {}
ns.WhatsNew = WN

local SHOW_MAX = 4   -- versions shown at most (the newest first)

-- Newest first. Keep each line short: what changed, and where / how to use it.
local NOTES = {
    { "1.6.2",
        en = { "Options > General: Gold per dungeon sits next to the style, AH prices have their own row." },
        de = { "Optionen > Allgemein: Gold pro Dungeon steht neben dem Stil, AH-Preise haben eine eigene Zeile." } },
    { "1.6.1",
        en = { "Options: the category Others is gone. AH prices, window style and Gold per dungeon are now under General." },
        de = { "Optionen: Die Kategorie Sonstiges ist weg. AH-Preise, Fensterstil und Gold pro Dungeon stehen jetzt unter Allgemein." } },
    { "1.6.0",
        en = {
            "Classic style reworked to match the WoW Forever interface: game menu frame, red buttons with gold text, Blizzard check boxes and sliders. Pick it in Options > General > Style.",
            "New installs: on the first start you choose between the Nibbelz and the Classic style.",
            "New: loot battle history. Button in the loot battle window or Options > Loot battle. Click a battle for its result, right-click to delete it.",
            "Options: new category General on top. Roll history buttons (demo, delete) are now in the Roll History window; AH prices, style and Gold per dungeon are under General.",
            "Quest loot: when the last item of a quest is looted, a short hint shows (sound optional). No more icon for quests that are already done. Options > Loot icons.",
        },
        de = {
            "Neu: Loot-Battle-Verlauf. Button im Loot-Battle-Fenster oder unter Optionen > Loot Battle. Klick auf ein Battle zeigt das Ergebnis, Rechtsklick löscht es.",
            "Optionen: neue Kategorie Allgemein ganz oben. Die Roll-History-Buttons (Demo, Löschen) sind jetzt im Roll-History-Fenster, AH-Preise, Stil und Gold pro Dungeon unter Allgemein.",
            "Quest-Beute: Ist das letzte Item einer Quest gelootet, erscheint ein kurzer Hinweis (Sound optional). Für erledigte Quests kommt kein Symbol mehr. Optionen > Loot-Symbole.",
            "Classic-Stil an die WoW-Forever-Oberfläche angepasst: Spielmenü-Rahmen, rote Buttons mit goldener Schrift, Blizzard-Checkboxen und -Schieberegler. Auswahl unter Optionen > Allgemein > Stil.",
            "Neuinstallation: Beim ersten Start wählst du zwischen Nibbelz- und Classic-Stil.",
        } },
    { "1.5.1",
        en = { "Quest item icon: only for quests in your own quest log (no longer your group members' quests), and without the green background." },
        de = { "Quest-Item-Symbol: nur noch für Quests in deinem eigenen Questlog (nicht mehr die der Gruppenmitglieder) und ohne grünen Hintergrund." } },
    { "1.5.0",
        en = {
            "New: this window. After an update it shows what changed. Open it again with /rolls news.",
            "Don't want it? Tick \"Don't show the changelog any more\" below.",
        },
        de = {
            "Neu: dieses Fenster. Nach einem Update zeigt es, was sich geändert hat. Wieder öffnen mit /rolls news.",
            "Nicht gewünscht? Unten \"Changelog nicht mehr anzeigen\" ankreuzen.",
        } },
    { "1.4.9",
        en = { "Uses less CPU: quest enemies are checked only once, events are only listened to while needed." },
        de = { "Braucht weniger CPU: Quest-Gegner werden nur einmal geprüft, Events nur abgehört, solange nötig." } },
    { "1.4.8",
        en = { "The quest item icon and the Undermine Real reminder now look the same." },
        de = { "Das Quest-Item-Symbol und die Undermine-Real-Erinnerung sehen jetzt gleich aus." } },
    { "1.4.7",
        en = { "Real reminder also for Blackmaw Hold and Shaper's Terrace. Bosses that give you a Real are learned automatically." },
        de = { "Real-Erinnerung auch für Blackmaw Hold und Shaper's Terrace. Bosse, die dir einen Real geben, lernt das Addon automatisch." } },
    { "1.4.6",
        en = {
            "Options: Quest loot and Undermine Reals are now one category, \"Loot icons\". The version is shown top right.",
            "/reals test shows the Real reminder, /reals debug prints boss kills in chat.",
        },
        de = {
            "Optionen: Quest-Beute und Undermine-Reals sind jetzt eine Kategorie, \"Loot-Symbole\". Oben rechts steht die Version.",
            "/reals test zeigt die Real-Erinnerung, /reals debug schreibt Bosskills in den Chat.",
        } },
    { "1.4.5",
        en = { "New: Undermine Real reminder. After the day's first kill of a Real boss, a blinking Real shows until you loot it. Right-click hides it. Settings: Options > Loot icons." },
        de = { "Neu: Undermine-Real-Erinnerung. Nach dem ersten Kill eines Real-Bosses am Tag blinkt ein Real, bis du lootest. Rechtsklick blendet ihn aus. Einstellungen: Optionen > Loot-Symbole." } },
    { "1.4.4",
        en = { "Undermine Reals window: the dungeon you are in opens by itself." },
        de = { "Undermine-Reals-Fenster: Der Dungeon, in dem du bist, klappt von selbst auf." } },
    { "1.4.3",
        en = { "\"Gold per dungeon in chat\" is a dropdown: all dungeons with the total, or one dungeon. Options > Roll history." },
        de = { "\"Gold pro Dungeon im Chat\" ist ein Dropdown: alle Dungeons mit Gesamt oder ein Dungeon. Optionen > Roll History." } },
    { "1.4.2",
        en = { "Undermine Reals window: search for a dungeon or boss, dungeons fold. Options: categories fold with a click, new category \"Windows\"." },
        de = { "Undermine-Reals-Fenster: Suche nach Dungeon oder Boss, Dungeons klappen zu. Optionen: Kategorien per Klick einklappbar, neue Kategorie \"Fenster\"." } },
    { "1.4.1",
        en = { "Quest item icon: after you kill an enemy that drops a quest item you need, its icon pops up. Options > Loot icons." },
        de = { "Quest-Item-Symbol: Nach dem Kill eines Gegners mit einem benötigten Quest-Item erscheint dessen Symbol. Optionen > Loot-Symbole." } },
    { "1.4.0",
        en = {
            "Enemies that drop an item your quest needs get a line in their tooltip.",
            "New window /reals: which bosses already gave you today's Tarnished Undermine Reals.",
        },
        de = {
            "Gegner, die ein Item für deine Quest droppen, bekommen eine Zeile im Tooltip.",
            "Neues Fenster /reals: welche Bosse dir heute schon Tarnished Undermine Reals gegeben haben.",
        } },
}

-------------------------------------------------------------------------------
--  Versions
-------------------------------------------------------------------------------
local function Parts(v)
    local a, b, c = tostring(v or ""):match("^(%d+)%.?(%d*)%.?(%d*)")
    return tonumber(a) or 0, tonumber(b) or 0, tonumber(c) or 0
end

-- true when version a is newer than b.
local function Newer(a, b)
    local a1, a2, a3 = Parts(a)
    local b1, b2, b3 = Parts(b)
    if a1 ~= b1 then return a1 > b1 end
    if a2 ~= b2 then return a2 > b2 end
    return a3 > b3
end

local function Current()
    local getMeta = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    return getMeta and getMeta(ADDON_NAME, "Version") or NOTES[1][1]
end

-- The notes since version `since` (all when nil), newest first, at most SHOW_MAX.
local function Since(since)
    local list = {}
    for _, n in ipairs(NOTES) do
        if not since or Newer(n[1], since) then list[#list + 1] = n end
        if #list >= SHOW_MAX then break end
    end
    return list
end

-------------------------------------------------------------------------------
--  Window
-------------------------------------------------------------------------------
local frame, scroll, content, text

local function Build()
    frame = St.Window("NibbelzLootWhatsNewFrame", 440, 360, L["What's new"], "whatsnew")
    frame:Place({ "CENTER", UIParent, "CENTER", 0, 80 })
    frame:SetFrameStrata("DIALOG")
    frame:Hide()
    tinsert(UISpecialFrames, "NibbelzLootWhatsNewFrame")

    local logo = frame.bar:CreateTexture(nil, "OVERLAY")
    logo:SetSize(16, 16)
    logo:SetPoint("LEFT", 10, 0)
    logo:SetTexture("Interface\\Icons\\INV_Misc_Coin_01")
    logo:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    frame.title:ClearAllPoints()
    frame.title:SetPoint("LEFT", logo, "RIGHT", 6, 0)

    -- The notes scroll (mouse wheel) when they are longer than the window.
    scroll = CreateFrame("ScrollFrame", nil, frame)
    scroll:SetPoint("TOPLEFT", 14, -38)
    scroll:SetPoint("BOTTOMRIGHT", -14, 72)
    content = CreateFrame("Frame", nil, scroll)
    content:SetSize(412, 10)
    scroll:SetScrollChild(content)
    text = St.Text(content, 12)
    text:SetPoint("TOPLEFT")
    text:SetWidth(408)
    text:SetJustifyH("LEFT")
    text:SetJustifyV("TOP")
    text:SetWordWrap(true)
    text:SetSpacing(3)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local range = self:GetVerticalScrollRange()
        self:SetVerticalScroll(max(0, min(range, self:GetVerticalScroll() - delta * 30)))
    end)

    local ok = St.Button(frame, L["Got it"], 110, 24, function() frame:Hide() end)
    ok:SetPoint("BOTTOMRIGHT", -12, 12)
    local opts = St.Button(frame, L["Options"], 110, 24, function()
        frame:Hide()
        ns.Options:Open()
    end)
    opts:SetPoint("RIGHT", ok, "LEFT", -8, 0)
    -- Switch the popup off for good (it can still be opened with /rolls news).
    frame.off = St.Checkbox(frame, L["Don't show the changelog any more"], function(on)
        ns.db.opts.whatsNewOff = on or nil
    end)
    frame.off:SetPoint("BOTTOMLEFT", 12, 42)
    frame.off:SetWidth(300)
    local hint = St.Text(frame, 10)
    hint:SetPoint("BOTTOMLEFT", 14, 19)
    hint:SetText(L["Again any time: /rolls news"])
    hint:SetTextColor(1, 1, 1, 0.4)
end

-- all: show the latest notes even without an update (/rolls news).
function WN:Show(all)
    local notes = Since((not all) and ns.db.seenVersion or nil)
    if #notes == 0 then notes = Since(nil) end
    if not frame then Build() end
    local r, g, b = St.Accent()
    local accent = format("|cff%02x%02x%02x", r * 255, g * 255, b * 255)
    local lines = {}
    for i, n in ipairs(notes) do
        if i > 1 then lines[#lines + 1] = " " end
        lines[#lines + 1] = accent .. "v" .. n[1] .. "|r"
        for _, line in ipairs(ns.IS_DE and n.de or n.en) do
            lines[#lines + 1] = "|cffd0d0d0-|r " .. line
        end
    end
    text:SetText(table.concat(lines, "\n"))
    content:SetHeight(text:GetStringHeight() + 6)
    scroll:SetVerticalScroll(0)
    frame.off:SetChecked(ns.db.opts.whatsNewOff == true)
    frame.title:SetText("|cffffd100Nibbelz|r Loot  |cff9a9a9a" .. format(L["What's new in v%s"], Current()) .. "|r")
    frame:Show()
    frame:Raise()
end

-------------------------------------------------------------------------------
--  At login: once per new version
-------------------------------------------------------------------------------
local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function()
    if not ns.db then return end
    local db, cur = ns.db, Current()
    local seen = db.seenVersion
    -- Switched off in the popup: just note the version, show nothing.
    if db.opts.whatsNewOff then
        db.seenVersion = cur
        return
    end
    if not seen then
        -- No version noted yet: an update from before this window existed if there
        -- is already data, else a fresh install (nothing to show).
        local used = (#(db.rolls or {}) > 0) or (#(db.visits or {}) > 0)
        db.seenVersion = cur
        if used then
            C_Timer.After(4, function() WN:Show(true) end)
        end
        return
    end
    if Newer(cur, seen) then
        C_Timer.After(4, function()
            WN:Show()
            db.seenVersion = cur
        end)
    end
end)
