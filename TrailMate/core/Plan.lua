-- Plan format v1 and the progress engine.
-- Pure Lua 5.1: no game API here, so all of it runs under busted.
-- A plan is pure data (strings, numbers, booleans, tables). It is validated
-- every time it is loaded, even when the addon built it itself, because from
-- the bridge onwards the file is written by a program from a model's answer.

local _, ns = ...

local Plan = {}
ns.Plan = Plan

Plan.FORMAT_VERSION = 1
Plan.MAX_STEPS = 400 -- a whole guide (the longest has 224)
Plan.MAX_TEXT = 200
Plan.MAX_ID = 64
Plan.NEAR = 0.1 -- a tenth of the map: "already there" for a guide's travel hints
Plan.MAX_DEPTH = 6
-- Arrival radius for "goto" steps, in map units (0..1 of the zone map).
-- Zones have different sizes, so this is approximate until zone sizes exist.
Plan.DEFAULT_RADIUS = 0.015

local STEP_TYPES = {
  accept = true,
  complete = true,
  turnin = true,
  ["goto"] = true,
  level = true,
  note = true,
}
Plan.STEP_TYPES = STEP_TYPES

local QUEST_TYPES = { accept = true, complete = true, turnin = true }

local function isPositiveInt(v)
  return type(v) == "number" and v > 0 and v == math.floor(v) and v < 2 ^ 31
end

local function isCoord(v)
  return type(v) == "number" and v >= 0 and v <= 1
end

local function isText(v, max)
  return type(v) == "string" and #v > 0 and #v <= max
end

local function isPureData(v, depth)
  local t = type(v)
  if t == "string" or t == "boolean" then
    return true
  end
  if t == "number" then
    return v == v and v ~= math.huge and v ~= -math.huge
  end
  if t ~= "table" or depth > Plan.MAX_DEPTH or getmetatable(v) ~= nil then
    return false
  end
  for k, val in pairs(v) do
    local kt = type(k)
    if kt ~= "string" and kt ~= "number" then
      return false
    end
    if not isPureData(val, depth + 1) then
      return false
    end
  end
  return true
end

--- True if v holds only strings, finite numbers, booleans and plain tables.
function Plan.isPureData(v)
  return isPureData(v, 0)
end

local function isArray(t)
  local n = 0
  for _ in pairs(t) do
    n = n + 1
  end
  return n == #t
end

local function checkStep(step)
  if type(step) ~= "table" then
    return "is not a table"
  end
  if not isText(step.id, Plan.MAX_ID) then
    return "has no valid id"
  end
  if not STEP_TYPES[step.type] then
    return "has an unknown type"
  end
  if not isText(step.text, Plan.MAX_TEXT) then
    return "has no valid text"
  end
  if step.why ~= nil and not isText(step.why, Plan.MAX_TEXT) then
    return "has an invalid why"
  end
  if QUEST_TYPES[step.type] and not isPositiveInt(step.questID) then
    return "needs a questID"
  end
  if step.type == "level" and not (isPositiveInt(step.level) and step.level <= 100) then
    return "needs a level"
  end
  local hasPoint = step.mapID ~= nil or step.x ~= nil or step.y ~= nil
  if step.type == "goto" or hasPoint then
    if not (isPositiveInt(step.mapID) and isCoord(step.x) and isCoord(step.y)) then
      return "has an invalid map point"
    end
  end
  if step.radius ~= nil and not (type(step.radius) == "number" and step.radius > 0 and step.radius <= 1) then
    return "has an invalid radius"
  end
  -- Who the step is about, to show it: a creature id (its model) and a name.
  if step.creature ~= nil and not isPositiveInt(step.creature) then
    return "has an invalid creature"
  end
  if step.who ~= nil and not isText(step.who, Plan.MAX_TEXT) then
    return "has an invalid who"
  end
  if step.drop ~= nil and step.drop ~= true then
    return "has an invalid drop"
  end
  -- An object has no model: the icon of the item looted from it.
  if step.loot ~= nil and not isPositiveInt(step.loot) then
    return "has an invalid loot"
  end
  -- An object's 3D model (a file of the game).
  if step.model ~= nil and not isPositiveInt(step.model) then
    return "has an invalid model"
  end
  return nil
end

--- Validates a plan. Returns true, or nil and a reason.
function Plan.validate(plan)
  if type(plan) ~= "table" then
    return nil, "plan is not a table"
  end
  if not Plan.isPureData(plan) then
    return nil, "plan must contain only data (no functions or metatables)"
  end
  if plan.version ~= Plan.FORMAT_VERSION then
    return nil, "unsupported plan version"
  end
  if not isText(plan.id, Plan.MAX_ID) then
    return nil, "plan has no valid id"
  end
  if plan.title ~= nil and not isText(plan.title, Plan.MAX_TEXT) then
    return nil, "plan has an invalid title"
  end
  local steps = plan.steps
  if type(steps) ~= "table" or #steps == 0 or not isArray(steps) then
    return nil, "plan needs a list of steps"
  end
  if #steps > Plan.MAX_STEPS then
    return nil, "plan has too many steps"
  end
  local seen = {}
  for i, step in ipairs(steps) do
    local problem = checkStep(step)
    if problem then
      return nil, ("step %d %s"):format(i, problem)
    end
    if seen[step.id] then
      return nil, ("step %d repeats id %s"):format(i, step.id)
    end
    seen[step.id] = true
  end
  return true
end

--- Fresh progress record for a plan.
function Plan.newProgress(plan)
  return { planId = plan.id, done = {}, skipped = {}, history = {} }
end

