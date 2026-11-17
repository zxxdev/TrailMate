-- Optional data source: the public runtime API of the QuestieDB addon
-- (global LibQuestieDB, documented in QuestieDB's docs/api.md for other
-- addons). TrailMate never copies that data; it only reads it while the game
-- runs, and only when the player has QuestieDB installed. Without it,
-- everything here returns nothing and the addon works with the game alone.

local _, ns = ...

local Data = {}
ns.Data = Data

local CONTRACT = 4
local CLASS_NAMES = {
  WARRIOR = "Warrior", PALADIN = "Paladin", HUNTER = "Hunter", ROGUE = "Rogue", PRIEST = "Priest",
  SHAMAN = "Shaman", MAGE = "Mage", WARLOCK = "Warlock", DRUID = "Druid",
}

local lib, areaToMap
local state -- nil: not tried yet; true/false afterwards

local function get(entity, id, key)
  local ok, v = pcall(entity.Get, id, key)
  if ok then
    return v
  end
  return nil
end

--- True when QuestieDB is installed, speaks the contract TrailMate was written
--- for, and its zone table could be loaded.
function Data.ready()
  if state ~= nil then
    return state
  end
  state = false
  lib = rawget(_G, "LibQuestieDB")
  if type(lib) ~= "table" or type(lib.RequireContract) ~= "function" then
    return false
  end
  local ok, accepted = pcall(lib.RequireContract, CONTRACT)
  if not (ok and accepted) then
    return false
  end
  -- QuestieDB ships its areaId -> uiMapID table as Lua source and documents
  -- loading it with loadstring.
  local okMap, map = pcall(function()
    local src = lib.Support.Get("ZoneDB").private.areaIdToUiMapId
    if type(src) == "table" then
      return src
    end
    return assert(loadstring(src))()
  end)
  if not okMap or type(map) ~= "table" then
    return false
  end
  areaToMap = map
  state = true
  return true
end

local function npcPoints(ids, out)
  for _, id in ipairs(type(ids) == "table" and ids or {}) do
    ns.Points.fromSpawns(get(lib.Npc, id, "spawns"), areaToMap, out)
  end
  return out
end

local function objectPoints(ids, out)
  for _, id in ipairs(type(ids) == "table" and ids or {}) do
    ns.Points.fromSpawns(get(lib.Object, id, "spawns"), areaToMap, out)
  end
  return out
end

-- Questgivers: [1] NPC ids, [2] object ids (each group may be missing).
local function giverPoints(givers)
  local out = {}
  if type(givers) == "table" then
    npcPoints(givers[1], out)
    objectPoints(givers[2], out)
  end
  return out
end

--- Where to go for a quest in the log, from the database: the turn-in when it
--- is complete, the creatures to kill otherwise. { mapID, x, y } or nil.
function Data.questTarget(questID, complete, player)
  if not Data.ready() then
    return nil
  end
  local points
  if complete then
    points = giverPoints(get(lib.Quest, questID, "finishedBy"))
  else
    points = {}
    local objectives = get(lib.Quest, questID, "objectives")
    local creatures = type(objectives) == "table" and objectives[1]
    for _, entry in ipairs(type(creatures) == "table" and creatures or {}) do
      local id = type(entry) == "table" and entry[1] or entry
      if type(id) == "number" then
        npcPoints({ id }, points)
      end
    end
    if #points == 0 then
      -- No creature to kill: at least head to whoever takes it back.
      points = giverPoints(get(lib.Quest, questID, "finishedBy"))
    end
  end
  return ns.Points.nearest(points, player)
end

--- Quests the player can pick up on the current map: { questID, title,
--- level, target }. ctx = { level, raceBit, classBit, faction, isDone, inLog }.
function Data.offers(ctx, player)
  local out = {}
  if not Data.ready() or not (player and player.mapID) then
    return out
  end
  local ok, ids = pcall(lib.Quest.GetAllIds)
  if not ok or type(ids) ~= "table" then
    return out
  end
  for _, questID in ipairs(ids) do
    local q = {
      questID = questID,
      requiredLevel = get(lib.Quest, questID, "requiredLevel"),
      questLevel = get(lib.Quest, questID, "questLevel"),
      requiredRaces = get(lib.Quest, questID, "requiredRaces"),
      requiredClasses = get(lib.Quest, questID, "requiredClasses"),
      preQuestSingle = get(lib.Quest, questID, "preQuestSingle"),
      preQuestGroup = get(lib.Quest, questID, "preQuestGroup"),
      exclusiveTo = get(lib.Quest, questID, "exclusiveTo"),
    }
    if ns.Points.eligible(q, ctx) then
      local starters = get(lib.Quest, questID, "startedBy")
      local here = {}
      for _, npc in ipairs(type(starters) == "table" and type(starters[1]) == "table" and starters[1] or {}) do
        if ns.Points.friendly(get(lib.Npc, npc, "friendlyToFaction"), ctx.faction) then
          for _, p in ipairs(npcPoints({ npc }, {})) do
            if p.mapID == player.mapID then
              here[#here + 1] = p
            end
          end
        end
      end
      local target = ns.Points.nearest(here, player)
      if target then
        out[#out + 1] = {
          questID = questID, title = get(lib.Quest, questID, "name"), level = q.questLevel, target = target,
        }
      end
    end
  end
  return out
end

--- Nearest trainer of the player's class: point, name; or nil.
function Data.findTrainer(class, faction, player)
  local className = CLASS_NAMES[class or ""]
  if not Data.ready() or not className then
    return nil
  end
  local ok, ids = pcall(lib.Npc.GetAllIds)
  if not ok or type(ids) ~= "table" then
    return nil
  end
  local best, bestName, bestD
  for _, npc in ipairs(ids) do
    local info = { npcFlags = get(lib.Npc, npc, "npcFlags"), subName = get(lib.Npc, npc, "subName") }
    if ns.Points.isClassTrainer(info, className)
      and ns.Points.friendly(get(lib.Npc, npc, "friendlyToFaction"), faction) then
      local p = ns.Points.nearest(npcPoints({ npc }, {}), player)
      if p then
        local d = (player and p.mapID == player.mapID and player.x)
          and ((p.x - player.x) ^ 2 + (p.y - player.y) ^ 2) or (10 + p.mapID)
        if bestD == nil or d < bestD then
          best, bestName, bestD = p, get(lib.Npc, npc, "name"), d
        end
      end
    end
  end
  return best, bestName
end
