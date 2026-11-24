-- Class quests as side quests: which ones this character can pick up now
-- (totems, pets, forms, stances, mounts...), which open at a later level,
-- and a plan that walks to the quest giver and back to hand it in. The data
-- (data/ClassQuests.lua) holds the quests; this file only decides. Plain
-- Lua, no game API.

local _, ns = ...

local ClassQuests = {}
ns.ClassQuests = ClassQuests

local function hasBit(mask, bit)
  return math.floor(mask / bit) % 2 == 1
end

--- The race bit the database uses for a race id of the game (UnitRace's
--- third value): 2 ^ (id - 1). nil for an unknown id.
function ClassQuests.raceBit(raceID)
  if type(raceID) ~= "number" or raceID < 1 then
    return nil
  end
  return 2 ^ (raceID - 1)
end

--- True if the quest is for this race (or for every race, or the race is
--- not known).
function ClassQuests.raceFits(q, raceBit)
  return q.races == nil or raceBit == nil or hasBit(q.races, raceBit)
end

--- What a quest is for this character now. ctx: { level, raceBit,
--- done(id) handed in, inLog(id) in the quest log }. One of:
---   "race": not for this race;   "done": handed in;   "log": in the log;
---   "gone": closed by another quest taken (or its target, for a breadcrumb);
---   "pre": needs a quest handed in first;   "level": needs a higher level;
---   "ready": can be picked up now.
function ClassQuests.status(q, ctx)
  if not ClassQuests.raceFits(q, ctx.raceBit) then
    return "race"
  end
  if ctx.done(q.q) then
    return "done"
  end
  if ctx.inLog(q.q) then
    return "log"
  end
  local function had(id)
    return ctx.done(id) or ctx.inLog(id)
  end
  if q.crumb and had(q.crumb) then
    return "gone"
  end
  for _, x in ipairs(q.excl or {}) do
    if had(x) then
      return "gone"
    end
  end
  if q.pre then
    local ok = false
    for _, p in ipairs(q.pre) do
      ok = ok or ctx.done(p)
    end
    if not ok then
      return "pre"
    end
  end
  for _, p in ipairs(q.preAll or {}) do
    if not ctx.done(p) then
      return "pre"
    end
  end
  if q.req > ctx.level then
    return "level"
  end
  return "ready"
end

-- A nearer version of a quest that opens this many levels later is worth
-- the wait: a troll shaman takes Call of Earth in the Valley of Trials at
-- 4, not on Zephras Isle at 3.
ClassQuests.WAIT_LEVELS = 2

-- One quest per name: the same step is often offered by several trainers
-- (one per capital). Keeps the nearest when distance(q) gives yards, else
-- the first.
local function oneByName(list, distance)
  local out, at, yards = {}, {}, {}
  for _, q in ipairs(list) do
    local d = distance and distance(q) or nil
    local i = at[q.name]
    if not i then
      out[#out + 1] = q
      at[q.name], yards[q.name] = #out, d
    elseif d and (not yards[q.name] or d < yards[q.name]) then
      out[i], yards[q.name] = q, d
    end
  end
  return out
end

-- The quests to offer at ctx.level: one per name with the nearest giver;
-- a name waits when its nearest giver opens within WAIT_LEVELS levels.
-- Also returns the lowest level a waiting quest needs (or nil).
local function offer(quests, ctx)
  local ready, waiting, nextLevel = {}, {}, nil
  for _, q in ipairs(quests or {}) do
    local s = ClassQuests.status(q, ctx)
    if s == "ready" then
      ready[#ready + 1] = q
    elseif s == "level" then
      waiting[#waiting + 1] = q
      nextLevel = math.min(nextLevel or q.req, q.req)
    end
  end
  -- Ready and soon-to-open quests compete by name: if the nearest is not
  -- open yet, that name waits.
  local candidates = {}
  for _, q in ipairs(ready) do
    candidates[#candidates + 1] = q
  end
  for _, q in ipairs(waiting) do
    if q.req <= ctx.level + ClassQuests.WAIT_LEVELS then
      candidates[#candidates + 1] = q
    end
  end
  local open = {}
  for _, q in ipairs(oneByName(candidates, ctx.distance)) do
    if q.req <= ctx.level then
      open[#open + 1] = q
    end
  end
  ready = open
  -- A breadcrumb only leads to another quest: if that one can be picked up
  -- too, go straight to it.
  local readyIds, direct = {}, {}
  for _, q in ipairs(ready) do
    readyIds[q.q] = true
  end
  for _, q in ipairs(ready) do
    if not (q.crumb and readyIds[q.crumb]) then
      direct[#direct + 1] = q
    end
  end
  -- Nearest to the character's level first: a starting zone's letter last.
  table.sort(direct, function(a, b)
    if a.level ~= b.level then
      return a.level > b.level
    end
    return a.q < b.q
  end)
  return direct, nextLevel
end

--- The class quests for this character: ready (can be picked up now, one
--- per name with the nearest giver, highest level first), and soon with its
--- level: what will be offered at the next level that brings anything new,
--- by the same rules. quests: the class's list (ns.CLASS_QUESTS[class]);
--- ctx as in status, plus distance(q).
function ClassQuests.forNow(quests, ctx)
  local ready, level = offer(quests, ctx)
  local now = {}
  for _, q in ipairs(ready) do
    now[q.name] = true
  end
  -- Each later level where some quest opens, until one offers a new name.
  while level do
    local later = {}
    for k, v in pairs(ctx) do
      later[k] = v
    end
    later.level = level
    local list, after = offer(quests, later)
    local soon = {}
    for _, q in ipairs(list) do
      if not now[q.name] then
        soon[#soon + 1] = q
      end
    end
    if #soon > 0 then
      return ready, soon, level
    end
    level = after
  end
  return ready, {}, nil
end

--- The ready quests not yet told about (seen: { [questID] = true }).
function ClassQuests.news(ready, seen)
  local out = {}
  for _, q in ipairs(ready) do
    if not (seen and seen[q.q]) then
      out[#out + 1] = q
    end
  end
  return out
end

--- A plan for one class quest: go to the giver and pick it up, do it, then
--- hand it in where the database says (when it knows). ctx: { L }.
function ClassQuests.toPlan(q, ctx)
  local L = ctx.L
  local steps = {
    { id = "a" .. q.q, type = "accept", questID = q.q, text = L["Pick up: "] .. q.name,
      why = q.npc and L["From %s"]:format(q.npc) or nil, mapID = q.m, x = q.x, y = q.y,
      creature = q.cid, who = q.npc, model = q.model },
  }
  -- Where the objectives are is not in the data: the quest text says.
  steps[2] = { id = "c" .. q.q, type = "complete", questID = q.q, text = L["Do: "] .. q.name }
  local turnin = { id = "t" .. q.q, type = "turnin", questID = q.q, text = L["Turn in: "] .. q.name,
    why = q.tnpc and L["To %s"]:format(q.tnpc) or nil, creature = q.tcid, who = q.tnpc,
    model = q.tmodel }
  if q.tm then
    turnin.mapID, turnin.x, turnin.y = q.tm, q.tx, q.ty
  end
  steps[3] = turnin
  return { version = 1, id = "class-" .. q.q, title = q.name, steps = steps }
end

--- True if a plan was made for a class quest.
function ClassQuests.isClassQuest(plan)
  return type(plan) == "table" and type(plan.id) == "string" and plan.id:find("^class%-") ~= nil
end
