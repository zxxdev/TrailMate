-- Thin wrappers over the game API. This client is new: every function is
-- feature-detected and called through pcall, and /tm diag reports what the
-- client really exposes. When a modern (C_*) and a legacy function both
-- exist, the modern one is tried first.

local _, ns = ...

local Api = {}
ns.Api = Api

local function try(fn, ...)
  if type(fn) ~= "function" then
    return false
  end
  return pcall(fn, ...)
end

local function pack(...)
  return { n = select("#", ...), ... }
end

-- Calls fn and returns its results, or nil if it is missing or fails.
local function safe(fn, ...)
  local r = pack(try(fn, ...))
  if not r[1] then
    return nil
  end
  return unpack(r, 2, r.n)
end

local function isSecret(v)
  return issecretvalue ~= nil and safe(issecretvalue, v) == true
end

-- Resolves "C_Map.SetUserWaypoint" style names against _G.
local function resolve(path)
  local node = _G
  for part in path:gmatch("[^%.]+") do
    if type(node) ~= "table" then
      return nil
    end
    node = node[part]
  end
  return node
end

function Api.class()
  local _, class = safe(UnitClass, "player")
  return class
end

function Api.level()
  return safe(UnitLevel, "player")
end

function Api.money()
  return safe(GetMoney)
end

function Api.xp()
  return safe(UnitXP, "player"), safe(UnitXPMax, "player")
end

function Api.faction()
  return (safe(UnitFactionGroup, "player"))
end

--- The creature you are talking to (quest giver, trainer, vendor):
--- { id, name }, or nil. The id is the 6th field of its GUID
--- ("Creature-0-server-instance-zone-ID-spawn").
function Api.npc()
  local guid = safe(UnitGUID, "npc")
  if type(guid) ~= "string" or isSecret(guid) then
    return nil
  end
  local tail = "%-%d+%-%d+%-%d+%-%d+%-(%d+)%-"
  local id = guid:match("^Creature" .. tail) or guid:match("^Vehicle" .. tail)
  if not id then
    return nil
  end
  local name = safe(UnitName, "npc")
  return { id = tonumber(id), name = type(name) == "string" and not isSecret(name) and name or nil }
end

--- True if the open trainer teaches a profession rather than your class.
function Api.isProfessionTrainer()
  return safe(IsTradeskillTrainer) == true
end

function Api.vendorRepairs()
  return safe(CanMerchantRepair) == true
end

--- How far a quest's objectives have got, as one number that only grows
--- while you make progress (sum of counts plus finished objectives).
function Api.questProgress(questID)
  local list = C_QuestLog and safe(C_QuestLog.GetQuestObjectives, questID)
  if type(list) ~= "table" then
    return nil
  end
  local total = 0
  for _, o in ipairs(list) do
    if type(o) == "table" then
      total = total + (type(o.numFulfilled) == "number" and o.numFulfilled or 0) + (o.finished and 1 or 0)
    end
  end
  return total
end

--- Quests in the log: { questID, title, complete }.
function Api.questLog()
  local quests = {}
  local Q = C_QuestLog
  if Q and Q.GetNumQuestLogEntries and Q.GetInfo then
    local n = safe(Q.GetNumQuestLogEntries) or 0
    for i = 1, n do
      local info = safe(Q.GetInfo, i)
      if type(info) == "table" and not info.isHeader and not info.isHidden
        and type(info.questID) == "number" and info.questID > 0 then
        local complete = safe(Q.IsComplete, info.questID)
        if complete == nil then
          complete = info.isComplete == true or info.isComplete == 1
        end
        local tag = safe(Q.GetQuestTagInfo, info.questID)
        local group = (type(info.suggestedGroup) == "number" and info.suggestedGroup > 1)
          or (type(tag) == "table" and (tag.isElite == true or tag.tagID == 1))
        quests[#quests + 1] = {
          questID = info.questID, title = info.title, complete = complete == true,
          level = info.level, group = group == true,
        }
      end
    end
  elseif GetNumQuestLogEntries and GetQuestLogTitle then
    local n = safe(GetNumQuestLogEntries) or 0
    for i = 1, n do
      local title, level, suggestedGroup, isHeader, _, isComplete, _, questID = safe(GetQuestLogTitle, i)
      if title and not isHeader and type(questID) == "number" and questID > 0 then
        quests[#quests + 1] = {
          questID = questID, title = title, complete = isComplete == 1 or isComplete == true,
          level = level, group = type(suggestedGroup) == "number" and suggestedGroup > 1,
        }
      end
    end
  end
  return quests
