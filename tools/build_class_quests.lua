-- Builds TrailMate/data/ClassQuests.lua: the quests of each class (totems,
-- pets, forms, stances, mounts...) from level 1 to 59, with who gives them,
-- where, what they need first and who takes them back.
--
-- Everything comes from the Questie database for Forever (read with
-- tools/questdb.lua): a class quest is one whose class field names exactly
-- one class. Level 60 quests (raid sets and the like) are left out: TrailMate
-- is for levelling. Runs in the VM only:
--
--   lua tools/build_class_quests.lua <questdb folder>         writes the file
--   lua tools/build_class_quests.lua <questdb folder> --ids   lists the ids
--
-- The folder holds QuestieDB_Forever.toc and areaIdToUiMapId.lua. The --ids
-- list is what was checked against Wowhead's Forever database (see
-- NOT_IN_FOREVER).

package.path = "tools/?.lua;" .. package.path
local Q = require("questdb")

local qdbDir = arg[1]
assert(qdbDir, "usage: lua tools/build_class_quests.lua <questdb folder> [--ids]")
local db = Q.open(qdbDir .. "/QuestieDB_Forever.toc", qdbDir .. "/areaIdToUiMapId.lua")

-- The class bits of the database, as the game names the classes.
local CLASSES = {
  { "WARRIOR", 1 }, { "PALADIN", 2 }, { "HUNTER", 4 }, { "ROGUE", 8 }, { "PRIEST", 16 }, { "SHAMAN", 64 },
  { "MAGE", 128 }, { "WARLOCK", 256 }, { "DRUID", 1024 },
}
local MAX_LEVEL = 59

-- Class quests Wowhead's Forever database does not have: its tooltip
-- service said "not found" for these on 2026-11-22, of the ids --ids lists.
local NOT_IN_FOREVER = {
  [2358] = true, -- Horns of Nez'ra (rogue, Redridge)
}

local function hasBit(mask, bit)
  return math.floor(mask / bit) % 2 == 1
end

-- The one class a mask names, or nil (none, several, or all).
local function onlyClass(mask)
  if type(mask) ~= "number" or mask <= 0 then
    return nil
  end
  local found
  for _, c in ipairs(CLASSES) do
    if hasBit(mask, c[2]) then
      if found then
        return nil
      end
      found = c[1]
    end
  end
  return found
end

