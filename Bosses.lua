-- Bosses.lua: the last boss of every WoW Forever dungeon (and wing). When one of
-- them dies, a running loot battle is scored.
-- Source: NaowhForever_DungeonJournal's dungeon data (encounter IDs, NPC IDs, boss
-- order). The last regular boss of each wing; Deadmines (VanCleef), Sunken Temple
-- (Shade of Eranikus) and Blackrock Depths (the Emperor) use the classic end boss.
-- Barrow Deeps and Hyjal Summit have no encounter IDs there: matched by name.
local _, ns = ...

-- { dungeon, boss, npc, instance map ID, encounter IDs }
local LIST = {
    { "Alcaz Prison", "Blazeroar", 255702, 2994, { 3409 } },
    { "The Barrow Deeps", "Sonya Darkhallow", 259912, nil, {} },
    { "Blackfathom Deeps", "Aku'mai", 4829, 48, { 2910, 2767 } },
    { "Blackmaw Hold", "Unbound Spirit", 247231, 2974, { 3336 } },
    { "Blackrock Depths", "Emperor Dagran Thaurissan", 9019, 230, { 2790 } },
    { "City of Dalaran", "Shade of the Archmage", 246020, 2959, { 3303 } },
    { "The Deadmines", "Edwin VanCleef", 639, 36, { 2747 } },
    { "Dire Maul - East", "Alzzin the Wildshaper", 11492, 429, { 346 } },
    { "Dire Maul - West", "Prince Tortheldrin", 11486, 429, { 361 } },
    { "Dire Maul - North", "King Gordok", 11501, 429, { 368 } },
    { "The Drowned City", "Min'loth the Serpent", 270886, 2970, { 3479 } },
    { "Excavation Site: Wetlands", "Relic Guardian", 260326, 2998, { 3482 } },
    { "Gnomeregan", "Mekgineer Thermaplugg", 7800, 90, { 2772 } },
    { "The Hall of Thanes", "Durgen Dirgehammer", 261319, 3065, { 3496 } },
    { "Hyjal Summit", "The Wild King", 250079, nil, {} },
    { "Krol'dok Stronghold", "Overlord Mugg", 258968, 3039, { 3451 } },
    { "Lower Blackrock Spire", "Overlord Wyrmthalak", 9568, 229, { 275 } },
    { "Maraudon", "Princess Theradras", 12201, 349, { 429 } },
    { "Onyxia's Lair", "Onyxia", 10184, 249, { 1084 } },
    { "Ragefire Chasm", "Bazzalan", 11519, 389, { 2735 } },
    { "Razorfen Downs", "Amnennar the Coldbringer", 7358, 129, { 2785 } },
    { "Razorfen Kraul", "Charlga Razorflank", 4421, 47, { 2778 } },
    { "Ruins of Lordaeron", "Rath'mael", 250657, 2999, { 3354 } },
    { "Scarlet Monastery - Armory", "Herod", 3975, 189, { 448 } },
    { "Scarlet Monastery - Cathedral", "High Inquisitor Whitemane", 3977, 189, { 450 } },
    { "Scarlet Monastery - Graveyard", "Bloodmage Thalnos", 4543, 189, { 2779 } },
    { "Scarlet Monastery - Library", "Arcanist Doan", 6487, 189, { 447 } },
    { "Scholomance", "Darkmaster Gandling", 1853, 289, { 2801 } },
    { "Shadowfang Keep", "Archmage Arugal", 4275, 33, { 2755 } },
    { "Shaper's Terrace", "Nanaya", 261809, 3001, { 3502 } },
    { "The Stockade", "Dextren Ward", 1663, 34, { 2759 } },
    { "Stratholme - Main Gate", "Balnazzar", 10813, 329, { 478 } },
    { "Stratholme - Service Entrance", "Baron Rivendare", 10440, 329, { 484 } },
    { "Sunken Temple", "Shade of Eranikus", 5709, 109, { 3584, 493 } },
    { "Uldaman", "Archaedas", 2748, 70, { 554 } },
    { "Upper Blackrock Spire", "General Drakkisath", 10363, 229, { 3069 } },
    { "Wailing Caverns", "Mutanus the Devourer", 3654, 43, { 592 } },
    { "Zul'Farrak", "Chief Ukorz Sandscalp", 7267, 209, { 600 } },
}

local byEncounter, byName, byInstance = {}, {}, {}

-- The boss name in the client's language, from NaowhForever's journal when it has one.
local function LocalName(entry)
    local naowh = _G.NaowhForever
    local names = naowh and naowh.Journal and naowh.Journal.Names and naowh.Journal.Names.npcs
    return names and entry.npc and names[entry.npc] or entry.boss
end

for _, e in ipairs(LIST) do
    local entry = { dungeon = e[1], boss = e[2], npc = e[3], instance = e[4] }
    for _, id in ipairs(e[5]) do byEncounter[id] = entry end
    byName[e[2]:lower()] = entry
    if e[4] then
        byInstance[e[4]] = byInstance[e[4]] or {}
        table.insert(byInstance[e[4]], entry)
    end
end

-- Is this encounter (ID or name) a dungeon's last boss? Returns its entry.
function ns.FinalBoss(encounterID, encounterName)
    local entry = encounterID and byEncounter[encounterID]
    if entry then return entry end
    if type(encounterName) == "string" then
        local name = encounterName:lower()
        if byName[name] then return byName[name] end
        for _, e in pairs(byName) do
            if LocalName(e):lower() == name then return e end
        end
    end
end

-- The last boss(es) of an instance, for display: "Amnennar the Coldbringer".
function ns.FinalBossNames(instanceID)
    local list = instanceID and byInstance[instanceID]
    if not list then return nil end
    local names = {}
    for _, e in ipairs(list) do names[#names + 1] = LocalName(e) end
    return table.concat(names, " / ")
end