end

--- true / false, or nil when the client cannot say.
function Api.turnedIn(questID)
  local fn = (C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted) or IsQuestFlaggedCompleted
  local r = safe(fn, questID)
  if r == nil then
    return nil
  end
  return r == true or r == 1
end

--- mapID, x, y of the player (x and y from 0 to 1). Any of them may be nil.
function Api.position()
  if not (C_Map and C_Map.GetBestMapForUnit and C_Map.GetPlayerMapPosition) then
    return nil
  end
  local mapID = safe(C_Map.GetBestMapForUnit, "player")
  if type(mapID) ~= "number" then
    return nil
  end
  local pos = safe(C_Map.GetPlayerMapPosition, mapID, "player")
  if not pos or not pos.GetXY then
    return mapID
  end
  local x, y = safe(pos.GetXY, pos)
  if isSecret(x) or isSecret(y) then
    return mapID
  end
  return mapID, x, y
end

--- Where the game points for a quest right now: { mapID, x, y } or nil.
function Api.questTarget(questID)
  local Q = C_QuestLog
  local mapID = Api.position()
  if mapID and Q and Q.GetQuestsOnMap then
    local list = safe(Q.GetQuestsOnMap, mapID)
    if type(list) == "table" then
      for _, poi in ipairs(list) do
        if poi.questID == questID and type(poi.x) == "number" and type(poi.y) == "number" then
          return { mapID = mapID, x = poi.x, y = poi.y }
        end
      end
    end
  end
  if Q and Q.GetNextWaypoint then
    local m, x, y = safe(Q.GetNextWaypoint, questID)
    if type(m) == "number" and type(x) == "number" and type(y) == "number" then
      return { mapID = m, x = x, y = y }
    end
  end
  if mapID and QuestPOIGetIconInfo then
    local _, x, y = safe(QuestPOIGetIconInfo, questID)
    if type(x) == "number" and type(y) == "number" then
      return { mapID = mapID, x = x, y = y }
    end
  end
  return nil
end

--- Player facing in radians (0 north, counter-clockwise), or nil.
function Api.facing()
  local f = safe(GetPlayerFacing)
  if type(f) ~= "number" or isSecret(f) then
    return nil
  end
  return f
end

--- Width and height of a map in yards, or nil.
function Api.mapSize(mapID)
  if not (C_Map and C_Map.GetMapWorldSize) then
    return nil
  end
  local w, h = safe(C_Map.GetMapWorldSize, mapID)
  if type(w) == "number" and type(h) == "number" and w > 0 and h > 0 then
    return w, h
  end
  return nil
end

function Api.mapName(mapID)
  local info = C_Map and safe(C_Map.GetMapInfo, mapID)
  return type(info) == "table" and info.name or nil
end

--- The target's coordinates on another map (usually the player's), so the
--- arrow can point across zone borders. Returns x, y or nil.
function Api.translate(target, mapID)
  if target.mapID == mapID then
    return target.x, target.y
  end
  if not (C_Map and C_Map.GetWorldPosFromMapPos and C_Map.GetMapPosFromWorldPos and CreateVector2D) then
    return nil
  end
  local continent, world = safe(C_Map.GetWorldPosFromMapPos, target.mapID, CreateVector2D(target.x, target.y))
  if not (continent and world) then
    return nil
  end
  local _, pos = safe(C_Map.GetMapPosFromWorldPos, continent, world, mapID)
  if not (pos and pos.GetXY) then
    return nil
  end
  return safe(pos.GetXY, pos)
end

