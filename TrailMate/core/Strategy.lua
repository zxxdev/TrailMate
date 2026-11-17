-- Leveling strategy: where you should be for your level, what else works,
-- how hard each option is, and what opens up next. Pure Lua 5.1, from the
-- zone table and the quests you actually have; nothing comes from a guide.

local _, ns = ...

local Strategy = {}
ns.Strategy = Strategy

-- Levels before the end of a zone's range when it starts to be outgrown,
-- below its start when it is still too dangerous, and how far ahead to look.
Strategy.EDGE = 3
Strategy.TOO_LOW = 2
Strategy.SOON = 4

--- How well a zone suits a level: 3 right in range, 1 at either edge,
--- 0 outgrown, nil when it is still too dangerous.
function Strategy.fit(zone, level)
  if level < zone.min - Strategy.TOO_LOW then
    return nil
  end
  if level >= zone.max then
    return 0
  end
  if level < zone.min or level >= zone.max - Strategy.EDGE then
    return 1
  end
  return 3
end

--- "easy", "normal" or "hard" for a zone at a level: where the level sits in
--- the zone's range. Lets the player pick something calmer or tougher.
function Strategy.difficulty(zone, level)
  local span = math.max(1, zone.max - zone.min)
  local pos = (level - zone.min) / span
  if pos < 0.3 then
    return "hard"
  elseif pos > 0.7 then
    return "easy"
  end
  return "normal"
end

--- Extra points a zone gets when the route picks where to work: its fit for
--- the level, and a penalty if it is still too dangerous.
function Strategy.zoneBonus(level)
  return function(mapID)
    local zone = ns.Zones.LIST[mapID]
    if not zone or type(level) ~= "number" then
      return 0
    end
    return Strategy.fit(zone, level) or -3
  end
end

--- Zones ranked for the player:
--- { mapID, name, min, max, fit, difficulty, quests, score }.
--- counts[mapID] = quests worth doing there that are already in the log.
function Strategy.rank(level, faction, here, counts)
  local out = {}
  for mapID, zone in pairs(ns.Zones.LIST) do
    if ns.Zones.forFaction(zone, faction) then
      local fit = Strategy.fit(zone, level)
      if fit and fit > 0 then
        local quests = counts and counts[mapID] or 0
        out[#out + 1] = {
          mapID = mapID, name = zone.name, min = zone.min, max = zone.max, fit = fit,
          difficulty = Strategy.difficulty(zone, level), quests = quests,
          score = fit * 2 + quests * 2 + (mapID == here and 2 or 0),
        }
      end
    end
  end
  table.sort(out, function(a, b)
    if a.score ~= b.score then
      return a.score > b.score
    end
    return a.mapID < b.mapID
  end)
  return out
end

--- Zones that open up within a few levels, by starting level.
function Strategy.upcoming(level, faction)
  local out = {}
  for mapID, zone in pairs(ns.Zones.LIST) do
    if ns.Zones.forFaction(zone, faction) and zone.min > level and zone.min <= level + Strategy.SOON then
      out[#out + 1] = { mapID = mapID, name = zone.name, min = zone.min, max = zone.max }
    end
  end
  table.sort(out, function(a, b)
    if a.min ~= b.min then
      return a.min < b.min
    end
    return a.mapID < b.mapID
  end)
  return out
end

--- The whole advice: { best, options = {...}, upcoming = {...}, leaveHere }.
--- options are the other zones that suit you, best first. leaveHere is true
--- when the zone you are in is outgrown for your level.
function Strategy.advise(level, faction, here, counts)
  local ranked = Strategy.rank(level, faction, here, counts)
  local options = {}
  for i = 2, #ranked do
    options[#options + 1] = ranked[i]
  end
  local hereZone = ns.Zones.LIST[here or -1]
  return {
    best = ranked[1],
    options = options,
    upcoming = Strategy.upcoming(level, faction),
    leaveHere = hereZone ~= nil and Strategy.fit(hereZone, level) == 0,
  }
end
