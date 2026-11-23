-- Dungeons by level: which ones suit you now, the quests to take with you
-- before going in, and a plan that walks you to each quest giver, then to
-- the entrance, then back to hand the quests in. The data (data/Dungeons.lua)
-- holds the enemies' levels, the entrances and the quests; this file only
-- decides. Plain Lua, no game API.

local _, ns = ...

local Dungeons = {}
ns.Dungeons = Dungeons

-- A dungeon suits you from a little under its enemies' lowest level (with a
-- group) to a little over its strongest boss (still worth the experience).
Dungeons.BELOW = 2
Dungeons.ABOVE = 3

local CLASS_BITS = {
  WARRIOR = 1, PALADIN = 2, HUNTER = 4, ROGUE = 8, PRIEST = 16, SHAMAN = 64, MAGE = 128, WARLOCK = 256,
  DRUID = 1024,
}

local function sideOf(who)
  local f = who and who.faction
  return (f == "Horde" and "H") or (f == "Alliance" and "A") or nil
end

local function hasBit(mask, bit)
  return math.floor(mask / bit) % 2 == 1
end

--- True if this character's faction can reach the dungeon (Ragefire Chasm
--- is inside Orgrimmar, The Stockade inside Stormwind).
function Dungeons.open(d, who)
  local s = sideOf(who)
  return d.side == nil or s == nil or d.side == s
end

--- True if the quest is for this character's faction and class.
function Dungeons.questFits(q, who)
  local s = sideOf(who)
  if q.side and s and q.side ~= s then
    return false
  end
  local bit = q.classes and who and CLASS_BITS[who.class]
  if bit and not hasBit(q.classes, bit) then
    return false
  end
  return true
end

--- True if the level suits the dungeon.
function Dungeons.suits(d, level)
  return level >= d.min - Dungeons.BELOW and level <= d.max + Dungeons.ABOVE
end

--- The dungeons for this character at this level, in the order players
--- meet them, and the next one to come (or nil).
function Dungeons.forLevel(list, who, level)
  local now, nextOne = {}, nil
  for _, d in ipairs(list or {}) do
    if Dungeons.open(d, who) then
      if Dungeons.suits(d, level) then
        now[#now + 1] = d
      elseif not nextOne and d.min - Dungeons.BELOW > level then
        nextOne = d
      end
    end
  end
  return now, nextOne
end

--- The dungeon's quests for this character, sorted out:
---   ready:  pick them up before going in (the giver stands outside);
---   inside: they start in the dungeon or from an item found there;
---   later:  { quest, level = needed } or { quest, after = quest id first }.
--- done(id) says whether a quest was already handed in.
function Dungeons.quests(d, who, level, done)
  done = done or function()
    return false
  end
  local ready, inside, later, seen = {}, {}, {}, {}
  for _, q in ipairs(d.quests or {}) do
    if Dungeons.questFits(q, who) and not done(q.q) and not seen[q.name] then
      seen[q.name] = true
      local preDone = not q.pre
      for _, p in ipairs(q.pre or {}) do
        preDone = preDone or done(p)
      end
      if not preDone then
        later[#later + 1] = { quest = q, after = q.pre[1] }
      elseif q.req and q.req > level then
        later[#later + 1] = { quest = q, level = q.req }
      elseif not q.m or q.m == d.inside then
        inside[#inside + 1] = q
      else
        ready[#ready + 1] = q
      end
    end
  end
  return ready, inside, later
end

--- The entrance to use: the nearest one when distance(point) gives yards
--- (nil when it cannot tell), else the first.
function Dungeons.entrance(d, distance)
  local best, bestYards = d.entrances[1], nil
  for _, e in ipairs(distance and d.entrances or {}) do
    local yards = distance(e)
    if yards and (not bestYards or yards < bestYards) then
      best, bestYards = e, yards
    end
  end
  return best
end

--- A plan for the dungeon: pick up the quests, go to the entrance, hand the
--- quests in. ctx: { who, level, done, L, distance }.
function Dungeons.toPlan(d, ctx)
  local L = ctx.L
  -- Quests that start inside are not steps: you may never find their item.
  local ready = Dungeons.quests(d, ctx.who, ctx.level, ctx.done)
  local steps = {}
  for _, q in ipairs(ready) do
    steps[#steps + 1] = { id = "a" .. q.q, type = "accept", questID = q.q, text = L["Pick up: "] .. q.name,
      why = q.npc and L["From %s"]:format(q.npc) or nil, mapID = q.m, x = q.x, y = q.y }
  end
  local e = Dungeons.entrance(d, ctx.distance)
  steps[#steps + 1] = { id = "entrance", type = "goto", soft = true, mapID = e.m, x = e.x, y = e.y,
    text = L["Go to the entrance of %s"]:format(d.name),
    why = L["Enemies of level %d-%d: go with a group."]:format(d.min, d.max) }
  local function turnin(q)
    local step = { id = "t" .. q.q, type = "turnin", questID = q.q, text = L["Turn in: "] .. q.name,
      why = q.tnpc and L["To %s"]:format(q.tnpc) or nil }
    if q.tm and q.tm ~= d.inside then
      step.mapID, step.x, step.y = q.tm, q.tx, q.ty
    end
    steps[#steps + 1] = step
  end
  for _, q in ipairs(ready) do
    turnin(q)
  end
  return { version = 1, id = "dungeon-" .. d.id, title = d.name, steps = steps }
end

--- True if a plan was made for a dungeon.
function Dungeons.isDungeon(plan)
  return type(plan) == "table" and type(plan.id) == "string" and plan.id:find("^dungeon%-") ~= nil
end

--- The dungeon whose inside map is mapID, or the one called name (the
--- game's instance name, when the map is not known), or nil.
function Dungeons.here(list, mapID, name)
  for _, d in ipairs(list or {}) do
    if (mapID and d.inside == mapID) or (name and d.name == name) then
      return d
    end
  end
  return nil
end

--- The quests of this dungeon in the quest log ({ [questID] = { complete } })
--- with something still to do inside: { { q, name, targets } }. Handed in or done
--- ones are not listed (they are done outside).
function Dungeons.toDoHere(d, questLog)
  local out = {}
  for _, q in ipairs(d and d.quests or {}) do
    local entry = questLog and questLog[q.q]
    if entry and not entry.complete then
      out[#out + 1] = { q = q.q, name = q.name, targets = q.targets }
    end
  end
  return out
end