--- Quest givers ("!") the game shows on a map: { questID, title, target }.
--- Only works if the client exposes them; returns an empty list otherwise.
function Api.availableQuests(mapID)
  local out = {}
  local QL = C_QuestLine
  if not (mapID and QL and QL.GetAvailableQuestLines) then
    return out
  end
  if QL.RequestQuestLinesForMap then
    try(QL.RequestQuestLinesForMap, mapID)
  end
  local lines = safe(QL.GetAvailableQuestLines, mapID)
  if type(lines) ~= "table" then
    return out
  end
  for _, info in ipairs(lines) do
    if type(info) == "table" and type(info.questID) == "number" and not info.isHidden
      and type(info.x) == "number" and type(info.y) == "number" then
      out[#out + 1] = {
        questID = info.questID,
        title = info.questName or info.questLineName,
        target = { mapID = mapID, x = info.x, y = info.y },
      }
    end
  end
  return out
end

local watchedByUs

--- Stops highlighting the quest TrailMate focused, and removes it from the
--- objective tracker only if TrailMate was the one who added it.
function Api.unfocusQuest()
  if watchedByUs and C_QuestLog and C_QuestLog.RemoveQuestWatch then
    try(C_QuestLog.RemoveQuestWatch, watchedByUs)
  end
  watchedByUs = nil
end

--- Highlights a quest of the log the way the game does when you click it:
--- super-tracked on the map, shown in the objective tracker and selected in
--- the quest log. Returns true if the game accepted it.
function Api.focusQuest(questID)
  Api.unfocusQuest()
  local Q = C_QuestLog
  if not questID or not Q then
    return false
  end
  if Q.GetLogIndexForQuestID and not safe(Q.GetLogIndexForQuestID, questID) then
    return false -- not in the log (yet): nothing to highlight
  end
  if Q.AddQuestWatch and Q.GetQuestWatchType and safe(Q.GetQuestWatchType, questID) == nil then
    if try(Q.AddQuestWatch, questID) then
      watchedByUs = questID
    end
  end
  if Q.SetSelectedQuest then
    try(Q.SetSelectedQuest, questID)
  end
  if C_SuperTrack and C_SuperTrack.SetSuperTrackedQuestID then
    return (try(C_SuperTrack.SetSuperTrackedQuestID, questID))
  end
  return false
end

local tomtomUid, pinSet = nil, false

function Api.clearArrow()
  if tomtomUid and TomTom and TomTom.RemoveWaypoint then
    try(TomTom.RemoveWaypoint, TomTom, tomtomUid)
  end
  tomtomUid = nil
  if pinSet and C_Map and C_Map.ClearUserWaypoint then
    try(C_Map.ClearUserWaypoint)
  end
  pinSet = false
end

--- Marks a target on the map. Uses TomTom when it is installed; otherwise the
--- game's own map pin, unless the quest is already highlighted (focused).
--- Returns the method used, or nil.
function Api.setArrow(target, title, focused)
  Api.clearArrow()
  if TomTom and TomTom.AddWaypoint then
    -- TomTom draws the map and minimap marks; TrailMate draws its own arrow.
    local uid = safe(TomTom.AddWaypoint, TomTom, target.mapID, target.x, target.y,
      { title = title, persistent = false, minimap = true, world = true, crazy = false })
    if uid then
      tomtomUid = uid
      return "TomTom"
    end
  end
  if focused then
    return "quest"
  end
  if C_Map and C_Map.SetUserWaypoint and UiMapPoint and UiMapPoint.CreateFromCoordinates then
    if C_Map.CanSetUserWaypointOnMap and not safe(C_Map.CanSetUserWaypointOnMap, target.mapID) then
      return nil
    end
    local point = safe(UiMapPoint.CreateFromCoordinates, target.mapID, target.x, target.y)
    if point and try(C_Map.SetUserWaypoint, point) then
      pinSet = true
      if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
        try(C_SuperTrack.SetSuperTrackedUserWaypoint, true)
      end
      return "map pin"
    end
  end
  return nil
end

-- Bags ---------------------------------------------------------------------

