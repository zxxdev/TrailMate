-- Who a quest's steps are about, from the table of every quest
-- (data/QuestInfo.lua): who gives it, the creature or object of its
-- objectives, who takes it back. The guides, dungeons and class quests carry
-- their own; this fills the rest (a route made from the quest log, a quest
-- the player marks), so the magnifier always has someone to show when the
-- database knows. Plain Lua, no game API.

local _, ns = ...

local QuestInfo = {}
ns.QuestInfo = QuestInfo

--- Who a step about questID is about: kind is "accept", "complete" or
--- "turnin". { type, creature, who, model, drop, loot } or nil.
function QuestInfo.about(info, questID, kind)
  local q = type(info) == "table" and info[questID]
  if type(q) ~= "table" then
    return nil
  end
  if kind == "accept" and q.an then
    return { type = kind, creature = q.ac, who = q.an, model = q.am }
  elseif kind == "complete" and q.dn then
    return { type = kind, creature = q.dc, who = q.dn, model = q.dm, drop = q.dd, loot = q.dl }
  elseif kind == "turnin" and q.tn then
    return { type = kind, creature = q.tc, who = q.tn, model = q.tm }
  end
  return nil
end

--- Gives the steps of a plan that have nobody to show (no who) the one the
--- table knows. Steps that already have someone keep theirs.
function QuestInfo.fill(steps, info)
  for _, step in ipairs(steps or {}) do
    if step.questID and step.who == nil then
      local a = QuestInfo.about(info, step.questID, step.type)
      if a then
        step.creature, step.who, step.model, step.drop, step.loot = a.creature, a.who, a.model, a.drop, a.loot
      end
    end
  end
  return steps
end
