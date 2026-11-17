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

--- Unspent talent points, or nil if the client does not say. Clients with
--- dual specs (like this one) answer through GetUnspentTalentPoints, while
--- UnitCharacterPoints may exist and say 0: take the highest answer.
function Api.talentPoints()
  local best
  -- pairs, not ipairs: a missing function leaves a hole in this list.
  for _, n in pairs({ safe(GetUnspentTalentPoints, false, false), (safe(GetUnspentTalentPoints)),
    (safe(UnitCharacterPoints, "player")) }) do
    if type(n) == "number" and (best == nil or n > best) then
      best = n
    end
  end
  return best
end

--- The player's talent trees, for core/Talents.lua, and the points already
--- placed but not applied yet ("Apply Changes"), which count as taken.
function Api.talentTree()
  local tabs, pending = {}, 0
  for tab = 1, safe(GetNumTalentTabs) or 0 do
    -- Classic answers name, icon, ...; later clients id, name, description, icon, ...
    local r = pack(try(GetTalentTabInfo, tab))
    local name, icon = r[2], r[3]
    if type(r[2]) == "number" then
      name, icon = r[3], r[5]
    end
    local talents = {}
    for index = 1, safe(GetNumTalents, tab) or 0 do
      local tname, ticon, tier, column, rank, maxRank, _, _, preview = safe(GetTalentInfo, tab, index)
      if type(tname) == "string" and type(tier) == "number" and type(column) == "number"
        and type(maxRank) == "number" then
        local taken = type(rank) == "number" and rank or 0
        if type(preview) == "number" and preview > taken then
          pending = pending + preview - taken
          taken = preview
        end
        local ptier, pcolumn = safe(GetTalentPrereqs, tab, index)
        talents[#talents + 1] = {
          index = index, name = tname, icon = ticon, tier = tier, column = column, rank = taken, maxRank = maxRank,
          prereq = type(ptier) == "number" and type(pcolumn) == "number" and { tier = ptier, column = pcolumn } or nil,
        }
      end
    end
    tabs[#tabs + 1] = { name = type(name) == "string" and name or ("Tree " .. tab), icon = icon, talents = talents }
  end
  return tabs, pending
end

-- Talent buttons in the game's talent window, by client generation.
local TALENT_BUTTONS = { "PlayerTalentFrameTalent", "TalentFrameTalent", "PlayerTalentFramePanel%dTalent" }

local function buttonIcon(b)
  local name = safe(b.GetName, b)
  local tex = rawget(b, "icon") or rawget(b, "Icon") or (name and rawget(_G, name .. "IconTexture"))
  return type(tex) == "table" and safe(tex.GetTexture, tex) or nil
end

--- The visible button of this talent in the game's talent window, or nil
--- (another tab is open). Matched by talent number and, if known, icon.
function Api.talentButton(tab, talent)
  for _, prefix in ipairs(TALENT_BUTTONS) do
    local base = prefix:find("%%d") and prefix:format(tab) or prefix
    for i = 1, 60 do
      local b = rawget(_G, base .. i)
      if type(b) ~= "table" then
        break
      end
      if safe(b.IsVisible, b) and safe(b.GetID, b) == talent.index then
        local icon = buttonIcon(b)
        if icon == nil or talent.icon == nil or tostring(icon):lower() == tostring(talent.icon):lower() then
          return b
        end
      end
    end
  end
  return nil
end

--- Opens the game's talent window (not in combat). Returns true if it could.
function Api.openTalents()
  if safe(InCombatLockdown) then
    return false
  end
  if type(ToggleTalentFrame) == "function" then
    return (pcall(ToggleTalentFrame))
  end
  return false
end

--- A big message in the middle of the screen with a sound, like a raid warning.
function Api.notice(text)
  local frame, info = rawget(_G, "RaidWarningFrame"), rawget(_G, "ChatTypeInfo")
  if frame and type(RaidNotice_AddMessage) == "function" then
    pcall(RaidNotice_AddMessage, frame, text, info and info.RAID_WARNING or { r = 1, g = 0.82, b = 0 })
  end
  if type(PlaySound) == "function" then
    pcall(PlaySound, SOUNDKIT and SOUNDKIT.RAID_WARNING or 8959)
  end
end

--- What the client says about talents, for the self-test: which functions
--- exist and the player's trees as the game reports them.
function Api.talentReport()
  local present = {}
  for _, name in ipairs({ "GetUnspentTalentPoints", "UnitCharacterPoints", "GetNumTalentTabs", "GetTalentTabInfo",
    "GetNumTalents", "GetTalentInfo", "GetActiveTalentGroup", "LearnTalent", "C_ClassTalents", "C_Traits",
    "PlayerTalentFrame", "TalentFrame" }) do
    present[#present + 1] = ("%s=%s"):format(name, type(rawget(_G, name)))
  end
  local lines = { table.concat(present, " ") }
  local tabs = safe(GetNumTalentTabs) or 0
  for tab = 1, tabs do
    local r = pack(try(GetTalentTabInfo, tab))
    local parts = {}
    for i = 2, math.min(r.n, 8) do
      parts[#parts + 1] = tostring(r[i])
    end
    local talents = {}
    for index = 1, safe(GetNumTalents, tab) or 0 do
      local name, _, tier, column, rank, maxRank = safe(GetTalentInfo, tab, index)
      talents[#talents + 1] = ("%s[%s,%s]%s/%s"):format(tostring(name), tostring(tier), tostring(column),
        tostring(rank), tostring(maxRank))
    end
    lines[#lines + 1] = ("tab %d: %s | %s"):format(tab, table.concat(parts, ", "), table.concat(talents, "; "))
  end
  return lines
end

-- Travel ---------------------------------------------------------------------

-- Continent maps of the classic world (Kalimdor, Eastern Kingdoms).
Api.CONTINENTS = { 1414, 1415 }
local HEARTHSTONE = 6948

--- World position of a map point: continent id, x, y in yards; or nil.
function Api.worldPos(mapID, x, y)
  if not (C_Map and C_Map.GetWorldPosFromMapPos and CreateVector2D and mapID and x and y) then
    return nil
  end
  local cont, pos = safe(C_Map.GetWorldPosFromMapPos, mapID, CreateVector2D(x, y))
  if not (cont and pos and pos.GetXY) then
    return nil
  end
  local wx, wy = safe(pos.GetXY, pos)
  if type(wx) ~= "number" or type(wy) ~= "number" then
    return nil
  end
  return { cont = cont, x = wx, y = wy }
end

local function nodeXY(n)
  local pos = n.position
  if type(pos) == "table" and pos.GetXY then
    return safe(pos.GetXY, pos)
  elseif type(pos) == "table" then
    return pos.x, pos.y
  end
  return nil
end

-- The other faction's flight path faction value, or nil if unknown.
local function enemyFaction()
  local F = Enum and Enum.FlightPathFaction
  local mine = Api.faction()
  if not F then
    return nil
  end
  if mine == "Horde" then
    return F.Alliance
  elseif mine == "Alliance" then
    return F.Horde
  end
  return nil
end

--- Flight points on the world map, without the other faction's:
--- { name, known, sure, cont, x, y (world), mapID, mx, my (for the arrow) }.
--- learned[contMap] = { [name] = true } are the ones this character was seen
--- to have at a flight master; with it, known is exact (sure = true).
--- Without it, every point of the player's faction counts as known but
--- not sure: the world map does not say which ones the character has.
function Api.flightNodes(learned)
  local out = {}
  local T = C_TaxiMap
  if not (T and T.GetTaxiNodesForMap) then
    return out
  end
  local enemy = enemyFaction()
  for _, contMap in ipairs(Api.CONTINENTS) do
    local mine = type(learned) == "table" and learned[contMap] or nil
    local nodes = safe(T.GetTaxiNodesForMap, contMap)
    for _, n in ipairs(type(nodes) == "table" and nodes or {}) do
      local mx, my = nodeXY(n)
      local w = type(mx) == "number" and Api.worldPos(contMap, mx, my)
      if w and type(n.name) == "string" and (enemy == nil or n.faction ~= enemy) then
        out[#out + 1] = {
          name = n.name, known = mine == nil or mine[n.name] == true, sure = mine ~= nil,
          cont = w.cont, x = w.x, y = w.y, mapID = contMap, mx = mx, my = my,
          state = n.state, faction = n.faction,
        }
      end
    end
  end
  return out
end

--- At an open flight map: the continent map, the current node's name, the
--- names it can reach, and every node shown (the flight map only shows the
--- ones this character has discovered).
function Api.taxiReach()
  local T = C_TaxiMap
  local mapID = safe(GetTaxiMapID)
  if not (T and T.GetAllTaxiNodes and mapID) then
    return nil
  end
  local nodes = safe(T.GetAllTaxiNodes, mapID)
  if type(nodes) ~= "table" then
    return nil
  end
  local states = Enum and Enum.FlightPathState or {}
  local currentState, reachableState = states.Current or 0, states.Reachable or 1
  local current, reachable, all = nil, {}, {}
  for _, n in ipairs(nodes) do
    if type(n.name) == "string" then
      all[#all + 1] = n.name
      if n.state == currentState then
        current = n.name
      elseif n.state == reachableState then
        reachable[#reachable + 1] = n.name
      end
    end
  end
  return current, reachable, all, mapID
end

--- The hearthstone: { name, ready, cooldown (seconds left), have } or nil.
function Api.hearth()
  local name = safe(GetBindLocation)
  if type(name) ~= "string" or name == "" then
    return nil
  end
  local countFn = (C_Item and C_Item.GetItemCount) or GetItemCount
  local have = (safe(countFn, HEARTHSTONE) or 0) > 0
  local cdFn = (C_Container and C_Container.GetItemCooldown) or GetItemCooldown
  local start, duration = safe(cdFn, HEARTHSTONE)
  local left = 0
  if type(start) == "number" and type(duration) == "number" and start > 0 then
    left = math.max(0, start + duration - (safe(GetTime) or 0))
  end
  return { name = name, have = have, ready = have and left == 0, cooldown = left }
end

--- The continent a zone belongs to (its uiMapID), or nil.
function Api.continentOf(mapID)
  local guard = 0
  while mapID and guard < 10 do
    local info = C_Map and safe(C_Map.GetMapInfo, mapID)
    if type(info) ~= "table" then
      return nil
    end
    if info.mapType == 2 then -- Enum.UIMapType.Continent
      return mapID
    end
    mapID, guard = info.parentMapID, guard + 1
  end
  return nil
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