local function bagIds()
  local last = (NUM_BAG_SLOTS or 4) + (NUM_REAGENTBAG_SLOTS or 0)
  local ids = {}
  for bag = 0, last do
    ids[#ids + 1] = bag
  end
  return ids
end

local function numSlots(bag)
  local fn = (C_Container and C_Container.GetContainerNumSlots) or GetContainerNumSlots
  return safe(fn, bag) or 0
end

local function slotInfo(bag, slot)
  if C_Container and C_Container.GetContainerItemInfo then
    local info = safe(C_Container.GetContainerItemInfo, bag, slot)
    if type(info) == "table" then
      return info.itemID, info.stackCount, info.quality, info.isBound, info.hyperlink
    end
    return nil
  end
  local _, count, _, quality, _, _, link, _, _, itemID = safe(GetContainerItemInfo, bag, slot)
  return itemID, count, quality, nil, link
end

local function isQuestItem(bag, slot)
  if C_Container and C_Container.GetContainerItemQuestInfo then
    local info = safe(C_Container.GetContainerItemQuestInfo, bag, slot)
    return type(info) == "table" and info.isQuestItem == true
  end
  local isQuest = safe(GetContainerItemQuestInfo, bag, slot)
  return isQuest == true or isQuest == 1
end

local function itemInfo(itemID)
  local fn = (C_Item and C_Item.GetItemInfo) or GetItemInfo
  local name, _, quality, itemLevel, _, _, _, _, equipLoc, _, sellPrice, classID = safe(fn, itemID)
  if not name then
    return nil
  end
  return { quality = quality, itemLevel = itemLevel, equipLoc = equipLoc, sellPrice = sellPrice, classID = classID }
end

local function wornLevel(slot)
  local id = safe(GetInventoryItemID, "player", slot)
  local info = id and itemInfo(id)
  return info and info.itemLevel
end

-- Item level worn in the slot for an equip location. For rings and trinkets,
-- the lower of the two, so "worse than both" is what triggers "sell".
local function equippedLevel(equipLoc)
  local slot = ns.Bags.SLOT_FOR_EQUIPLOC[equipLoc or ""]
  if not slot then
    return nil
  end
  local a = wornLevel(slot)
  if slot == 11 or slot == 13 then
    local b = wornLevel(slot + 1)
    if a and b then
      return math.min(a, b)
    end
    return nil
  end
  return a
end

--- Items in the bags, with what the advisor needs. Items whose data the
--- client has not loaded yet are left out until the next look.
function Api.bagItems()
  local items = {}
  for _, bag in ipairs(bagIds()) do
    for slot = 1, numSlots(bag) do
      local itemID, count, quality, isBound, link = slotInfo(bag, slot)
      if itemID then
        local info = itemInfo(itemID)
        if info then
          items[#items + 1] = {
            itemID = itemID,
            count = count or 1,
            quality = quality or info.quality,
            sellPrice = info.sellPrice,
            classID = info.classID,
            isQuest = isQuestItem(bag, slot),
            isBound = isBound,
            equipLoc = info.equipLoc,
            itemLevel = info.itemLevel,
            equippedLevel = equippedLevel(info.equipLoc),
            link = link,
          }
        end
      end
    end
  end
  return items
end

--- Free and total slots in normal bags.
function Api.bagSpace()
  local free, total = 0, 0
  local freeFn = (C_Container and C_Container.GetContainerNumFreeSlots) or GetContainerNumFreeSlots
  for _, bag in ipairs(bagIds()) do
    local n, bagType = safe(freeFn, bag)
    if (bagType or 0) == 0 then
      free = free + (n or 0)
      total = total + numSlots(bag)
    end
  end
  return free, total
end

-- Trainer ------------------------------------------------------------------

local scanner

local function trainerSpellID(index)
  if C_TooltipInfo and C_TooltipInfo.GetTrainerService then
    local data = safe(C_TooltipInfo.GetTrainerService, index)
    if type(data) == "table" and type(data.id) == "number" then
      return data.id
    end
  end
  if not scanner then
    scanner = safe(CreateFrame, "GameTooltip", "TrailMateScanTooltip", nil, "GameTooltipTemplate")
    if not scanner then
      return nil
    end
  end
  try(scanner.SetOwner, scanner, UIParent, "ANCHOR_NONE")
  if not try(scanner.SetTrainerService, scanner, index) then
    return nil
  end
  local _, id = safe(scanner.GetSpell, scanner)
  scanner:Hide()
  return type(id) == "number" and id or nil
end

--- Services at the open trainer: { index, name, status, cost, reqLevel, spellID }.
function Api.trainerServices()
  local services = {}
  local n = safe(GetNumTrainerServices) or 0
  for i = 1, n do
    local name, rank, category = safe(GetTrainerServiceInfo, i)
    if name and category ~= "header" then
      local baseName = name
      if type(rank) == "string" and rank ~= "" then
        name = name .. " (" .. rank .. ")"
      end
      services[#services + 1] = {
        index = i,
        name = name,
        baseName = baseName,
        status = category,
        cost = safe(GetTrainerServiceCost, i) or 0,
        reqLevel = safe(GetTrainerServiceLevelReq, i),
        spellID = trainerSpellID(i),
      }
    end
  end
  return services
end

-- Diagnostics --------------------------------------------------------------

Api.PROBES = {
  "C_QuestLog.GetInfo", "C_QuestLog.IsComplete", "C_QuestLog.IsQuestFlaggedCompleted",
  "C_QuestLog.GetQuestsOnMap", "C_QuestLog.GetNextWaypoint", "GetQuestLogTitle",
  "IsQuestFlaggedCompleted", "QuestPOIGetIconInfo",
  "C_Map.GetBestMapForUnit", "C_Map.GetPlayerMapPosition", "C_Map.SetUserWaypoint",
  "C_SuperTrack.SetSuperTrackedUserWaypoint", "UiMapPoint.CreateFromCoordinates",
  "C_Container.GetContainerItemInfo", "GetContainerItemInfo", "C_Item.GetItemInfo", "GetItemInfo",
  "GetTrainerServiceInfo", "GetTrainerServiceLevelReq", "C_TooltipInfo.GetTrainerService",
  "issecretvalue", "C_AddOns.GetAddOnMetadata", "TomTom.AddWaypoint",
  "GetPlayerFacing", "C_Map.GetMapWorldSize", "C_Map.GetWorldPosFromMapPos",
  "C_Map.GetMapPosFromWorldPos", "CreateVector2D", "C_QuestLine.GetAvailableQuestLines",
  "IsSpellKnown", "IsPlayerSpell", "C_SuperTrack.SetSuperTrackedQuestID",
  "C_QuestLog.AddQuestWatch", "C_QuestLog.SetSelectedQuest", "C_QuestLog.GetLogIndexForQuestID",
}

--- Lines describing what this client exposes. No names, nothing personal.
function Api.diagnose()
  local lines = {}
  local version, build, _, toc = safe(GetBuildInfo)
  lines[#lines + 1] = ("client %s build %s interface %s locale %s"):format(
    tostring(version), tostring(build), tostring(toc), tostring(safe(GetLocale)))
  lines[#lines + 1] = ("class %s level %s"):format(tostring(Api.class()), tostring(Api.level()))
  local missing = {}
  for _, path in ipairs(Api.PROBES) do
    if type(resolve(path)) ~= "function" then
      missing[#missing + 1] = path
    end
  end
  lines[#lines + 1] = "missing: " .. (#missing > 0 and table.concat(missing, ", ") or "none")
  local quests = Api.questLog()
  local first = quests[1]
  lines[#lines + 1] = ("quests %d, first id %s complete %s turnedIn %s"):format(#quests,
    tostring(first and first.questID), tostring(first and first.complete),
    tostring(first and Api.turnedIn(first.questID)))
  local mapID, x, y = Api.position()
  lines[#lines + 1] = ("map %s x %s y %s"):format(tostring(mapID), tostring(x), tostring(y))
  local target = first and Api.questTarget(first.questID)
  lines[#lines + 1] = ("first quest target %s"):format(target and
    ("%d %.3f %.3f"):format(target.mapID, target.x, target.y) or "none")
  local free, total = Api.bagSpace()
  lines[#lines + 1] = ("bags %d free of %d, items read %d"):format(free, total, #Api.bagItems())
  local w, h
  if mapID then
    w, h = Api.mapSize(mapID)
  end
  lines[#lines + 1] = ("facing %s map size %s x %s available quests on map %d"):format(
    tostring(Api.facing()), tostring(w), tostring(h), #Api.availableQuests(mapID))
  local atlas = rawget(_G, "TrailMateDB") and TrailMateDB.atlas
  if type(atlas) == "table" then
    lines[#lines + 1] = ("atlas: %d npcs, %d quests learned"):format(ns.Atlas.counts(atlas))
  end
  return lines
end