--- Returns saved progress if it belongs to this plan, otherwise a fresh one.
function Plan.ensureProgress(plan, saved)
  if type(saved) == "table" and saved.planId == plan.id and type(saved.done) == "table"
    and type(saved.skipped) == "table" and type(saved.history) == "table" then
    return saved
  end
  return Plan.newProgress(plan)
end

local function distance(ax, ay, bx, by)
  local dx, dy = ax - bx, ay - by
  return math.sqrt(dx * dx + dy * dy)
end

--- True if the player stands within the step's radius. A position of 0,0
--- (inside instances) or an unknown position never counts as arrived.
function Plan.isAt(step, facts)
  local x, y = facts.x, facts.y
  if facts.mapID ~= step.mapID or type(x) ~= "number" or type(y) ~= "number" then
    return false
  end
  if x == 0 and y == 0 then
    return false
  end
  return distance(x, y, step.x, step.y) <= (step.radius or Plan.DEFAULT_RADIUS)
end

-- Steps whose state can be read from the game at any time. They count as done
-- even out of order. "goto" and "note" only count when they are current.
local function stateDone(step, facts)
  local q = step.questID
  local turnedIn = facts.turnedIn and facts.turnedIn(q)
  local entry = q and facts.questLog and facts.questLog[q]
  if step.type == "accept" then
    return entry ~= nil or turnedIn == true
  elseif step.type == "complete" then
    return (entry ~= nil and entry.complete == true) or turnedIn == true
  elseif step.type == "turnin" then
    return turnedIn == true
  elseif step.type == "level" then
    return type(facts.level) == "number" and facts.level >= step.level
  end
  return false
end

--- Works out which steps are done and which one is current.
--- Marks a reached "goto" step as done in progress (it stays done after you
--- walk away). Returns the current index (nil when the plan is finished),
--- a list of statuses ("done", "skipped", "pending") and whether progress
--- changed.
function Plan.evaluate(plan, progress, facts)
  local statuses, current, changed = {}, nil, false
  -- Soft steps (a guide's travel hints and notes) count as passed once any
  -- later step is done, or when the player already stands near the place
  -- of the next step with one ("Take the zeppelin" while at Grom'gol).
  local lastDone = 0
  for i, step in ipairs(plan.steps) do
    if not step.soft and (progress.done[step.id] or stateDone(step, facts)) then
      lastDone = i
    end
  end
  local function nearNext(i)
    for k = i + 1, #plan.steps do
      local s = plan.steps[k]
      if s.mapID then
        return facts.mapID == s.mapID and type(facts.x) == "number" and type(facts.y) == "number"
          and distance(facts.x, facts.y, s.x, s.y) <= Plan.NEAR
      end
    end
    return false
  end
  -- A quest you do not have (not in the log, never handed in) cannot be done
  -- or handed in: unless its pick-up step is still ahead, those steps are
  -- passed ("Turn in: Hemet Nesingwary" when it was never picked up).
  local acceptAhead = {}
  local function missing(step)
    local q = step.questID
    return (step.type == "complete" or step.type == "turnin") and q and not acceptAhead[q]
      and type(facts.questLog) == "table" and facts.questLog[q] == nil
      and type(facts.turnedIn) == "function" and facts.turnedIn(q) == false
  end
  for i, step in ipairs(plan.steps) do
    local status
    if progress.skipped[step.id] then
      status = "skipped"
    elseif progress.done[step.id] or stateDone(step, facts) or (step.soft and (i < lastDone or nearNext(i))) then
      status = "done"
    elseif missing(step) then
      status = "skipped"
    elseif current == nil and step.type == "goto" and Plan.isAt(step, facts) then
      progress.done[step.id] = true
      progress.history[#progress.history + 1] = step.id
      changed = true
      status = "done"
    else
      status = "pending"
      if current == nil then
        current = i
      end
      if step.type == "accept" and step.questID then
        acceptAhead[step.questID] = true
      end
    end
    statuses[i] = status
  end
  -- The player picked another step to do first: it leads while it is pending.
  if progress.chosen then
    local picked
    for i, step in ipairs(plan.steps) do
      if step.id == progress.chosen and statuses[i] == "pending" then
        picked = i
      end
    end
    if picked then
      current = picked
    else
      progress.chosen = nil
    end
  end
  return current, statuses, changed
end

--- The player chooses which pending step to do now (the others stay in the
--- plan). Returns the step, or nil if that step is not pending.
function Plan.choose(plan, progress, facts, index)
  local step = plan.steps[index]
  local _, statuses = Plan.evaluate(plan, progress, facts)
  if not step or statuses[index] ~= "pending" then
    return nil
  end
  progress.chosen = step.id
  return step
end

local function markCurrent(plan, progress, facts, field)
  local current = Plan.evaluate(plan, progress, facts)
  if not current then
    return nil
  end
  local step = plan.steps[current]
  progress[field][step.id] = true
  progress.history[#progress.history + 1] = step.id
  return step
end

--- Skips the current step. Returns the skipped step, or nil if finished.
function Plan.skip(plan, progress, facts)
  return markCurrent(plan, progress, facts, "skipped")
end

--- Marks the current step as done by hand (for "note" steps or when
--- detection fails). Returns the step, or nil if finished.
function Plan.markDone(plan, progress, facts)
  return markCurrent(plan, progress, facts, "done")
end

--- Undoes the last manual or arrival mark. Steps read from the game state
--- (a quest in the log, a level reached) stay done: undo cannot change them.
function Plan.undo(progress)
  local id = table.remove(progress.history)
  if not id then
    return nil
  end
  progress.done[id] = nil
  progress.skipped[id] = nil
  return id
end
