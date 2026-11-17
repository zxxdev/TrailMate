-- Character snapshot with a schema version: what the bridge will read later.
-- Built from a whitelist, so names of characters, accounts, guilds or realms
-- can never end up in it, whatever the adapter passes. Pure Lua 5.1.

local _, ns = ...

local State = {}
ns.State = State

State.SCHEMA_VERSION = 1
State.MAX_ITEMS = 200
State.MAX_QUESTS = 50

local function num(v)
  if type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge then
    return v
  end
  return nil
end

local function str(v, max)
  if type(v) == "string" and #v > 0 then
    return v:sub(1, max or 80)
  end
  return nil
end

--- Builds the snapshot from raw values gathered by the adapter.
function State.build(raw, now)
  raw = raw or {}
  local snap = {
    schema = State.SCHEMA_VERSION,
    takenAt = num(now),
    class = str(raw.class, 20),
    level = num(raw.level),
    xp = num(raw.xp),
    xpMax = num(raw.xpMax),
    money = num(raw.money),
    position = nil,
    quests = {},
    bags = { free = num(raw.bagsFree), total = num(raw.bagsTotal), items = {} },
  }
  if num(raw.mapID) then
    snap.position = { mapID = raw.mapID, x = num(raw.x), y = num(raw.y) }
  end
  for i, q in ipairs(raw.quests or {}) do
    if i > State.MAX_QUESTS then
      break
    end
    if num(q.questID) then
      snap.quests[#snap.quests + 1] = {
        questID = q.questID, title = str(q.title, 120), complete = q.complete == true,
      }
    end
  end
  for i, it in ipairs(raw.items or {}) do
    if i > State.MAX_ITEMS then
      break
    end
    if num(it.itemID) then
      snap.bags.items[#snap.bags.items + 1] = { itemID = it.itemID, count = num(it.count) or 1, quality = num(it.quality) }
    end
  end
  return snap
end

--- Checks a snapshot against the schema. Returns true, or nil and a reason.
function State.validate(snap)
  if type(snap) ~= "table" or snap.schema ~= State.SCHEMA_VERSION then
    return nil, "wrong schema"
  end
  if not ns.Plan.isPureData(snap) then
    return nil, "snapshot must contain only data"
  end
  local allowed = {
    schema = true, takenAt = true, class = true, level = true, xp = true, xpMax = true,
    money = true, position = true, quests = true, bags = true,
  }
  for k in pairs(snap) do
    if not allowed[k] then
      return nil, "unexpected field " .. tostring(k)
    end
  end
  if type(snap.quests) ~= "table" or type(snap.bags) ~= "table" then
    return nil, "missing quests or bags"
  end
  return true
end

--- Short human summary, one line per entry.
function State.summary(snap, L)
  local lines = {}
  lines[#lines + 1] = L["Class %s, level %s"]:format(tostring(snap.class), tostring(snap.level))
  if snap.xp and snap.xpMax and snap.xpMax > 0 then
    lines[#lines + 1] = L["XP %d%%"]:format(math.floor(snap.xp / snap.xpMax * 100))
  end
  if snap.money then
    lines[#lines + 1] = L["Gold %s"]:format(ns.formatMoney(snap.money))
  end
  if snap.position then
    lines[#lines + 1] = L["Map %d at %s, %s"]:format(snap.position.mapID,
      snap.position.x and ("%.1f"):format(snap.position.x * 100) or "?",
      snap.position.y and ("%.1f"):format(snap.position.y * 100) or "?")
  end
  lines[#lines + 1] = L["Quests in log: %d"]:format(#snap.quests)
  if snap.bags.free and snap.bags.total then
    lines[#lines + 1] = L["Bag slots free: %d of %d"]:format(snap.bags.free, snap.bags.total)
  end
  return lines
end
