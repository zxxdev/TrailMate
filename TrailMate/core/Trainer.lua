-- Class trainer advisor: each service gets "learn", "skip" or "later", with
-- a reason. It only advises: the player clicks "Train" or not. Pure Lua 5.1.
--
-- Service: { index, name, spellID (may be nil), cost (copper),
--            status = "available" | "unavailable" | "used", reqLevel }
-- Context: { class, level, money, prefs = { skipTracking, reserve } }
-- reserve is copper the advisor never spends (for repairs, a mount, etc.).

local _, ns = ...

local Trainer = {}
ns.Trainer = Trainer

-- Per-class rules. Spell ids are the classic ones and are not yet confirmed
-- in-game on this client: the name patterns are the fallback (enUS, esES).
Trainer.RULES = {
  HUNTER = {
    tracking = {
      ids = {
        [1494] = true, -- Track Beasts
        [19878] = true, -- Track Demons
        [19879] = true, -- Track Dragonkin
        [19880] = true, -- Track Elementals
        [19882] = true, -- Track Giants
        [19883] = true, -- Track Humanoids
        [19884] = true, -- Track Undead
        [19885] = true, -- Track Hidden
      },
      patterns = { "^Track ", "^Rastrear " },
    },
  },
}

local function isTracking(rules, service)
  local tracking = rules and rules.tracking
  if not tracking then
    return false
  end
  if service.spellID and tracking.ids[service.spellID] then
    return true
  end
  if type(service.name) == "string" then
    for _, pattern in ipairs(tracking.patterns) do
      if service.name:find(pattern) then
        return true
      end
    end
  end
  return false
end

--- Key used to ignore a spell in all its ranks: its name without the rank.
function Trainer.key(service)
  return service.baseName or service.name
end

--- Returns a list of { index, name, key, cost, verdict, reason } for every
--- service not already known, and the total cost of the "learn" ones.
--- prefs.ignored[key] = true makes a spell "skip" for good, in every rank.
function Trainer.advise(services, ctx, L)
  local prefs = ctx.prefs or {}
  local ignored = prefs.ignored or {}
  local rules = Trainer.RULES[ctx.class]
  local budget = math.max(0, (ctx.money or 0) - (prefs.reserve or 0))
  local results, spend = {}, 0

  for _, s in ipairs(services) do
    if s.status ~= "used" then
      local verdict, reason
      local cost = s.cost or 0
      if ignored[Trainer.key(s)] then
        verdict, reason = "skip", L["You chose to ignore it"]
      elseif s.status == "unavailable" then
        verdict = "later"
        if s.reqLevel and ctx.level and s.reqLevel > ctx.level then
          reason = L["Needs level %d"]:format(s.reqLevel)
        else
          reason = L["Not available yet"]
        end
      elseif prefs.skipTracking and isTracking(rules, s) then
        verdict, reason = "skip", L["Tracking: you chose to skip it"]
      elseif spend + cost > budget then
        verdict, reason = "later", L["Not enough gold after your reserve"]
      else
        verdict, reason = "learn", L["Useful now and affordable"]
        spend = spend + cost
      end
      results[#results + 1] = {
        index = s.index, name = s.name, key = Trainer.key(s), cost = cost, verdict = verdict, reason = reason,
      }
    end
  end
  return results, spend
end

--- Remembers what a trainer offered, so a level-up can say what is new
--- without a data pack. memory[name] = { key, reqLevel, cost }. Spells the
--- trainer shows as learned are forgotten.
function Trainer.remember(memory, services)
  for _, s in ipairs(services) do
    if s.status == "used" then
      memory[s.name] = nil
    elseif type(s.reqLevel) == "number" then
      memory[s.name] = { key = Trainer.key(s), reqLevel = s.reqLevel, cost = s.cost or 0 }
    end
  end
end

--- Spells that unlock exactly at this level and are not ignored, sorted.
--- Only the new ones: the advisor never nags about what you left behind.
function Trainer.newAtLevel(memory, level, ignored)
  local names = {}
  for name, entry in pairs(memory) do
    if entry.reqLevel == level and not (ignored and ignored[entry.key]) then
      names[#names + 1] = name
    end
  end
  table.sort(names)
  return names
end
