-- Quest hubs: the places where you arrive to level (Grom'gol, Nesingwary's
-- camp...) and the quests to pick up there, so arriving in a new zone starts
-- with "pick up these" instead of the first quest in the log. Pure Lua 5.1.
--
-- Forever gives addons no list of a place's quests, so the hubs ship as data
-- (data/Hubs.lua): which quests (by id) to take at each place, for which
-- levels and faction. These are facts of the game, gathered from public
-- levelling guides (the TUGs guides for Forever, Wowhead). The quest names
-- come from the game at run time, and where each quest giver stands is
-- learned while playing (core/Atlas.lua); until then the hub itself is the
-- target.
--
-- hub = { mapID, name, faction (nil: both), x, y (the hub on its map),
--         min, max (levels), pickup = { questID, ... },
--         optional = { questID, ... } (elite or group quests) }

local _, ns = ...

local Hubs = {}
ns.Hubs = Hubs

Hubs.EARLY = 3 -- a hub is shown from this many levels below its range

--- The hubs of a map that suit this faction and level, in the data's order.
function Hubs.forZone(hubs, mapID, faction, level)
  local out = {}
  for _, h in ipairs(hubs or {}) do
    if h.mapID == mapID and (h.faction == nil or h.faction == faction)
      and level >= (h.min or 1) - Hubs.EARLY and level <= (h.max or 60) then
      out[#out + 1] = h
    end
  end
  return out
end

--- The quests still to pick up at a hub: { questID, optional } in order.
--- ctx = { inLog(id), isDone(id) }.
function Hubs.pending(hub, ctx)
  local out = {}
  local function add(list, optional)
    for _, id in ipairs(list or {}) do
      if not ctx.inLog(id) and not ctx.isDone(id) then
        out[#out + 1] = { questID = id, optional = optional }
      end
    end
  end
  add(hub.pickup, false)
  add(hub.optional, true)
  return out
end
