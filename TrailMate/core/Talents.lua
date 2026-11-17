-- Talent advice: which talent to take next for a chosen leveling template.
-- Pure Lua 5.1.
--
-- The tree comes from the game at run time (names, rows, columns, ranks,
-- prerequisites), so the advice always fits the real tree of WoW Forever.
-- A template is only an order of preference by talent name: names the tree
-- does not have are skipped, and when none is left the advice falls back to
-- the lowest open row. The templates are a guide written from the classic
-- trees, not checked in WoW Forever: the panel says how many names it found.
--
-- tabs = { { name, icon, talents = { { index, name, icon, tier, column, rank,
--   maxRank, prereq = { tier, column } | nil } } } }

local _, ns = ...

local Talents = {}
ns.Talents = Talents

-- Points needed in a tree to open each row (classic rule: 5 per row).
Talents.PER_ROW = 5

Talents.TEMPLATES = {
  HUNTER = {
    {
      id = "hunter-bm", tree = 1, difficulty = "easy",
      note = "Easiest to level: a strong pet takes the hits, little downtime.",
      priority = {
        "Improved Aspect of the Hawk", "Endurance Training", "Focused Fire", "Unleashed Fury", "Ferocity",
        "Thick Hide", "Bestial Discipline", "Intimidation", "Frenzy", "Spirit Bond", "Ferocious Inspiration",
        "Bestial Wrath", "Serpent's Swiftness", "Catlike Reflexes", "Invigoration", "The Beast Within",
        "Kindred Spirits", "Cobra Strikes", "Longevity", "Beast Mastery", "Animal Handler",
        "Improved Mend Pet", "Pathfinding", "Aspect Mastery", "Bestial Swiftness", "Improved Revive Pet",
      },
    },
    {
      id = "hunter-mm", tree = 2, difficulty = "normal",
      note = "More damage from you, a weaker pet. Good for groups.",
      priority = {
        "Lethal Shots", "Improved Concussive Shot", "Focused Aim", "Careful Aim", "Mortal Shots",
        "Improved Hunter's Mark", "Aimed Shot", "Go for the Throat", "Rapid Killing", "Improved Arcane Shot",
        "Barrage", "Improved Stings", "Trueshot Aura", "Ranged Weapon Specialization", "Piercing Shots",
        "Improved Barrage", "Master Marksman", "Readiness", "Wild Quiver", "Silencing Shot",
        "Improved Steady Shot", "Marked for Death", "Chimera Shot", "Efficiency", "Hawk Eye",
        "Improved Serpent Sting", "Scatter Shot", "Improved Scorpid Sting",
      },
    },
    {
      id = "hunter-sv", tree = 3, difficulty = "hard",
      note = "Traps and survival tricks; slower solo, needs more care.",
      priority = {
        "Improved Tracking", "Savage Strikes", "Surefooted", "Entrapment", "Trap Mastery", "Survival Instincts",
        "Survivalist", "Deterrence", "T.N.T.", "Lock and Load", "Hunter vs. Wild", "Killer Instinct",
        "Lightning Reflexes", "Resourcefulness", "Expose Weakness", "Wyvern Sting", "Thrill of the Hunt",
        "Master Tactician", "Noxious Stings", "Sniper Training", "Hunting Party", "Explosive Shot",
        "Monster Slaying", "Humanoid Slaying", "Improved Wing Clip", "Counterattack", "Deflection",
      },
    },
  },
}

--- The templates for this class and tree, plus a plain "fill this tree"
--- one for every tree no template covers. Each gets a `label` from the
--- tree's own name in the game.
function Talents.templates(class, tabs)
  local list, covered = {}, {}
  for _, t in ipairs(Talents.TEMPLATES[class] or {}) do
    local tab = tabs[t.tree]
    if tab then
      covered[t.tree] = true
      local copy = {}
      for k, v in pairs(t) do
        copy[k] = v
      end
      copy.label = tab.name
      list[#list + 1] = copy
    end
  end
  for i, tab in ipairs(tabs) do
    if not covered[i] then
      list[#list + 1] = { id = "auto-" .. i, tree = i, label = tab.name, priority = {}, auto = true }
    end
  end
  return list
end

local function spentIn(tab)
  local n = 0
  for _, t in ipairs(tab.talents) do
    n = n + (t.rank or 0)
  end
  return n
end

--- The template to show when the player has not chosen: the saved one if
--- it still exists, else the one for the tree with the most points.
function Talents.choose(list, tabs, savedId)
  local best, bestSpent
  for _, t in ipairs(list) do
    if t.id == savedId then
      return t
    end
    local spent = spentIn(tabs[t.tree])
    if not best or spent > bestSpent then
      best, bestSpent = t, spent
    end
  end
  return best
end

--- How many of the template's names exist in the player's tree.
function Talents.found(tabs, template)
  local names = {}
  for _, t in ipairs(tabs[template.tree].talents) do
    names[t.name] = true
  end
  local n = 0
  for _, name in ipairs(template.priority) do
    if names[name] then
      n = n + 1
    end
  end
  return n, #template.priority
end

local function pos(tier, column)
  return tier .. ":" .. column
end

--- The next `limit` points in order, as { talent, rank } (rank after the
--- point). The tree is not changed.
function Talents.plan(tabs, template, limit)
  local tab = tabs[template.tree]
  if not tab then
    return {}
  end
  local ranks, byPos, byName, sorted = {}, {}, {}, {}
  local spent = 0
  for _, t in ipairs(tab.talents) do
    ranks[t] = t.rank or 0
    spent = spent + ranks[t]
    byPos[pos(t.tier, t.column)] = t
    byName[t.name] = byName[t.name] or t
    sorted[#sorted + 1] = t
  end
  table.sort(sorted, function(a, b)
    if a.tier ~= b.tier then
      return a.tier < b.tier
    end
    return a.column < b.column
  end)

  local function open(t)
    if ranks[t] >= t.maxRank or spent < (t.tier - 1) * Talents.PER_ROW then
      return false
    end
    local p = t.prereq and byPos[pos(t.prereq.tier, t.prereq.column)]
    return not p or ranks[p] >= p.maxRank
  end

  local picks = {}
  for _ = 1, limit do
    local pick
    for _, name in ipairs(template.priority) do
      local t = byName[name]
      if t and open(t) then
        pick = t
        break
      end
    end
    if not pick then
      for _, t in ipairs(sorted) do
        if open(t) then
          pick = t
          break
        end
      end
    end
    if not pick then
      break
    end
    ranks[pick] = ranks[pick] + 1
    spent = spent + 1
    picks[#picks + 1] = { talent = pick, rank = ranks[pick] }
  end
  return picks
end

--- Joins points in a row on the same talent: { talent, from, to }.
function Talents.group(picks)
  local out = {}
  for _, p in ipairs(picks) do
    local last = out[#out]
    if last and last.talent == p.talent then
      last.to = p.rank
    else
      out[#out + 1] = { talent = p.talent, from = p.rank, to = p.rank }
    end
  end
  return out
end
