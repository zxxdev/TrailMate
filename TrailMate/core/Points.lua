-- Places and filters for data read from a quest database at runtime.
-- Pure Lua 5.1: the adapter passes plain tables, so all of it is tested.

local _, ns = ...

local Points = {}
ns.Points = Points

--- Converts spawns { [areaId] = { {x, y, phase?}, ... } } on a 0-100 scale
--- into points { mapID, x, y } on a 0-1 scale, using areaToMap[areaId] = uiMapID.
--- Zones the table does not know are left out. Appends to out if given.
function Points.fromSpawns(spawns, areaToMap, out)
  out = out or {}
  if type(spawns) ~= "table" or type(areaToMap) ~= "table" then
    return out
  end
  for areaId, list in pairs(spawns) do
    local mapID = areaToMap[areaId]
    if type(mapID) == "number" and mapID > 0 and type(list) == "table" then
      for _, p in ipairs(list) do
        local x, y = type(p) == "table" and p[1], type(p) == "table" and p[2]
        if type(x) == "number" and type(y) == "number" and x >= 0 and x <= 100 and y >= 0 and y <= 100 then
          out[#out + 1] = { mapID = mapID, x = x / 100, y = y / 100 }
        end
      end
    end
  end
  return out
end

--- The point nearest the player on the player's map; if none is on that map,
--- the first point with the lowest map id (stable, whatever the table order).
function Points.nearest(points, player)
  local best, bestD
  for _, p in ipairs(points or {}) do
    local d
    if player and p.mapID == player.mapID and type(player.x) == "number" and type(player.y) == "number" then
      local dx, dy = p.x - player.x, p.y - player.y
      d = dx * dx + dy * dy
    else
      d = 10 + p.mapID
    end
    if bestD == nil or d < bestD then
      best, bestD = p, d
    end
  end
  return best
end

--- True if bit (a power of two) is set in mask. A mask of 0 or nil means
--- "everyone", as the quest databases use it.
function Points.hasBit(mask, bit)
  if type(mask) ~= "number" or mask <= 0 or type(bit) ~= "number" then
    return true
  end
  return math.floor(mask / bit) % 2 == 1
end

local function anyDone(ids, isDone)
  for _, id in ipairs(ids) do
    if isDone(id) then
      return true
    end
  end
  return false
end

--- Whether a quest from the database is worth offering now.
--- q: { questID, requiredLevel, questLevel, requiredRaces, requiredClasses,
---      preQuestSingle, preQuestGroup, exclusiveTo }
--- ctx: { level, raceBit, classBit, isDone(id), inLog(id) }
function Points.eligible(q, ctx)
  if ctx.inLog(q.questID) or ctx.isDone(q.questID) then
    return false
  end
  if type(q.requiredLevel) == "number" and q.requiredLevel > ctx.level then
    return false
  end
  local ql = q.questLevel
  if type(ql) == "number" and ql > 0 then
    if ql - ctx.level >= ns.Builder.TOO_HARD_DIFF or ql <= ns.Builder.grayLevel(ctx.level) then
      return false
    end
  end
  if not (Points.hasBit(q.requiredRaces, ctx.raceBit) and Points.hasBit(q.requiredClasses, ctx.classBit)) then
    return false
  end
  for _, id in ipairs(q.preQuestGroup or {}) do
    if not ctx.isDone(id) then
      return false
    end
  end
  local single = q.preQuestSingle
  if type(single) == "table" and #single > 0 and not anyDone(single, ctx.isDone) then
    return false
  end
  for _, id in ipairs(q.exclusiveTo or {}) do
    if ctx.isDone(id) or ctx.inLog(id) then
      return false
    end
  end
  return true
end

--- True if an NPC trains the given class, judging by its trainer flag and its
--- title in the database ("Hunter Trainer"). className is the English name.
Points.TRAINER_FLAG = 16
function Points.isClassTrainer(npc, className)
  if type(npc.npcFlags) ~= "number" or not Points.hasBit(npc.npcFlags, Points.TRAINER_FLAG)
    or npc.npcFlags == 0 then
    return false
  end
  return type(npc.subName) == "string" and npc.subName:find("^" .. className .. " Trainer") ~= nil
end

--- True if an NPC is friendly to the player's faction ("Alliance"/"Horde").
--- friendly is "A", "H", "AH" or nil (unknown: allowed).
function Points.friendly(friendly, faction)
  if type(friendly) ~= "string" or friendly == "" then
    return true
  end
  local letter = faction == "Alliance" and "A" or faction == "Horde" and "H" or nil
  return letter == nil or friendly:find(letter, 1, true) ~= nil
end
