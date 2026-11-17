-- The atlas: TrailMate's own data, learned while you play. Pure Lua 5.1.
--
-- Every entry was seen in the game by one of your characters: who gave a
-- quest and where, where it was turned in, where its objectives progressed,
-- and where trainers, vendors and flight masters stand. It is shared by all
-- characters of the account, so an alt already knows the way.
--
-- It lives in saved variables, which are files on disk: everything read back
-- is checked, and anything malformed is ignored.

local _, ns = ...

local Atlas = {}
ns.Atlas = Atlas

Atlas.SCHEMA = 1
Atlas.MAX_AREAS = 12 -- objective sample points kept per quest
Atlas.MAX_TEXT = 80

local function isNum(v)
  return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

local function isPlace(p)
  return type(p) == "table" and isNum(p.mapID) and p.mapID > 0 and isNum(p.x) and isNum(p.y)
    and p.x >= 0 and p.x <= 1 and p.y >= 0 and p.y <= 1 and not (p.x == 0 and p.y == 0)
end
Atlas.isPlace = isPlace

local function place(p)
  return { mapID = p.mapID, x = p.x, y = p.y }
end

local function text(v)
  if type(v) == "string" and v ~= "" then
    return v:sub(1, Atlas.MAX_TEXT)
  end
  return nil
end

--- Returns a usable atlas table, creating or repairing it in place.
function Atlas.ensure(db)
  if type(db.atlas) ~= "table" or db.atlas.schema ~= Atlas.SCHEMA then
    db.atlas = { schema = Atlas.SCHEMA, npcs = {}, quests = {} }
  end
  local a = db.atlas
  if type(a.npcs) ~= "table" then
    a.npcs = {}
  end
  if type(a.quests) ~= "table" then
    a.quests = {}
  end
  return a
end

local function quest(atlas, questID)
  local q = atlas.quests[questID]
  if type(q) ~= "table" then
    q = {}
    atlas.quests[questID] = q
  end
  return q
end

--- Remembers an NPC: { id, name, role, class }, standing at place p.
--- role: "trainer", "profession", "vendor", "repair", "flight" or "quest".
function Atlas.recordNpc(atlas, npc, p)
  if not (isNum(npc.id) and npc.id > 0 and isPlace(p)) then
    return false
  end
  local e = atlas.npcs[npc.id]
  if type(e) ~= "table" then
    e = { roles = {} }
    atlas.npcs[npc.id] = e
  end
  if type(e.roles) ~= "table" then
    e.roles = {}
  end
  e.name = text(npc.name) or e.name
  e.place = place(p)
  if npc.role then
    e.roles[npc.role] = true
  end
  if npc.role == "trainer" and text(npc.class) then
    e.class = npc.class
  end
  if text(npc.faction) then
    e.faction = npc.faction
  end
  return true
end

--- Remembers where a quest was picked up. info: { title, level, npcID, faction }.
function Atlas.recordStart(atlas, questID, info, p)
  if not (isNum(questID) and questID > 0 and isPlace(p)) then
    return false
  end
  local q = quest(atlas, questID)
  q.title = text(info.title) or q.title
  q.level = isNum(info.level) and info.level or q.level
  q.faction = text(info.faction) or q.faction
  q.start = place(p)
  q.startNpc = isNum(info.npcID) and info.npcID or q.startNpc
  return true
end

--- Remembers where a quest was turned in.
function Atlas.recordFinish(atlas, questID, info, p)
  if not (isNum(questID) and questID > 0 and isPlace(p)) then
    return false
  end
  local q = quest(atlas, questID)
  q.title = text(info.title) or q.title
  q.finish = place(p)
  q.finishNpc = isNum(info.npcID) and info.npcID or q.finishNpc
  return true
end

--- Remembers a place where a quest's objectives moved forward. Keeps the
--- most recent points, skipping ones very close to a point already kept.
function Atlas.recordProgress(atlas, questID, p)
  if not (isNum(questID) and questID > 0 and isPlace(p)) then
    return false
  end
  local q = quest(atlas, questID)
  if type(q.areas) ~= "table" then
    q.areas = {}
  end
  for _, a in ipairs(q.areas) do
    if isPlace(a) and a.mapID == p.mapID and (a.x - p.x) ^ 2 + (a.y - p.y) ^ 2 < 0.0004 then
      return false
    end
  end
  table.insert(q.areas, place(p))
  while #q.areas > Atlas.MAX_AREAS do
    table.remove(q.areas, 1)
  end
  return true
end

--- Nearest valid place to the player: on the player's map first, otherwise
--- the one with the lowest map id (stable, whatever the table order).
function Atlas.nearest(places, player)
  local best, bestD
  for _, p in ipairs(places) do
    if isPlace(p) then
      local d
      if player and p.mapID == player.mapID and isNum(player.x) and isNum(player.y) then
        d = (p.x - player.x) ^ 2 + (p.y - player.y) ^ 2
      else
        d = 10 + p.mapID
      end
      if bestD == nil or d < bestD then
        best, bestD = p, d
      end
    end
  end
  return best and place(best) or nil
end

--- Where to go for a quest in the log, from what was seen before: the
--- turn-in once complete; otherwise where its objectives progressed.
function Atlas.questTarget(atlas, questID, complete, player)
  local q = atlas.quests[questID]
  if type(q) ~= "table" then
    return nil
  end
  if complete then
    return isPlace(q.finish) and place(q.finish) or nil
  end
  return Atlas.nearest(type(q.areas) == "table" and q.areas or {}, player)
end

--- Quests seen before (by any character of the same faction) that can be
--- picked up on the player's map now. ctx: { level, faction, isDone, inLog }.
--- Only quests whose level is known and fits are offered.
function Atlas.offers(atlas, ctx, player)
  local out = {}
  if not (player and player.mapID) then
    return out
  end
  for questID, q in pairs(atlas.quests) do
    if type(q) == "table" and isPlace(q.start) and q.start.mapID == player.mapID and isNum(q.level)
      and (q.faction == nil or q.faction == ctx.faction)
      and not ctx.inLog(questID) and not ctx.isDone(questID)
      and q.level - ctx.level < ns.Builder.TOO_HARD_DIFF and q.level > ns.Builder.grayLevel(ctx.level) then
      out[#out + 1] = { questID = questID, title = q.title, level = q.level, target = place(q.start) }
    end
  end
  table.sort(out, function(a, b)
    return a.questID < b.questID
  end)
  return out
end

--- Nearest known NPC with a role (and class, for trainers): place, name.
function Atlas.findNpc(atlas, role, class, faction, player)
  local places, names = {}, {}
  for _, e in pairs(atlas.npcs) do
    if type(e) == "table" and type(e.roles) == "table" and e.roles[role] and isPlace(e.place)
      and (class == nil or e.class == class) and (e.faction == nil or faction == nil or e.faction == faction) then
      places[#places + 1] = e.place
      names[e.place] = e.name
    end
  end
  local best = Atlas.nearest(places, player)
  if not best then
    return nil
  end
  for p, name in pairs(names) do
    if p.mapID == best.mapID and p.x == best.x and p.y == best.y then
      return best, name
    end
  end
  return best, nil
end

--- Counts for /tm diag.
function Atlas.counts(atlas)
  local npcs, quests = 0, 0
  for _ in pairs(atlas.npcs) do
    npcs = npcs + 1
  end
  for _ in pairs(atlas.quests) do
    quests = quests + 1
  end
  return npcs, quests
end