local function ids(v)
  local list = {}
  for _, id in ipairs(type(v) == "table" and v or {}) do
    if type(id) == "number" then
      list[#list + 1] = id
    end
  end
  table.sort(list)
  return #list > 0 and list or nil
end

local all = {}
for key in pairs(db.lines) do
  local id = key:match("^Quest%-(%d+)%-S$")
  if id then
    all[#all + 1] = tonumber(id)
  end
end
table.sort(all)

local byClass, dropped = {}, { level = 0, place = 0, negative = 0, absent = 0 }
local listIds = arg[2] == "--ids"
for _, id in ipairs(all) do
  local r = Q.row(db, "Quest", id)
  local class = r and onlyClass(Q.field(db, "Quest", id, Q.QUEST.requiredClasses))
  if class then
    local req = r[Q.QUEST.requiredLevel]
    req = type(req) == "number" and req > 0 and req or 1
    local level = r[Q.QUEST.questLevel]
    -- -1: the quest takes the player's level; show it at the level it opens.
    level = type(level) == "number" and level > 0 and level or req
    local q = { q = id, name = r[Q.QUEST.name], level = level, req = req,
      pre = ids(Q.field(db, "Quest", id, Q.QUEST.preQuestSingle)),
      preAll = ids(Q.field(db, "Quest", id, Q.QUEST.preQuestGroup)),
      excl = ids(Q.field(db, "Quest", id, Q.QUEST.exclusiveTo)),
      crumb = Q.field(db, "Quest", id, Q.QUEST.breadcrumbFor) }
    local races = Q.field(db, "Quest", id, Q.QUEST.requiredRaces)
    if type(races) == "number" and races > 0 then
      q.races = races
    end
    local start, startName = Q.giver(db, Q.field(db, "Quest", id, Q.QUEST.startedBy))
    if start then
      q.m, q.x, q.y = start.m, start.x, start.y
    end
    q.npc = startName
    local finish, finishName = Q.giver(db, Q.field(db, "Quest", id, Q.QUEST.finishedBy))
    if finish then
      q.tm, q.tx, q.ty = finish.m, finish.x, finish.y
    end
    q.tnpc = finishName
    local negative = false
    for _, list in ipairs({ q.pre or {}, q.preAll or {} }) do
      for _, p in ipairs(list) do
        negative = negative or p < 0
      end
    end
    if level > MAX_LEVEL or req > MAX_LEVEL then
      dropped.level = dropped.level + 1
    elseif not q.m then
      -- Started by an item or by nobody known: nowhere to send the player.
      dropped.place = dropped.place + 1
    elseif negative then
      -- "Must not have done this one first": not a rule TrailMate reads.
      dropped.negative = dropped.negative + 1
    elseif listIds then
      print(id)
    elseif NOT_IN_FOREVER[id] then
      dropped.absent = dropped.absent + 1
    else
      byClass[class] = byClass[class] or {}
      table.insert(byClass[class], q)
    end
  end
end
if listIds then
  return
end

-- Output ------------------------------------------------------------------------

local function quote(s)
  return ("%q"):format(s):gsub("\\\n", "\\n")
end

local function list(v)
  return "{ " .. table.concat(v, ", ") .. " }"
end

local out = assert(io.open("TrailMate/data/ClassQuests.lua", "w"))
out:write([[
-- The class quests of WoW Forever from level 1 to 59, by class. Generated by
-- tools/build_class_quests.lua from the Questie database for Forever: do not
-- edit by hand.
--
-- Quest fields: q id, level, req (level to pick it up), races (bit mask of
-- the races it is for, or all), pre (one of these handed in first), preAll
-- (all of them), excl (taking one of these closes this one), crumb (this
-- quest only leads to that one), m/x/y and npc where it starts, tm/tx/ty and
-- tnpc where it is handed in.

local _, ns = ...

ns.CLASS_QUESTS = {
]])
local total = 0
for _, c in ipairs(CLASSES) do
  local quests = byClass[c[1]] or {}
  table.sort(quests, function(a, b)
    if a.req ~= b.req then
      return a.req < b.req
    end
    if a.level ~= b.level then
      return a.level < b.level
    end
    return a.q < b.q
  end)
  out:write(("  %s = {\n"):format(c[1]))
  for _, q in ipairs(quests) do
    local parts = { ("q = %d, name = %s, level = %d, req = %d"):format(q.q, quote(q.name or "?"), q.level, q.req) }
    if q.races then
      parts[#parts + 1] = ("races = %.0f"):format(q.races)
    end
    for _, k in ipairs({ "pre", "preAll", "excl" }) do
      if q[k] then
        parts[#parts + 1] = ("%s = %s"):format(k, list(q[k]))
      end
    end
    if type(q.crumb) == "number" and q.crumb > 0 then
      parts[#parts + 1] = ("crumb = %d"):format(q.crumb)
    end
    parts[#parts + 1] = ("m = %d, x = %s, y = %s"):format(q.m, q.x, q.y)
    if q.npc then
      parts[#parts + 1] = ("npc = %s"):format(quote(q.npc))
    end
    if q.tm then
      parts[#parts + 1] = ("tm = %d, tx = %s, ty = %s"):format(q.tm, q.tx, q.ty)
    end
    if q.tnpc then
      parts[#parts + 1] = ("tnpc = %s"):format(quote(q.tnpc))
    end
    out:write("    { " .. table.concat(parts, ", ") .. " },\n")
  end
  out:write("  },\n")
  total = total + #quests
  print(("%-8s %3d quests"):format(c[1], #quests))
end
out:write("}\n")
out:close()
print(("%d class quests; left out: %d above level %d, %d with no place to start, %d with a \"not done\" rule, "
  .. "%d not in Forever"):format(total, dropped.level, MAX_LEVEL, dropped.place, dropped.negative, dropped.absent))
