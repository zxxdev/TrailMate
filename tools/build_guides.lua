-- Builds TrailMate/data/Guides.lua: quest guides for WoW Forever with the
-- position of every step, so the arrow can point everywhere.
--
-- The order of the steps comes from the TUGs levelling guides for Forever
-- (Guidelime format). Who gives each quest, who takes it back, where they
-- stand and where the objectives are come from the Questie database for
-- Forever (read with tools/questdb.lua). Runs in the VM only:
--
--   lua tools/build_guides.lua <tugs folder> <questdb folder>
--
-- The tugs folder holds Horde/*.lua and Alliance/*.lua; the questdb folder
-- holds QuestieDB_Forever.toc, areaIdToUiMapId.lua and zones.lua, and
-- gameobject_template.sql and GameObjectDisplayInfo.csv for the models of
-- objects (see questdb.lua, loadModels).

package.path = "tools/?.lua;" .. package.path
local Q = require("questdb")

local tugs, qdbDir = arg[1], arg[2]
assert(tugs and qdbDir, "usage: lua tools/build_guides.lua <tugs folder> <questdb folder>")
local db = Q.open(qdbDir .. "/QuestieDB_Forever.toc", qdbDir .. "/areaIdToUiMapId.lua")
Q.loadModels(db, qdbDir) -- the 3D model of each object (see questdb.lua)

-- Zone names in the guides -> AreaTable ids -> map ids.
local zoneArea = {}
for line in io.lines(qdbDir .. "/zones.lua") do
  local name, id = line:match("^%s*([%u_%d]+)%s*=%s*(%d+)")
  if name then
    zoneArea[name] = zoneArea[name] or tonumber(id)
  end
end
local function zoneMap(name)
  local key = name:upper():gsub("'", ""):gsub("[^%u%d]+", "_"):gsub("^_+", ""):gsub("_+$", "")
  local area = zoneArea[key]
  return area and db:map(area) or nil
end

local function round(v)
  return math.floor(v * 1000 + 0.5) / 1000
end

-- Spawns { [area] = { { x, y }, ... } } -> list of { map, x, y } (0-1).
local function places(spawns, out)
  out = out or {}
  for area, list in pairs(spawns or {}) do
    local map = db:map(area)
    if map and map > 0 then
      for _, p in ipairs(list) do
        if type(p[1]) == "number" and p[1] >= 0 then
          out[#out + 1] = { map = map, x = p[1] / 100, y = p[2] / 100 }
        end
      end
    end
  end
  return out
end

-- The one place that stands for many: in the map with most of them, the
-- spot nearest to the middle of that map's spots (a real spawn, not empty
-- ground between two camps).
local function central(list)
  if #list == 0 then
    return nil
  end
  local count, best = {}, nil
  for _, p in ipairs(list) do
    count[p.map] = (count[p.map] or 0) + 1
    if not best or count[p.map] > count[best] then
      best = p.map
    end
  end
  local sx, sy, n = 0, 0, 0
  for _, p in ipairs(list) do
    if p.map == best then
      sx, sy, n = sx + p.x, sy + p.y, n + 1
    end
  end
  local cx, cy = sx / n, sy / n
  local pick, d
  for _, p in ipairs(list) do
    if p.map == best then
      local e = (p.x - cx) ^ 2 + (p.y - cy) ^ 2
      if not d or e < d then
        pick, d = p, e
      end
    end
  end
  return pick
end

local function npcPlaces(id, out)
  return places(Q.field(db, "Npc", id, Q.NPC.spawns), out)
end
local function objectPlaces(id, out)
  return places(Q.field(db, "Object", id, Q.OBJECT.spawns), out)
end
local function itemPlaces(id, out)
  out = out or {}
  for _, npc in ipairs(Q.field(db, "Item", id, Q.ITEM.npcDrops) or {}) do
    npcPlaces(npc, out)
  end
  for _, obj in ipairs(Q.field(db, "Item", id, Q.ITEM.objectDrops) or {}) do
    objectPlaces(obj, out)
  end
  return out
end

-- Where a quest is given or taken back: { npcIds, objectIds, itemIds }.
-- Returns the place, the giver's name, and its creature id when it is an NPC
-- (the game draws its model from that id).
local function giverPlace(givers)
  givers = givers or {}
  local list = {}
  for _, npc in ipairs(givers[1] or {}) do
    npcPlaces(npc, list)
    if #list > 0 then
      return central(list), Q.field(db, "Npc", npc, Q.NPC.name), npc
    end
  end
  for _, obj in ipairs(givers[2] or {}) do
    objectPlaces(obj, list)
    if #list > 0 then
      return central(list), Q.field(db, "Object", obj, Q.OBJECT.name), nil, Q.model(db, obj)
    end
  end
  return nil
end

-- What an objective is about, to show it: { creature = id, name } for an NPC
-- to kill or talk to, or for one that drops the item; { name } for an object.
local function npcTarget(id)
  local name = Q.field(db, "Npc", id, Q.NPC.name)
  return name and { creature = id, name = name } or nil
end
local function objectTarget(id)
  local name = Q.field(db, "Object", id, Q.OBJECT.name)
  return name and { name = name, model = Q.model(db, id) } or nil
end
local function itemTarget(id)
  for _, npc in ipairs(Q.field(db, "Item", id, Q.ITEM.npcDrops) or {}) do
    if #npcPlaces(npc) > 0 then
      local t = npcTarget(npc)
      if t then
        t.drop = true
      end
      return t
    end
  end
  for _, obj in ipairs(Q.field(db, "Item", id, Q.ITEM.objectDrops) or {}) do
    if #objectPlaces(obj) > 0 then
      local t = objectTarget(obj)
      if t then
        t.loot = id -- its icon: objects have no model here
      end
      return t
    end
  end
  return nil
end

-- Where a quest's objective n (or all) is done, and what it is about
-- (objective n, or the first one).
local function objectivePlace(questID, n)
  local obj = Q.field(db, "Quest", questID, Q.QUEST.objectives) or {}
  local flat, targets = {}, {}
  for _, c in ipairs(obj[1] or {}) do
    flat[#flat + 1] = function(out) return npcPlaces(c[1], out) end
    targets[#flat] = function() return npcTarget(c[1]) end
  end
  for _, o in ipairs(obj[2] or {}) do
    flat[#flat + 1] = function(out) return objectPlaces(o[1], out) end
    targets[#flat] = function() return objectTarget(o[1]) end
  end
  for _, i in ipairs(obj[3] or {}) do
    flat[#flat + 1] = function(out) return itemPlaces(i[1], out) end
    targets[#flat] = function() return itemTarget(i[1]) end
  end
  for _, k in ipairs(obj[5] or {}) do -- kill credit: { { npcIds }, creditId, text }
    flat[#flat + 1] = function(out)
      for _, npc in ipairs(k[1] or {}) do
        npcPlaces(npc, out)
      end
      return out
    end
    targets[#flat] = function() return k[1] and k[1][1] and npcTarget(k[1][1]) end
  end
  local which = targets[n or 1]
  local target = which and which() or nil
  local list = {}
  if n and flat[n] then
    flat[n](list)
  else
    for _, f in ipairs(flat) do
      f(list)
    end
  end
  if #list == 0 then
    local trigger = Q.field(db, "Quest", questID, Q.QUEST.triggerEnd)
    if trigger then
      places(trigger[2], list)
    end
  end
  return central(list), target
end

-- Guide text -> steps ---------------------------------------------------------

local function clean(text)
  text = text:gsub("%[[^%]]*%]", function(tag)
    local inner = tag:sub(2, -2)
    local kind, rest = inner:match("^(%u+)%s*(.*)$")
    if kind == "F" or kind == "TAR" then
      return rest
    elseif kind == "H" then
      return "Hearthstone"
    elseif kind == "P" then
      return ""
    elseif kind == "XP" then
      return "level " .. (rest:match("^(%d+)") or rest)
    elseif kind == "G" then
      return ""
    elseif kind == "CI" then
      return rest:match("^[%d,]+%s*(.*)$") or rest
    end
    return ""
  end)
  return (text:gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", ""):gsub(":%s*$", ""))
end

local function only(line)
  local list = line:match("%[A ([^%]]+)%]")
  if not list then
    return nil
  end
  local out = {}
  for word in list:gmatch("[^,%s]+") do
    out[#out + 1] = word:upper()
  end
  return out
end

local missing = { accept = 0, turnin = 0, complete = 0, ["goto"] = 0 }
local totals = { accept = 0, turnin = 0, complete = 0, ["goto"] = 0 }

local function step(kind, fields, place)
  totals[kind] = totals[kind] + 1
  if place then
    fields.m, fields.x, fields.y = place.map, round(place.x), round(place.y)
  else
    missing[kind] = missing[kind] + 1
  end
  fields.t = kind
  return fields
end

local function parseGuide(path, faction)
  local text = assert(io.open(path)):read("*a")
  local body = text:match("%[%[(.*)%]%]")
  local guide = { faction = faction, steps = {} }
  local started = false
  -- Header lines with nothing to keep: next guide, description, faction.
  local function header(line)
    return line:match("^%[NX") or line:match("^%[D ") or line:match("^%[GA ")
  end
  for line in body:gmatch("[^\r\n]+") do
    local name = not line:match("^%[NX") and line:match("^%[N([^%]]+)%]")
    if header(line) and not name then
      line = ""
    end
    if name then
      guide.name = guide.name or name
      local a, b = name:match("^(%d+)%-?(%d*)")
      guide.min, guide.max = tonumber(a), tonumber(b ~= "" and b or a)
    elseif line:match("^%s*%[A [^%]]+%]%s*$") and not started then
      guide.only = only(line)
    elseif line ~= "" then
      started = true
      local opt = line:find("[O]", 1, true) and true or nil
      local who = only(line)
      local added = false
      local function quest(id)
        return { q = id, name = Q.field(db, "Quest", id, Q.QUEST.name), opt = opt, only = who }
      end
      for id in line:gmatch("%[QA(%d+)") do
        id = tonumber(id)
        local s = quest(id)
        local place
        place, s.npc, s.cid, s.model = giverPlace(Q.field(db, "Quest", id, Q.QUEST.startedBy))
        guide.steps[#guide.steps + 1] = step("accept", s, place)
        added = true
      end
      for id, n in line:gmatch("%[QC(%d+),?(%d*)") do
        id = tonumber(id)
        local s = quest(id)
        s.n = tonumber(n)
        local place, target = objectivePlace(id, s.n)
        if target then
          s.tgt, s.cid, s.drop, s.loot, s.model = target.name, target.creature, target.drop, target.loot, target.model
        end
        guide.steps[#guide.steps + 1] = step("complete", s, place)
        added = true
      end
      for id in line:gmatch("%[QT(%d+)") do
        id = tonumber(id)
        local s = quest(id)
        local place
        place, s.npc, s.cid, s.model = giverPlace(Q.field(db, "Quest", id, Q.QUEST.finishedBy))
        guide.steps[#guide.steps + 1] = step("turnin", s, place)
        added = true
      end
      local level = line:match("%[XP(%d+)")
      if not added and level then
        guide.steps[#guide.steps + 1] = { t = "level", level = tonumber(level), text = clean(line) }
        added = true
      end
      if not added then
        local gx, gy, gzone = line:match("%[G%s*([%d%.]+)%s*,%s*([%d%.]+)%s*([^%]]*)%]")
        local note = clean(line)
        local map = gzone and gzone ~= "" and zoneMap(gzone) or nil
        if gx and map then
          guide.steps[#guide.steps + 1] = step("goto", { text = note ~= "" and note or ("Go to " .. gzone),
            only = who }, { map = map, x = tonumber(gx) / 100, y = tonumber(gy) / 100 })
        elseif note ~= "" then
          guide.steps[#guide.steps + 1] = { t = "note", text = note, only = who }
        end
      end
    end
  end
  return guide
end

-- Lua output -------------------------------------------------------------------

local function quote(s)
  return ("%q"):format(s):gsub("\\\n", "\\n")
end

local function serialize(t)
  local keys = {}
  for k in pairs(t) do
    keys[#keys + 1] = k
  end
  table.sort(keys)
  local parts = {}
  for _, k in ipairs(keys) do
    local v = t[k]
    local s
    if type(v) == "table" then
      local items = {}
      for _, x in ipairs(v) do
        items[#items + 1] = quote(x)
      end
      s = "{ " .. table.concat(items, ", ") .. " }"
    elseif type(v) == "string" then
      s = quote(v)
    else
      s = tostring(v)
    end
    parts[#parts + 1] = k .. " = " .. s
  end
  return "{ " .. table.concat(parts, ", ") .. " }"
end

local function listFiles(dir)
  local files = {}
  local p = io.popen(('ls "%s"'):format(dir))
  for name in p:lines() do
    if name:match("%.lua$") then
      files[#files + 1] = name
    end
  end
  p:close()
  table.sort(files, function(a, b)
    local na, nb = tonumber(a:match("^(%d+)")) or 0, tonumber(b:match("^(%d+)")) or 0
    if na ~= nb then
      return na < nb
    end
    return a < b
  end)
  return files
end

local guides = {}
for _, faction in ipairs({ "Horde", "Alliance" }) do
  for _, file in ipairs(listFiles(tugs .. "/" .. faction)) do
    guides[#guides + 1] = parseGuide(tugs .. "/" .. faction .. "/" .. file, faction)
  end
end

local out = assert(io.open("TrailMate/data/Guides.lua", "w"))
out:write([[
-- Quest guides for WoW Forever, generated by tools/build_guides.lua: do not
-- edit by hand. The order of the steps is the TUGs levelling guides' (free
-- guides for Forever, Guidelime format). Who gives and takes back each quest,
-- where they stand and where the objectives are come from the Questie
-- database for Forever. Positions are 0 to 1 on the step's map (m).
--
-- Step: t = accept | complete | turnin | goto | note | level, q = quest id,
-- n = objective, m/x/y = where, npc = who, opt = optional (elite or group),
-- only = classes or races it is for, text = what to do (goto, note, level),
-- cid = creature to show (the quest giver, or the one to kill or that drops
-- the item), tgt = what a "complete" step is about (an NPC or an object),
-- drop = true when tgt is not to kill but drops the item, loot = the item
-- looted from the object tgt (its icon), model = the 3D model file of an
-- object (tgt, or the one a quest starts or ends at).

local _, ns = ...

ns.GUIDES = {
]])
local steps = 0
for _, g in ipairs(guides) do
  out:write(("  {\n    name = %s, faction = %q, min = %d, max = %d,%s\n    steps = {\n"):format(quote(g.name or "?"),
    g.faction, g.min or 1, g.max or 60, g.only and (" only = " .. serialize({ x = g.only }):match("x = (.*) }")
    .. ",") or ""))
  for _, s in ipairs(g.steps) do
    out:write("      " .. serialize(s) .. ",\n")
    steps = steps + 1
  end
  out:write("    },\n  },\n")
end
out:write("}\n")
out:close()

print(("%d guides, %d steps"):format(#guides, steps))
for _, kind in ipairs({ "accept", "complete", "turnin", "goto" }) do
  print(("%-8s %5d, without a place %d"):format(kind, totals[kind], missing[kind]))
end

-- What each quest needs, for TrailMate/data/GuideQuests.lua ---------------------
--
-- The addon uses it when it builds a guide's plan, with what this character
-- has really done: a quest it can no longer pick up is left out.

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

-- Quests Wowhead's Forever database does not have (its tooltip service said
-- "not found" for these on 2026-11-18, of the 1777 the guides use).
local NOT_IN_FOREVER = { [4389] = true, [6221] = true, [281143] = true }

local needs, ordered = {}, {}
for _, g in ipairs(guides) do
  for _, s in ipairs(g.steps) do
    if s.q and not needs[s.q] then
      local e = {
        pre = ids(Q.field(db, "Quest", s.q, Q.QUEST.preQuestSingle)),
        preAll = ids(Q.field(db, "Quest", s.q, Q.QUEST.preQuestGroup)),
        excl = ids(Q.field(db, "Quest", s.q, Q.QUEST.exclusiveTo)),
        crumb = Q.field(db, "Quest", s.q, Q.QUEST.breadcrumbFor),
        known = Q.field(db, "Quest", s.q, Q.QUEST.name) ~= nil,
        absent = NOT_IN_FOREVER[s.q],
      }
      needs[s.q] = e
      ordered[#ordered + 1] = s.q
    end
  end
end
table.sort(ordered)

out = assert(io.open("TrailMate/data/GuideQuests.lua", "w"))
out:write([[
-- What the guides' quests need before the game offers them, from the Questie
-- database for Forever. Generated by tools/build_guides.lua: do not edit by
-- hand. pre: one of these handed in first; preAll: all of them; excl: taking
-- one of these closes this one; crumb: this quest only leads to that one,
-- and is gone once that one is taken.

local _, ns = ...

ns.GUIDE_QUESTS = {
]])
local written = 0
for _, q in ipairs(ordered) do
  local e = needs[q]
  local parts = {}
  for _, k in ipairs({ "pre", "preAll", "excl" }) do
    if e[k] then
      parts[#parts + 1] = ("%s = { %s }"):format(k, table.concat(e[k], ", "))
    end
  end
  if e.absent then
    parts[#parts + 1] = "absent = true"
  end
  if type(e.crumb) == "number" then
    parts[#parts + 1] = ("crumb = %d"):format(e.crumb)
  end
  if #parts > 0 then
    out:write(("  [%d] = { %s },\n"):format(q, table.concat(parts, ", ")))
    written = written + 1
  end
end
out:write("}\n")
out:close()
print(("%d quests with requirements written to TrailMate/data/GuideQuests.lua"):format(written))

-- The audit: each guide in order, as a player who follows the guides from
-- the start would meet them. Writes every risk to the file named by the
-- third argument (default /tmp/guide_audit.txt).
local report = {}
local counts = { unknown = 0, pre = 0, crumb = 0, excl = 0, faction = 0 }
local function flag(kind, g, q, text)
  counts[kind] = counts[kind] + 1
  report[#report + 1] = ("%-7s %-40s %6d %s: %s"):format(kind, g.name, q, tostring(Q.field(db, "Quest", q,
    Q.QUEST.name)), text)
end
for _, faction in ipairs({ "Horde", "Alliance" }) do
  local handedIn, taken = {}, {}
  for _, g in ipairs(guides) do
    if g.faction == faction then
      for _, s in ipairs(g.steps) do
        local e = s.q and needs[s.q]
        if s.t == "accept" and e then
          if not e.known then
            flag("unknown", g, s.q, "not in the Forever database")
          end
          local races = Q.field(db, "Quest", s.q, Q.QUEST.requiredRaces)
          if type(races) == "number" and races > 0 then
            local r = races % 2 ^ 32
            local horde = math.floor(r / 2) % 2 == 1 or math.floor(r / 16) % 2 == 1 or math.floor(r / 32) % 2 == 1
              or math.floor(r / 128) % 2 == 1
            local alliance = r % 2 == 1 or math.floor(r / 4) % 2 == 1 or math.floor(r / 8) % 2 == 1
              or math.floor(r / 64) % 2 == 1
            if (faction == "Horde" and not horde) or (faction == "Alliance" and not alliance) then
              flag("faction", g, s.q, "for the other faction")
            end
          end
          if e.pre then
            local ok = false
            for _, p in ipairs(e.pre) do
              ok = ok or handedIn[p]
            end
            if not ok then
              flag("pre", g, s.q, "needs one of " .. table.concat(e.pre, ", ") .. " handed in before")
            end
          end
          for _, p in ipairs(e.preAll or {}) do
            if not handedIn[p] then
              flag("pre", g, s.q, "needs " .. p .. " handed in before")
            end
          end
          if type(e.crumb) == "number" and taken[e.crumb] then
            flag("crumb", g, s.q, ("leads to %d, taken earlier: it will not be offered"):format(e.crumb))
          end
          for _, x in ipairs(e.excl or {}) do
            if taken[x] then
              flag("excl", g, s.q, ("closed by %d, taken earlier"):format(x))
            end
          end
          taken[s.q] = true
        elseif s.t == "turnin" and s.q then
          handedIn[s.q] = true
        end
      end
    end
  end
end
local path = arg[3] or "/tmp/guide_audit.txt"
local file = assert(io.open(path, "w"))
file:write(table.concat(report, "\n") .. "\n")
file:close()
print(("audit: %d unknown, %d for the other faction, %d need a quest not handed in before, %d breadcrumbs after "
  .. "their quest, %d closed by an exclusive one (details in %s)"):format(counts.unknown, counts.faction, counts.pre,
  counts.crumb, counts.excl, path))
