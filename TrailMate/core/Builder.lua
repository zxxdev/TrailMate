-- Builds a plan from the quest log, so the addon is useful before any data
-- pack or bridge exists. Pure Lua 5.1.
--
-- It decides, like a leveling guide would:
--   1. Classify every quest for the player's level: ready to turn in, fine,
--      hard (orange), too hard (red), group/elite, or trivial (grey).
--   2. Pick ONE zone to work in: the one with the most worth doing, with a
--      bonus for staying where you are (travelling costs time).
--   3. Route that zone nearest-first: turn in what is ready, do what is fine
--      or hard, then turn in what was done. Nothing from other zones.
--   4. Report the rest: what to leave for now, what to consider abandoning,
--      and which zones come later. When the zone is finished the addon
--      rebuilds and the next zone wins.
--
-- Input quests: { questID, title, complete, level, group, zone,
--                 target = { mapID, x, y } or nil }
-- player: { mapID, x, y, level }

local _, ns = ...

local Builder = {}
ns.Builder = Builder

-- Nearest quest givers added to a plan; the rest wait for the next rebuild.
Builder.MAX_OFFERS = 10
-- Quest level minus player level from which a quest is hard (orange) and too
-- hard for now (red), as the game colours them.
Builder.HARD_DIFF = 3
Builder.TOO_HARD_DIFF = 5
-- Points a quest gives to its zone, and the bonus for the zone you are in.
Builder.SCORE = { ready = 3, ok = 2, hard = 1, trivial = 0, tooHard = 0, group = 0 }
Builder.HERE_BONUS = 2

local IN_PLAN = { ready = true, ok = true, hard = true }

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

