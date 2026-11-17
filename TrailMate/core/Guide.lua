-- Quest guides: TrailMate follows a guide (data/Guides.lua) step by step:
-- pick up these quests at this hub, do them there, hand them in, fly on.
-- Every quest step has the place of its quest giver or objectives, so the
-- arrow points everywhere. Pure Lua 5.1.
--
-- A guide becomes an ordinary TrailMate plan (core/Plan.lua): quest steps
-- tick off by themselves from the quest log; the travel hints and notes of
-- a guide are "soft": once something after them is done, they count as
-- passed, so the player never has to click through old hints.

local _, ns = ...

local Guide = {}
ns.Guide = Guide

-- Race names in guides (Guidelime) and in the game (UnitRace) differ.
local RACE_ALIASES = { UNDEAD = "SCOURGE", NIGHTELF = "NIGHTELF", NIGHT_ELF = "NIGHTELF" }

local function fits(only, who)
  if not only then
    return true
  end
  for _, w in ipairs(only) do
    local word = RACE_ALIASES[w] or w
    if word == who.class or word == who.race or w == who.race then
      return true
    end
  end
  return false
end
Guide.fits = fits

--- The guides for a faction (and class or race), in the data's order.
function Guide.list(guides, who)
  local out = {}
  for _, g in ipairs(guides or {}) do
    if g.faction == who.faction and fits(g.only, who) then
      out[#out + 1] = g
    end
  end
  return out
end

--- The guide to follow: the one chosen by name if it still exists; else
--- the first guide for the level (from one level below its end) that is not
--- finished; else the last one starting at or below the level.
--- finished(guide) (optional) says whether its quests are all handed in.
function Guide.pick(list, level, chosen, finished)
  for _, g in ipairs(list) do
    if chosen and g.name == chosen then
      return g
    end
  end
  for _, g in ipairs(list) do
    if g.min <= level and g.max >= level - 1 and not (finished and finished(g)) then
      return g
    end
  end
  local pick
  for _, g in ipairs(list) do
    if g.min <= level and (not pick or g.min >= pick.min) then
      pick = g
    end
  end
  return pick or list[1]
end

--- True when every quest the guide hands in (not optional, for this
--- character) is handed in. isDone(questID).
function Guide.finished(guide, who, isDone)
  local any = false
  for _, s in ipairs(guide.steps) do
    if s.t == "turnin" and not s.opt and fits(s.only, who) then
      any = true
      if not isDone(s.q) then
        return false
      end
    end
  end
  return any
end

--- The guide after this one in the list, or nil.
function Guide.after(list, guide)
  for i, g in ipairs(list) do
    if g == guide then
      return list[i + 1]
    end
  end
  return nil
end

local function slug(text)
  return (text:lower():gsub("[^%w]+", "-"):gsub("^%-+", ""):gsub("%-+$", ""))
end

--- A TrailMate plan from a guide. ctx = { who, L, title(questID) }: title
--- gives the game's (localized) quest name, falling back to the guide's.
function Guide.toPlan(guide, ctx)
  local L, who = ctx.L, ctx.who
  local steps = {}
  local max = ns.Plan.MAX_TEXT
  local function cut(text)
    return #text > max and text:sub(1, max - 3) .. "..." or text
  end
  for i, s in ipairs(guide.steps) do
    if fits(s.only, who) then
      local step = { id = "g" .. i }
      local name = s.q and ((ctx.title and ctx.title(s.q)) or s.name or L["Quest %d"]:format(s.q))
      if s.t == "accept" then
        step.type, step.questID, step.text = "accept", s.q, L["Pick up: "] .. name
        step.why = s.npc and L["From %s"]:format(s.npc) or nil
      elseif s.t == "turnin" then
        step.type, step.questID, step.text = "turnin", s.q, L["Turn in: "] .. name
        step.why = s.npc and L["To %s"]:format(s.npc) or nil
      elseif s.t == "complete" then
        step.type, step.questID, step.text = "complete", s.q, L["Do: "] .. name
      elseif s.t == "goto" then
        step.type, step.text, step.soft = "goto", s.text, true
      elseif s.t == "level" then
        step.type, step.level, step.text = "level", s.level, s.text
      else
        step.type, step.text, step.soft = "note", s.text, true
      end
      if s.opt then
        step.why = L["Optional: elite or group quest"] .. (step.why and (" - " .. step.why) or "")
      end
      if s.m and s.x and s.y then
        step.mapID, step.x, step.y = s.m, s.x, s.y
      end
      step.text = cut(step.text or "")
      if step.why then
        step.why = cut(step.why)
      end
      steps[#steps + 1] = step
    end
  end
  return {
    version = 1,
    id = "guide-" .. slug(guide.faction .. "-" .. guide.name),
    title = guide.name,
    steps = steps,
  }
end

--- True if a plan was made from a guide.
function Guide.isGuide(plan)
  return type(plan) == "table" and type(plan.id) == "string" and plan.id:find("^guide%-") ~= nil
end
