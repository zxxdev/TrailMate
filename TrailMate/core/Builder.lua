-- Builds a plan from the quest log, so the addon is useful before any data
-- pack or bridge exists. Pure Lua 5.1.
--
-- Input quests: { questID, title, complete, target = { mapID, x, y } or nil }
-- where target is where the game points for that quest right now.
-- Order: quests already complete are turned in first; the rest are visited by
-- nearest neighbour from the player (same map only), then turned in in the
-- same order. Quests without a point on the current map go last, in log order.

local _, ns = ...

local Builder = {}
ns.Builder = Builder

local function dist2(ax, ay, bx, by)
  local dx, dy = ax - bx, ay - by
  return dx * dx + dy * dy
end

local function hasPoint(q, mapID)
  local t = q.target
  return t ~= nil and t.mapID == mapID and type(t.x) == "number" and type(t.y) == "number"
end

-- Nearest-neighbour ordering. Fine for a quest log (35 quests at most).
local function orderByDistance(quests, player)
  local onMap, rest = {}, {}
  for _, q in ipairs(quests) do
    if player and hasPoint(q, player.mapID) then
      onMap[#onMap + 1] = q
    else
      rest[#rest + 1] = q
    end
  end
  local ordered = {}
  local x, y = player and player.x, player and player.y
  while #onMap > 0 do
    local best, bestD = 1, nil
    for i, q in ipairs(onMap) do
      local d = (x and y) and dist2(x, y, q.target.x, q.target.y) or i
      if bestD == nil or d < bestD then
        best, bestD = i, d
      end
    end
    local q = table.remove(onMap, best)
    ordered[#ordered + 1] = q
    x, y = q.target.x, q.target.y
  end
  for _, q in ipairs(rest) do
    ordered[#ordered + 1] = q
  end
  return ordered
end

local function clip(text, max)
  text = tostring(text or "?")
  if #text > max then
    text = text:sub(1, max)
  end
  return text
end

--- Stable plan id for a set of quests: same quests, same id, same progress.
function Builder.planId(quests)
  local ids = {}
  for _, q in ipairs(quests) do
    ids[#ids + 1] = q.questID
  end
  table.sort(ids)
  local h = 5381
  for _, id in ipairs(ids) do
    h = (h * 33 + id) % 2147483647
  end
  return ("questlog-%d-%d"):format(#ids, h)
end

--- Returns a plan (format v1) built from the quest log, or nil when the log
--- has no quests. L is the locale table for the step texts.
function Builder.fromQuestLog(quests, player, L)
  local max = ns.Plan.MAX_TEXT - 20
  local valid = {}
  for _, q in ipairs(quests or {}) do
    if type(q.questID) == "number" and q.questID > 0 then
      valid[#valid + 1] = q
    end
  end
  if #valid == 0 then
    return nil
  end

  local done, todo = {}, {}
  for _, q in ipairs(valid) do
    if q.complete then
      done[#done + 1] = q
    else
      todo[#todo + 1] = q
    end
  end
  todo = orderByDistance(todo, player)

  local steps = {}
  local function add(kind, q, text)
    steps[#steps + 1] = { id = kind .. "-" .. q.questID, type = kind, questID = q.questID, text = text }
  end
  for _, q in ipairs(done) do
    add("turnin", q, L["Turn in: "] .. clip(q.title, max))
  end
  for _, q in ipairs(todo) do
    add("complete", q, L["Do: "] .. clip(q.title, max))
  end
  for _, q in ipairs(todo) do
    add("turnin", q, L["Turn in: "] .. clip(q.title, max))
  end

  return {
    version = ns.Plan.FORMAT_VERSION,
    id = Builder.planId(valid),
    title = L["Quest log"],
    steps = steps,
  }
end