local function validQuests(list, exclude)
  local out = {}
  for _, q in ipairs(list or {}) do
    if type(q.questID) == "number" and q.questID > 0 and not (exclude and exclude[q.questID]) then
      out[#out + 1] = q
    end
  end
  return out
end

--- Highest quest level that counts as trivial (grey) for a player level,
--- following the classic rule.
function Builder.grayLevel(level)
  if level <= 5 then
    return 0
  elseif level <= 39 then
    return level - math.floor(level / 10) - 5
  elseif level <= 59 then
    return level - math.floor(level / 5) - 1
  end
  return level - 9
end

--- "ready", "ok", "hard", "tooHard", "group" or "trivial".
function Builder.classify(q, playerLevel)
  if q.complete then
    return "ready"
  end
  if q.group then
    return "group"
  end
  if type(q.level) ~= "number" or type(playerLevel) ~= "number" then
    return "ok"
  end
  local diff = q.level - playerLevel
  if diff >= Builder.TOO_HARD_DIFF then
    return "tooHard"
  end
  if q.level <= Builder.grayLevel(playerLevel) then
    return "trivial"
  end
  if diff >= Builder.HARD_DIFF then
    return "hard"
  end
  return "ok"
end

-- Groups quests by the map of their target, in first-seen order.
local function groupByMap(quests)
  local groups, keys = {}, {}
  for _, q in ipairs(quests) do
    local key = q.target and q.target.mapID or "none"
    if not groups[key] then
      groups[key] = { key = key, zone = q.zone, quests = {}, score = 0, count = 0 }
      keys[#keys + 1] = key
    end
    local g = groups[key]
    g.quests[#g.quests + 1] = q
    g.zone = g.zone or q.zone
    g.score = g.score + Builder.SCORE[q.class]
    if IN_PLAN[q.class] then
      g.count = g.count + 1
    end
  end
  return groups, keys
end

--- The zone to work in: highest score, staying here on a tie. Quests with no
--- known place never decide the zone. bonus(mapID), if given, adds how well
--- the zone suits the player's level (the leveling strategy).
function Builder.chooseZone(groups, keys, here, bonus)
  local best, bestScore = nil, nil
  for _, key in ipairs(keys) do
    local g = groups[key]
    if key ~= "none" and g.count > 0 then
      local score = g.score + (key == here and Builder.HERE_BONUS or 0) + (bonus and bonus(key) or 0)
      if bestScore == nil or score > bestScore or (score == bestScore and key == here) then
        best, bestScore = key, score
      end
    end
  end
  -- Nothing has a known place: work through those quests in log order.
  if not best and groups.none and groups.none.count > 0 then
    best = "none"
  end
  return best
end

local REASON = {
  tooHard = "Too hard for now (level %s)",
  group = "Group or elite quest",
  trivial = "Gives little XP now (level %s)",
}

--- Returns plan, report; or nil, report when there is nothing to do.
--- available (optional) are quest givers the game shows on the map:
--- { questID, title, target }. L is the locale table for the texts.
--- report = { zone, later = { { zone, count } }, notNow = { { title, reason } },
---            abandon = { { title, reason } }, counts = { [mapID] = quests worth doing } }
--- opts.zoneBonus(mapID) weighs zones by the leveling strategy; opts.focus
--- (a mapID) is a zone the player chose, which wins whenever it has quests.
function Builder.fromQuestLog(quests, player, L, available, opts)
  local max = ns.Plan.MAX_TEXT - 40
  local level = player and player.level
  local here = player and player.mapID
  local valid = validQuests(quests)
  local inLog = {}
  for _, q in ipairs(valid) do
    inLog[q.questID] = true
    q.class = Builder.classify(q, level)
  end
  local offers = orderByDistance(validQuests(available, inLog), player)
  for i = #offers, Builder.MAX_OFFERS + 1, -1 do
    offers[i] = nil
  end

  local report = { later = {}, notNow = {}, abandon = {}, counts = {} }
  for _, q in ipairs(valid) do
    local reason = REASON[q.class]
    if reason then
      local entry = { title = q.title, reason = L[reason]:format(tostring(q.level)) }
      local list = q.class == "trivial" and report.abandon or report.notNow
      list[#list + 1] = entry
    end
  end

  local groups, keys = groupByMap(valid)
  for _, key in ipairs(keys) do
    if key ~= "none" then
      report.counts[key] = groups[key].count
    end
  end
  local chosen = opts and opts.focus
  local focus
  if chosen and groups[chosen] and groups[chosen].count > 0 then
    focus = chosen
  else
    focus = Builder.chooseZone(groups, keys, here, opts and opts.zoneBonus)
  end
  if not focus and #offers > 0 then
    focus = here
  end
  for _, key in ipairs(keys) do
    local g = groups[key]
    if key ~= focus and g.count > 0 then
      report.later[#report.later + 1] = { zone = g.zone or L["Unknown place"], count = g.count }
    end
  end
  table.sort(report.later, function(a, b)
    return a.count > b.count
  end)
  if not focus then
    return nil, report
  end
  local group = groups[focus] or { quests = {}, zone = nil }
  report.zone = group.zone or (offers[1] and offers[1].zone)

  local steps = {}
  local function add(kind, q, prefix, target)
    local step = {
      id = kind .. "-" .. q.questID, type = kind, questID = q.questID, text = L[prefix] .. clip(q.title, max),
    }
    if target then
      step.mapID, step.x, step.y = target.mapID, target.x, target.y
    end
    if q.class == "hard" and kind == "complete" then
      step.why = L["Hard (level %s): be careful or bring help"]:format(tostring(q.level))
    end
    steps[#steps + 1] = step
  end

  for _, q in ipairs(offers) do
    add("accept", q, "Pick up: ", q.target)
  end
  local list = {}
  for _, q in ipairs(group.quests) do
    if IN_PLAN[q.class] then
      list[#list + 1] = q
    end
  end
  local first = list[1] and list[1].target
  local start = (focus == here and player) or (first and { mapID = focus, x = first.x, y = first.y })
  local route = orderByDistance(list, start)
  local doneHere = {}
  for _, q in ipairs(route) do
    if q.complete then
      add("turnin", q, "Turn in: ")
    else
      add("complete", q, "Do: ")
      doneHere[#doneHere + 1] = q
    end
  end
  for _, q in ipairs(offers) do
    add("complete", q, "Do: ")
  end
  for _, q in ipairs(doneHere) do
    add("turnin", q, "Turn in: ")
  end
  for _, q in ipairs(offers) do
    add("turnin", q, "Turn in: ")
  end

  local all = {}
  for _, q in ipairs(route) do
    all[#all + 1] = q
  end
  for _, q in ipairs(offers) do
    all[#all + 1] = q
  end
  return {
    version = ns.Plan.FORMAT_VERSION,
    id = Builder.planId(all),
    title = clip(report.zone or L["Quest log"], max),
    steps = steps,
  }, report
end

--- True if the plan was built by this module (and can be rebuilt freely).
function Builder.isAuto(plan)
  return type(plan) == "table" and type(plan.id) == "string" and plan.id:find("^questlog%-") ~= nil
end
