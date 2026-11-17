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
-- holds QuestieDB_Forever.toc, areaIdToUiMapId.lua and zones.lua.

package.path = "tools/?.lua;" .. package.path
local Q = require("questdb")

local tugs, qdbDir = arg[1], arg[2]
assert(tugs and qdbDir, "usage: lua tools/build_guides.lua <tugs folder> <questdb folder>")
local db = Q.open(qdbDir .. "/QuestieDB_Forever.toc", qdbDir .. "/areaIdToUiMapId.lua")

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
local function giverPlace(givers)
  givers = givers or {}
  local list = {}
  for _, npc in ipairs(givers[1] or {}) do
    npcPlaces(npc, list)
    if #list > 0 then
      return central(list), Q.field(db, "Npc", npc, Q.NPC.name)
    end
  end
  for _, obj in ipairs(givers[2] or {}) do
    objectPlaces(obj, list)
    if #list > 0 then
      return central(list), Q.field(db, "Object", obj, Q.OBJECT.name)
    end
  end
  return nil
end

-- Where a quest's objective n (or all) is done.
local function objectivePlace(questID, n)
  local obj = Q.field(db, "Quest", questID, Q.QUEST.objectives) or {}
  local flat = {}
  for _, c in ipairs(obj[1] or {}) do
    flat[#flat + 1] = function(out) return npcPlaces(c[1], out) end
  end
  for _, o in ipairs(obj[2] or {}) do
    flat[#flat + 1] = function(out) return objectPlaces(o[1], out) end
  end
  for _, i in ipairs(obj[3] or {}) do
    flat[#flat + 1] = function(out) return itemPlaces(i[1], out) end
  end
  for _, k in ipairs(obj[5] or {}) do -- kill credit: { { npcIds }, creditId, text }
    flat[#flat + 1] = function(out)
      for _, npc in ipairs(k[1] or {}) do
        npcPlaces(npc, out)
      end
      return out
    end
  end
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
  return central(list)
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
        place, s.npc = giverPlace(Q.field(db, "Quest", id, Q.QUEST.startedBy))
        guide.steps[#guide.steps + 1] = step("accept", s, place)
        added = true
      end
      for id, n in line:gmatch("%[QC(%d+),?(%d*)") do
        id = tonumber(id)
        local s = quest(id)
        s.n = tonumber(n)
        guide.steps[#guide.steps + 1] = step("complete", s, objectivePlace(id, s.n))
        added = true
      end
      for id in line:gmatch("%[QT(%d+)") do
        id = tonumber(id)
        local s = quest(id)
        local place
        place, s.npc = giverPlace(Q.field(db, "Quest", id, Q.QUEST.finishedBy))
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
-- only = classes or races it is for, text = what to do (goto, note, level).

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
