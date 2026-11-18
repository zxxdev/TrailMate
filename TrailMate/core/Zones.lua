-- Leveling zones: level range and who has quest hubs there. Pure Lua 5.1.
--
-- These are the classic level ranges, general knowledge about the game, not
-- taken from any guide. WoW Forever adds quests and may shift some ranges:
-- they are NOT yet confirmed in Forever and are only used to weigh zones,
-- never to hide what the game itself shows.
--
-- side: "H" Horde, "A" Alliance, "AH" both. Keys are the game's uiMapIDs.

local _, ns = ...

local Zones = {}
ns.Zones = Zones

Zones.VERIFIED_IN_FOREVER = false

Zones.LIST = {
  [1411] = { name = "Durotar", min = 1, max = 10, side = "H" },
  [1412] = { name = "Mulgore", min = 1, max = 10, side = "H" },
  [1420] = { name = "Tirisfal Glades", min = 1, max = 10, side = "H" },
  [1429] = { name = "Elwynn Forest", min = 1, max = 10, side = "A" },
  [1426] = { name = "Dun Morogh", min = 1, max = 10, side = "A" },
  [1438] = { name = "Teldrassil", min = 1, max = 10, side = "A" },
  [1413] = { name = "The Barrens", min = 10, max = 25, side = "H" },
  [1421] = { name = "Silverpine Forest", min = 10, max = 20, side = "H" },
  [1436] = { name = "Westfall", min = 10, max = 20, side = "A" },
  [1432] = { name = "Loch Modan", min = 10, max = 20, side = "A" },
  [1439] = { name = "Darkshore", min = 10, max = 20, side = "A" },
  [1433] = { name = "Redridge Mountains", min = 15, max = 25, side = "A" },
  [1442] = { name = "Stonetalon Mountains", min = 15, max = 27, side = "AH" },
  [1440] = { name = "Ashenvale", min = 18, max = 30, side = "AH" },
  [1431] = { name = "Duskwood", min = 18, max = 30, side = "A" },
  [1424] = { name = "Hillsbrad Foothills", min = 20, max = 30, side = "AH" },
  [1437] = { name = "Wetlands", min = 20, max = 30, side = "A" },
  [1441] = { name = "Thousand Needles", min = 25, max = 35, side = "AH" },
  [1416] = { name = "Alterac Mountains", min = 30, max = 40, side = "AH" },
  [1417] = { name = "Arathi Highlands", min = 30, max = 40, side = "AH" },
  [1443] = { name = "Desolace", min = 30, max = 40, side = "AH" },
  [1434] = { name = "Stranglethorn Vale", min = 30, max = 45, side = "AH" },
  [1445] = { name = "Dustwallow Marsh", min = 35, max = 45, side = "AH" },
  [1418] = { name = "Badlands", min = 35, max = 45, side = "AH" },
  [1435] = { name = "Swamp of Sorrows", min = 35, max = 45, side = "AH" },
  [1444] = { name = "Feralas", min = 40, max = 50, side = "AH" },
  [1446] = { name = "Tanaris", min = 40, max = 50, side = "AH" },
  [1425] = { name = "The Hinterlands", min = 40, max = 50, side = "AH" },
  [1427] = { name = "Searing Gorge", min = 43, max = 50, side = "AH" },
  [1447] = { name = "Azshara", min = 45, max = 55, side = "AH" },
  [1419] = { name = "Blasted Lands", min = 45, max = 55, side = "AH" },
  [1449] = { name = "Un'Goro Crater", min = 48, max = 55, side = "AH" },
  [1448] = { name = "Felwood", min = 48, max = 55, side = "AH" },
  [1428] = { name = "Burning Steppes", min = 50, max = 58, side = "AH" },
  [1422] = { name = "Western Plaguelands", min = 51, max = 58, side = "AH" },
  [1423] = { name = "Eastern Plaguelands", min = 53, max = 60, side = "AH" },
  [1452] = { name = "Winterspring", min = 53, max = 60, side = "AH" },
  [1451] = { name = "Silithus", min = 55, max = 60, side = "AH" },
}

--- True if the zone has quest hubs for the faction ("Horde"/"Alliance").
function Zones.forFaction(zone, faction)
  local letter = faction == "Horde" and "H" or faction == "Alliance" and "A" or nil
  return letter == nil or zone.side:find(letter, 1, true) ~= nil
end
