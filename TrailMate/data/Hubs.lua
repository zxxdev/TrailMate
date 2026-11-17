-- Quest hubs and the quests to pick up there (see core/Hubs.lua).
--
-- Source: which quests are taken where, from the TUGs levelling guides for
-- WoW Forever ("written by TUGs and is totally free"). Only facts of the
-- game are kept here: places, levels and quest ids. The names in comments
-- are the classic ones, for reading; the game shows its own. Hub positions
-- are the classic map's (0 to 1, Grom'gol's flight master from the guide,
-- Nesingwary's camp from the classic map), not checked in Forever: they are
-- only where the arrow points until TrailMate learns where each quest giver
-- stands.

local _, ns = ...

ns.HUBS = {
  -- Stranglethorn Vale (1434), Horde, levels 30-40.
  {
    mapID = 1434, name = "Grom'gol Base Camp", faction = "Horde", x = 0.326, y = 0.292, min = 30, max = 40,
    pickup = {
      581, -- Hunt for Yenniku
      596, -- Bloody Bone Necklaces
      638, -- Trollbane
    },
    optional = {
      629, -- The Vile Reef (elite)
    },
  },
  {
    mapID = 1434, name = "Nesingwary's Expedition", x = 0.357, y = 0.108, min = 30, max = 42,
    pickup = {
      583, -- Welcome to the Jungle
      185, -- Tiger Mastery
      190, -- Panther Mastery
      194, -- Raptor Mastery
    },
  },
}
