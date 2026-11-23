-- Reads the Questie database for WoW Forever (QuestieDB_Forever.toc) outside
-- the game, to build TrailMate's quest guides: who gives each quest, who
-- takes it back, where they stand, where its objectives are. Pure Lua 5.1;
-- runs in the VM only (never in the addon).
--
-- The database keeps every entity in the toc's metadata lines:
--   ## X-Quest-<id>-S: <base64 CBOR map of the plain fields>
--   ## X-Quest-<id>-<field>: <base64 CBOR of one table field>
-- Field numbers are QuestieDB's (src/meta/questMeta.lua, npcMeta.lua...).
-- Positions are in percent (0-100) of a zone given by its AreaTable id;
-- areaIdToUiMapId.lua turns that into the map ids the game uses.

local M = {}

-- Base64 -----------------------------------------------------------------------

local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local B64V = {}
for i = 1, #B64 do
  B64V[B64:byte(i)] = i - 1
end

function M.base64(s)
  local out, bits, n = {}, 0, 0
  for i = 1, #s do
    local v = B64V[s:byte(i)]
    if v then
      bits, n = bits * 64 + v, n + 6
      if n >= 8 then
        n = n - 8
        local byte = math.floor(bits / 2 ^ n)
        out[#out + 1] = string.char(byte)
        bits = bits - byte * 2 ^ n
      end
    end
  end
  return table.concat(out)
end

-- CBOR (RFC 8949): the types QuestieDB writes ----------------------------------

local function half(h)
  local sign = h >= 0x8000 and -1 or 1
  local e = math.floor(h / 1024) % 32
  local f = h % 1024
  if e == 0 then
    return sign * f * 2 ^ -24
  elseif e == 31 then
    return f == 0 and sign * math.huge or 0 / 0
  end
  return sign * (1 + f / 1024) * 2 ^ (e - 15)
end

local function single(b)
  local sign = b[1] >= 128 and -1 or 1
  local e = (b[1] % 128) * 2 + math.floor(b[2] / 128)
  local f = ((b[2] % 128) * 256 + b[3]) * 256 + b[4]
  if e == 0 then
    return sign * f * 2 ^ -149
  elseif e == 255 then
    return f == 0 and sign * math.huge or 0 / 0
  end
  return sign * (1 + f / 2 ^ 23) * 2 ^ (e - 127)
end

local function double(b)
  local sign = b[1] >= 128 and -1 or 1
  local e = (b[1] % 128) * 16 + math.floor(b[2] / 16)
  local f = b[2] % 16
  for i = 3, 8 do
    f = f * 256 + b[i]
  end
  if e == 0 then
    return sign * f * 2 ^ -1074
  elseif e == 2047 then
    return f == 0 and sign * math.huge or 0 / 0
  end
  return sign * (1 + f / 2 ^ 52) * 2 ^ (e - 1023)
end

function M.cbor(s)
  local pos = 1
  local function byte()
    local b = s:byte(pos)
    pos = pos + 1
    return b
  end
  local function bytes(n)
    local t = {}
    for i = 1, n do
      t[i] = byte()
    end
    return t
  end
  local function uint(info)
    if info < 24 then
      return info
    end
    local n = ({ [24] = 1, [25] = 2, [26] = 4, [27] = 8 })[info]
    local v = 0
    for _ = 1, n do
      v = v * 256 + byte()
    end
    return v
  end
  local item
  function item()
    local b = byte()
    local major, info = math.floor(b / 32), b % 32
    if major == 0 then
      return uint(info)
    elseif major == 1 then
      return -1 - uint(info)
    elseif major == 2 or major == 3 then
      local n = uint(info)
      local str = s:sub(pos, pos + n - 1)
      pos = pos + n
      return str
    elseif major == 4 then
      local t = {}
      for i = 1, uint(info) do
        t[i] = item()
      end
      return t
    elseif major == 5 then
      local t = {}
      for _ = 1, uint(info) do
        local k = item()
        t[k] = item()
      end
      return t
    elseif major == 6 then
      uint(info) -- a tag: the value follows
      return item()
    end
    if info == 20 then
      return false
    elseif info == 21 then
      return true
    elseif info == 22 or info == 23 then
      return nil
    elseif info == 25 then
      local b1, b2 = byte(), byte()
      return half(b1 * 256 + b2)
    elseif info == 26 then
      return single(bytes(4))
    elseif info == 27 then
      return double(bytes(8))
    end
    error(("cbor: unsupported byte %d at %d"):format(b, pos - 1))
  end
  return item()
end

-- The database -------------------------------------------------------------------

-- Quest fields. 12: all of these quests first; 13: one of them first; 16:
-- taking one of these closes this one; 27: this quest only leads to that
-- one (a breadcrumb, gone once that one is taken); 28: the breadcrumbs that
-- lead here. Checked on known cases (638 -> 639, 1362 -> 1365) on 2026-11-18.
M.QUEST = { name = 1, startedBy = 2, finishedBy = 3, requiredLevel = 4, questLevel = 5, requiredRaces = 6,
  requiredClasses = 7, objectivesText = 8, triggerEnd = 9, objectives = 10, preQuestGroup = 12, preQuestSingle = 13,
  exclusiveTo = 16, zoneOrSort = 17, requiredMinRep = 19, breadcrumbFor = 27, breadcrumbs = 28 }
M.NPC = { name = 1, minLevel = 4, maxLevel = 5, spawns = 7, zoneID = 9, friendlyToFaction = 13, subName = 14,
  npcFlags = 15 }
M.OBJECT = { name = 1, spawns = 4 }
M.ITEM = { name = 1, npcDrops = 2, objectDrops = 3 }

--- Opens the database: reads every metadata line into memory.
function M.open(tocPath, areaPath)
  local db = { lines = {}, areas = {} }
  for line in io.lines(tocPath) do
    local key, value = line:match("^## X%-(%S+): (.*)$")
    if key then
      db.lines[key] = value
    end
  end
  -- AreaTable id -> map id: every "[area] = map," pair (the file's base
  -- table first, its overrides after, so overrides win).
  for line in io.lines(areaPath) do
    local area, map = line:match("^%s*%[(%d+)%]%s*=%s*(%d+)")
    if area then
      db.areas[tonumber(area)] = tonumber(map)
    end
  end
  return setmetatable(db, { __index = M })
end

local function stored(db, key)
  local v = db.lines[key]
  if not v then
    return nil
  end
  local parts = v:match("^~(%d+)~$")
  if parts then
    local buf = {}
    for i = 1, tonumber(parts) do
      buf[i] = assert(db.lines[key .. "-" .. i], key .. ": chunk missing")
    end
    v = table.concat(buf)
  end
  return v
end

--- One field of an entity ("Quest", "Npc", "Object", "Item"), decoded.
function M.field(db, kind, id, index)
  local row = db:row(kind, id)
  if row and row[index] ~= nil then
    return row[index]
  end
  local v = stored(db, ("%s-%d-%d"):format(kind, id, index))
  return v and M.cbor(M.base64(v)) or nil
end

--- The plain fields of an entity (a map field number -> value), or nil.
function M.row(db, kind, id)
  db.rows = db.rows or {}
  local key = kind .. id
  if db.rows[key] == nil then
    local v = stored(db, ("%s-%d-S"):format(kind, id))
    db.rows[key] = v and M.cbor(M.base64(v)) or false
  end
  return db.rows[key] or nil
end

--- A zone (AreaTable id) as a map id, or nil.
function M.map(db, area)
  return db.areas[area]
end

-- Places -----------------------------------------------------------------------

--- A position rounded to a thousandth of the map.
function M.round(v)
  return math.floor(v * 1000 + 0.5) / 1000
end

--- The most central spawn of an NPC or object ({ [area] = { {x, y}, ... } },
--- in percent): { m, x, y } on the map where it has the most spawns, or nil.
function M.central(db, spawns)
  local list = {}
  for area, points in pairs(spawns or {}) do
    local map = db:map(area)
    for _, p in ipairs(map and points or {}) do
      if type(p[1]) == "number" and p[1] >= 0 then
        list[#list + 1] = { m = map, x = p[1] / 100, y = p[2] / 100 }
      end
    end
  end
  if #list == 0 then
    return nil
  end
  local count, best = {}, nil
  for _, p in ipairs(list) do
    count[p.m] = (count[p.m] or 0) + 1
    if not best or count[p.m] > count[best] then
      best = p.m
    end
  end
  local sx, sy, n = 0, 0, 0
  for _, p in ipairs(list) do
    if p.m == best then
      sx, sy, n = sx + p.x, sy + p.y, n + 1
    end
  end
  local pick, dist
  for _, p in ipairs(list) do
    if p.m == best then
      local e = (p.x - sx / n) ^ 2 + (p.y - sy / n) ^ 2
      if not dist or e < dist then
        pick, dist = p, e
      end
    end
  end
  return { m = pick.m, x = M.round(pick.x), y = M.round(pick.y) }
end

--- Who starts or ends a quest (its startedBy or finishedBy field: { npcs,
--- objects, items }): their place ({ m, x, y } or nil), their name, and the
--- creature id when it is an NPC (the game draws its model from it). An item
--- has a name but no place.
function M.giver(db, by)
  by = by or {}
  for _, npc in ipairs(by[1] or {}) do
    local place = M.central(db, M.field(db, "Npc", npc, M.NPC.spawns))
    if place then
      return place, M.field(db, "Npc", npc, M.NPC.name), npc
    end
  end
  for _, obj in ipairs(by[2] or {}) do
    local place = M.central(db, M.field(db, "Object", obj, M.OBJECT.spawns))
    if place then
      return place, M.field(db, "Object", obj, M.OBJECT.name)
    end
  end
  if by[3] and by[3][1] then
    return nil, M.field(db, "Item", by[3][1], M.ITEM.name)
  end
  return nil
end

local function hasSpawns(db, kind, id, field)
  local spawns = M.field(db, kind, id, field)
  return type(spawns) == "table" and next(spawns) ~= nil
end

--- Who or what each objective of a quest is about, to show it, in the
--- database's order and once per name: { c = creature id, n = name } for a
--- creature to kill (or to talk to, for a kill credit), with d = true when
--- it is not to kill but drops the item; { n = name } for an object, with
--- l = the item looted from it (its icon is shown, objects have no model
--- here). Spawns
--- are not needed to be placed on a map: inside a dungeon they often are not.
function M.targets(db, questID)
  local obj = M.field(db, "Quest", questID, M.QUEST.objectives) or {}
  local out, seen = {}, {}
  local function add(t)
    if t and t.n and not seen[t.n] then
      seen[t.n] = true
      out[#out + 1] = t
    end
  end
  local function npc(id, drop)
    local name = M.field(db, "Npc", id, M.NPC.name)
    return name and { c = id, n = name, d = drop or nil } or nil
  end
  local function object(id, loot)
    local name = M.field(db, "Object", id, M.OBJECT.name)
    return name and { n = name, l = loot } or nil
  end
  for _, c in ipairs(obj[1] or {}) do
    add(npc(c[1]))
  end
  for _, o in ipairs(obj[2] or {}) do
    add(object(o[1]))
  end
  for _, i in ipairs(obj[3] or {}) do
    local found
    for _, id in ipairs(M.field(db, "Item", i[1], M.ITEM.npcDrops) or {}) do
      if hasSpawns(db, "Npc", id, M.NPC.spawns) then
        found = npc(id, true)
        break
      end
    end
    if not found then
      for _, id in ipairs(M.field(db, "Item", i[1], M.ITEM.objectDrops) or {}) do
        if hasSpawns(db, "Object", id, M.OBJECT.spawns) then
          found = object(id, i[1])
          break
        end
      end
    end
    add(found)
  end
  for _, k in ipairs(obj[5] or {}) do -- kill credit: { { npcIds }, creditId, text }
    if k[1] and k[1][1] then
      add(npc(k[1][1]))
    end
  end
  return out
end

return M
