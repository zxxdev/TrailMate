-- Builds TrailMate/data/Dungeons.lua: the dungeons of WoW Forever with the
-- level of their enemies, where their entrance is and the quests to take
-- with you (who gives them, where, and who takes them back).
--
-- Everything comes from the Questie database for Forever (read with
-- tools/questdb.lua): the entrances from its dungeons.lua (stored in
-- Forever's own coordinates), the enemies' levels from the NPCs that live
-- in each dungeon, and the quests from the ones whose zone is the dungeon.
-- Runs in the VM only:
--
--   lua tools/build_dungeons.lua <questdb folder>
--
-- The folder holds QuestieDB_Forever.toc, areaIdToUiMapId.lua and
-- dungeons.lua (support/Forever/Zones/dungeons.lua of QuestieDB).

package.path = "tools/?.lua;" .. package.path
local Q = require("questdb")

local qdbDir = arg[1]
assert(qdbDir, "usage: lua tools/build_dungeons.lua <questdb folder>")
local db = Q.open(qdbDir .. "/QuestieDB_Forever.toc", qdbDir .. "/areaIdToUiMapId.lua")

-- The 5-player dungeons of levels 1-60, in the order players meet them.
-- Raids, battlegrounds and later expansions are left out. side: the only
-- faction that can reach the entrance without crossing an enemy city.
local DUNGEONS = {
  { id = 2437, side = "H" }, -- Ragefire Chasm, in Orgrimmar
  { id = 1581 }, -- The Deadmines
  { id = 718 }, -- Wailing Caverns
  { id = 209 }, -- Shadowfang Keep
  { id = 719 }, -- Blackfathom Deeps
  { id = 717, side = "A" }, -- The Stockade, in Stormwind
  { id = 721 }, -- Gnomeregan
  { id = 491 }, -- Razorfen Kraul
  { id = 796 }, -- Scarlet Monastery
  { id = 722 }, -- Razorfen Downs
  { id = 1337 }, -- Uldaman
  { id = 1176 }, -- Zul'Farrak
  { id = 2100 }, -- Maraudon
  { id = 1477 }, -- The Temple of Atal'Hakkar
  { id = 1584 }, -- Blackrock Depths
  { id = 1583 }, -- Blackrock Spire
  { id = 2557 }, -- Dire Maul
  { id = 2057 }, -- Scholomance
  { id = 2017 }, -- Stratholme
}

local CLASSES = 7 -- the quest field with the class mask
local SEASON_IDS = 200000

-- Race bits of the database: the Alliance races and the Horde races.
local ALLIANCE = { 1, 4, 8, 64 } -- Human, Dwarf, Night Elf, Gnome
local HORDE = { 2, 16, 32, 128 } -- Orc, Undead, Tauren, Troll

local function hasBit(mask, bit)
  return math.floor(mask / bit) % 2 == 1
end

local function anyBit(mask, bits)
  for _, b in ipairs(bits) do
    if hasBit(mask, b) then
      return true
    end
  end
  return false
end

-- "A", "H" or nil (both) from a race mask (higher flags ignored).
local function sideOf(mask)
  if type(mask) ~= "number" or mask <= 0 then
    return nil
  end
  mask = mask % 2 ^ 32
  local a, h = anyBit(mask, ALLIANCE), anyBit(mask, HORDE)
  if a and not h then
    return "A"
  elseif h and not a then
    return "H"
  end
  return nil
end

local round = Q.round

-- dungeons.lua: [area] = {"Name", {alternative areas} or nil, parent, {{area, x, y}, ...}}
local entries = {}
for line in io.lines(qdbDir .. "/dungeons.lua") do
  local id, name, rest = line:match('^%s*%[(%d+)%]%s*=%s*{"([^"]+)",%s*(.*)$')
  local alts, locations
  if rest then
    alts, rest = rest:match("^{([%d,%s]*)},%s*(.*)$")
    if not alts then
      alts, rest = "", line:match('^%s*%[%d+%]%s*=%s*{"[^"]+",%s*nil,%s*(.*)$')
    end
    locations = rest and rest:match("^%d+,%s*{(.*)}}")
  end
  if id and locations then
    local e = { name = name, areas = { [tonumber(id)] = true }, entrances = {} }
    for a in (alts or ""):gmatch("%d+") do
      e.areas[tonumber(a)] = true
    end
    for area, x, y in locations:gmatch("{(%d+),%s*([%d.]+),%s*([%d.]+)}") do
      local map = db:map(tonumber(area))
      if map then
        e.entrances[#e.entrances + 1] = { m = map, x = round(tonumber(x) / 100), y = round(tonumber(y) / 100) }
      end
    end
    entries[tonumber(id)] = e
  end
end

-- Which dungeon an area belongs to.
local dungeonOf = {}
for _, d in ipairs(DUNGEONS) do
  local e = assert(entries[d.id], "dungeon " .. d.id .. " missing from dungeons.lua")
  for area in pairs(e.areas) do
    dungeonOf[area] = d.id
  end
end

local function ids(kind)
  local list = {}
  for key in pairs(db.lines) do
    local id = key:match("^" .. kind .. "%-(%d+)%-S$")
    if id then
      list[#list + 1] = tonumber(id)
    end
  end
  table.sort(list)
  return list
end

-- The enemies' levels in each dungeon (hostile NPCs only).
local levels = {}
for _, id in ipairs(ids("Npc")) do
  local r = Q.row(db, "Npc", id)
  local d = r and dungeonOf[r[Q.NPC.zoneID]]
  local lo, hi = r and r[Q.NPC.minLevel], r and r[Q.NPC.maxLevel]
  -- Ids from 200000 are the Season of Discovery's raid versions (level 40
  -- Gnomeregan and the like), not the dungeon.
  if d and id < SEASON_IDS and r[Q.NPC.friendlyToFaction] == nil and type(lo) == "number"
    and type(hi) == "number" and lo > 1 and hi <= 63 then
    levels[d] = levels[d] or { lows = {}, top = 0 }
    table.insert(levels[d].lows, lo)
    levels[d].top = math.max(levels[d].top, hi)
  end
end

-- Where a quest starts or ends (the most central spawn) and who it is.
local function giver(by)
  return Q.giver(db, by)
end

local quests = {}
for _, id in ipairs(ids("Quest")) do
  local r = Q.row(db, "Quest", id)
  local d = r and dungeonOf[r[Q.QUEST.zoneOrSort]]
  local level = r and r[Q.QUEST.questLevel]
  if d and type(level) == "number" and level > 0 then
    local q = { q = id, name = r[Q.QUEST.name], level = level, req = r[Q.QUEST.requiredLevel],
      side = sideOf(Q.field(db, "Quest", id, Q.QUEST.requiredRaces)) }
    -- Lists are stored apart from the row: read them by field.
    local classes = Q.field(db, "Quest", id, CLASSES)
    if type(classes) == "number" and classes > 0 then
      q.classes = classes
    end
    local pre = Q.field(db, "Quest", id, Q.QUEST.preQuestSingle)
    if type(pre) == "table" and #pre > 0 then
      q.pre = pre
    end
    local start, startName = giver(Q.field(db, "Quest", id, Q.QUEST.startedBy))
    if start then
      q.m, q.x, q.y = start.m, start.x, start.y
    end
    q.npc = startName
    local finish, finishName = giver(Q.field(db, "Quest", id, Q.QUEST.finishedBy))
    if finish then
      q.tm, q.tx, q.ty = finish.m, finish.x, finish.y
    end
    q.tnpc = finishName
    q.targets = Q.targets(db, id)
    quests[d] = quests[d] or {}
    table.insert(quests[d], q)
  end
end

-- Output ------------------------------------------------------------------------

local function quote(s)
  return ("%q"):format(s):gsub("\\\n", "\\n")
end

local out = assert(io.open("TrailMate/data/Dungeons.lua", "w"))
out:write([[
-- The dungeons of WoW Forever for levels 1-60: the level of their enemies
-- (lowest common level to the strongest boss), where the entrance is, and
-- the quests to take with you. Generated by tools/build_dungeons.lua from
-- the Questie database for Forever: do not edit by hand.
--
-- Quest fields: q id, level, req (level to pick it up), side ("A", "H" or
-- both), classes (bit mask, or all), pre (needs one of these quests first),
-- m/x/y and npc where it starts, tm/tx/ty and tnpc where it is handed in.
-- targets: who or what its objectives are about, to show them: c = creature
-- id (its 3D model), n = name, d = true when it drops the item (not to kill),
-- l = the item looted from an object (its icon: objects have no model here).

local _, ns = ...

ns.DUNGEONS = {
]])
local total = 0
for _, d in ipairs(DUNGEONS) do
  local e, lv = entries[d.id], levels[d.id]
  table.sort(lv.lows)
  -- The lowest level most enemies have: the tenth percentile, so a lone
  -- low critter or pet does not pull the range down.
  local low = lv.lows[math.max(1, math.floor(#lv.lows * 0.1 + 0.5))]
  -- inside: the dungeon's own map, to tell quests that start inside it.
  local inside = db:map(d.id)
  out:write(("  {\n    id = %d, name = %s, min = %d, max = %d,%s%s\n    entrances = {"):format(d.id, quote(e.name),
    low, lv.top, inside and (" inside = %d,"):format(inside) or "", d.side and (" side = %q,"):format(d.side) or ""))
  for _, p in ipairs(e.entrances) do
    out:write((" { m = %d, x = %s, y = %s },"):format(p.m, p.x, p.y))
  end
  out:write(" },\n    quests = {\n")
  -- A quest far above the dungeon's enemies belongs to another version of
  -- it (the Season of Discovery's level 40 Gnomeregan, for example).
  local list = {}
  for _, q in ipairs(quests[d.id] or {}) do
    if q.level <= lv.top + 5 then
      list[#list + 1] = q
    end
  end
  table.sort(list, function(a, b)
    if a.level ~= b.level then
      return a.level < b.level
    end
    return a.q < b.q
  end)
  for _, q in ipairs(list) do
    local parts = { ("q = %d, name = %s, level = %d"):format(q.q, quote(q.name or "?"), q.level) }
    if type(q.req) == "number" and q.req > 0 then
      parts[#parts + 1] = ("req = %d"):format(q.req)
    end
    if q.side then
      parts[#parts + 1] = ("side = %q"):format(q.side)
    end
    if q.classes then
      parts[#parts + 1] = ("classes = %d"):format(q.classes)
    end
    if q.pre then
      parts[#parts + 1] = ("pre = { %s }"):format(table.concat(q.pre, ", "))
    end
    if q.m then
      parts[#parts + 1] = ("m = %d, x = %s, y = %s"):format(q.m, q.x, q.y)
    end
    if q.npc then
      parts[#parts + 1] = ("npc = %s"):format(quote(q.npc))
    end
    if q.tm then
      parts[#parts + 1] = ("tm = %d, tx = %s, ty = %s"):format(q.tm, q.tx, q.ty)
    end
    if q.tnpc then
      parts[#parts + 1] = ("tnpc = %s"):format(quote(q.tnpc))
    end
    if q.targets and #q.targets > 0 then
      local shown = {}
      for _, t in ipairs(q.targets) do
        shown[#shown + 1] = "{ " .. (t.c and ("c = %d, "):format(t.c) or "") .. ("n = %s"):format(quote(t.n))
          .. (t.d and ", d = true" or "") .. (t.l and (", l = %d"):format(t.l) or "") .. " }"
      end
      parts[#parts + 1] = "targets = { " .. table.concat(shown, ", ") .. " }"
    end
    out:write("      { " .. table.concat(parts, ", ") .. " },\n")
    total = total + 1
  end
  out:write("    },\n  },\n")
  print(("%-28s %2d-%2d  %d quests, %d entrances"):format(e.name, low, lv.top, #list, #e.entrances))
end
out:write("}\n")
out:close()
print(("%d dungeons, %d quests"):format(#DUNGEONS, total))
