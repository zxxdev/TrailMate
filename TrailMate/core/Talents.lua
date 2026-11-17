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

-- The hunter templates use the talent names of WoW Forever's own trees, as
-- the game reported them on 2026-11-17 (they differ from classic: Deadly
-- Aspects, Summon Hawk, Lethal Attacks...). The order is a suggestion for
-- levelling, not an official guide.
Talents.TEMPLATES = {
  HUNTER = {
    -- A build by level across the three trees (31/16/4): one entry per
    -- talent with the ranks to take, in the order they are taken.
    {
      id = "hunter-levelling", tree = 1, difficulty = "easy", name = "Levelling build",
      note = "Beast Mastery up to Bestial Wrath, then Marksmanship up to Trueshot Aura, then Survival.",
      build = {
        { "Deadly Aspects", 5 }, { "Focused Fire", 2 }, { "Endurance Training", 3 }, { "Unleashed Fury", 5 },
        { "Summon Hawk", 1 }, { "Ferocity", 5 }, { "Bestial Swiftness", 1 }, { "Intimidation", 1 },
        { "Bestial Discipline", 2 }, { "Frenzy", 5 }, { "Bestial Wrath", 1 },
        { "Lethal Attacks", 5 }, { "Improved Stings", 3 }, { "Careful Aim", 5 }, { "Rapid Killing", 2 },
        { "Trueshot Aura", 1 },
        { "Improved Tracking", 4 },
      },
    },
    {
      id = "hunter-bm", tree = 1, difficulty = "easy",
      note = "Easiest to level: a strong pet takes the hits, little downtime.",
      priority = {
        "Deadly Aspects", "Focused Fire", "Unleashed Fury", "Ferocity", "Bestial Swiftness", "Intimidation",
        "Bestial Discipline", "Frenzy", "Bestial Wrath", "Endurance Training", "Spirit Bond", "Summon Hawk",
        "Improved Aspect of the Monkey", "Pathfinding", "Improved Mend Pet", "Improved Revive Pet",
      },
    },
    {
      id = "hunter-mm", tree = 2, difficulty = "normal",
      note = "More damage from you, a weaker pet. Good for groups.",
      priority = {
        "Lethal Attacks", "Careful Aim", "Efficiency", "Mortal Shots", "Improved Arcane Shot", "Rapid Killing",
        "Trueshot Aura", "Barrage", "Ranged Weapon Specialization", "Sniper Shot", "Improved Concussive Shot",
        "Hawk Eye", "Improved Stings", "Rapid Recuperation", "Scatter Shot", "Improved Serpent Sting", "Lone Wolf",
      },
    },
    {
      id = "hunter-sv", tree = 3, difficulty = "hard",
      note = "Traps and survival tricks; slower solo, needs more care.",
      priority = {
        "Savage Strikes", "Survivalist", "Deflection", "Surefooted", "Predator's Edge", "Expose Prey",
        "Lightning Reflexes", "Lacerating Strikes", "Survivalist's Discipline", "Deterrence", "Survival Tactics",
        "Improved Tracking", "Entrapment", "Clever Traps", "Resourcefulness", "Counterattack", "Strider Kick",
        "Improved Wing Clip",
      },
    },
  },
}

-- Tree names left to right, for clients that do not give the
-- specialisation names (WoW Forever does not).
Talents.TREE_NAMES = {
  DRUID = { "Balance", "Feral Combat", "Restoration" },
  HUNTER = { "Beast Mastery", "Marksmanship", "Survival" },
  MAGE = { "Arcane", "Fire", "Frost" },
  PALADIN = { "Holy", "Protection", "Retribution" },
  PRIEST = { "Discipline", "Holy", "Shadow" },
  ROGUE = { "Assassination", "Combat", "Subtlety" },
  SHAMAN = { "Elemental", "Enhancement", "Restoration" },
  WARLOCK = { "Affliction", "Demonology", "Destruction" },
  WARRIOR = { "Arms", "Fury", "Protection" },
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
      copy.label = t.name or tab.name
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

-- The names a template uses: its order of preference, or its build.
local function namesOf(template)
  if template.build then
    local out = {}
    for _, entry in ipairs(template.build) do
      out[#out + 1] = entry[1]
    end
    return out
  end
  return template.priority or {}
end

--- How many of the template's names exist in the player's trees.
function Talents.found(tabs, template)
  local names = {}
  for i, tab in ipairs(tabs) do
    if template.build or i == template.tree then
      for _, t in ipairs(tab.talents) do
        names[t.name] = true
      end
    end
  end
  local n, list = 0, namesOf(template)
  for _, name in ipairs(list) do
    if names[name] then
      n = n + 1
    end
  end
  return n, #list
end

local function pos(tier, column)
  return tier .. ":" .. column
end

-- A build: take each entry's ranks in order, across trees. An entry whose
-- row or prerequisite is not open yet waits, and the next one is taken.
-- When the build is done, the main tree is filled row by row.
local function planBuild(tabs, template, limit)
  local ranks, spent, byName, byPos = {}, {}, {}, {}
  for i, tab in ipairs(tabs) do
    spent[i], byPos[i] = 0, {}
    for _, t in ipairs(tab.talents) do
      ranks[t] = t.rank or 0
      spent[i] = spent[i] + ranks[t]
      byName[t.name] = byName[t.name] or { talent = t, tree = i }
      byPos[i][pos(t.tier, t.column)] = t
    end
  end
  local function open(t, tree)
    if ranks[t] >= t.maxRank or spent[tree] < (t.tier - 1) * Talents.PER_ROW then
      return false
    end
    local p = t.prereq and byPos[tree][pos(t.prereq.tier, t.prereq.column)]
    return not p or ranks[p] >= p.maxRank
  end
  -- One entry per point: the talent and the rank it reaches.
  local steps, seen = {}, {}
  for _, entry in ipairs(template.build) do
    for _ = 1, entry[2] do
      seen[entry[1]] = (seen[entry[1]] or 0) + 1
      steps[#steps + 1] = { name = entry[1], rank = seen[entry[1]] }
    end
  end
  local picks = {}
  for _ = 1, limit do
    local pick
    for _, s in ipairs(steps) do
      local found = byName[s.name]
      if found and ranks[found.talent] < s.rank and open(found.talent, found.tree) then
        pick = found
        break
      end
    end
    if not pick then
      local main = tabs[template.tree]
      local sorted = {}
      for _, t in ipairs(main and main.talents or {}) do
        sorted[#sorted + 1] = t
      end
      table.sort(sorted, function(a, b)
        if a.tier ~= b.tier then
          return a.tier < b.tier
        end
        return a.column < b.column
      end)
      for _, t in ipairs(sorted) do
        if open(t, template.tree) then
          pick = { talent = t, tree = template.tree }
          break
        end
      end
    end
    if not pick then
      break
    end
    ranks[pick.talent] = ranks[pick.talent] + 1
    spent[pick.tree] = spent[pick.tree] + 1
    picks[#picks + 1] = { talent = pick.talent, rank = ranks[pick.talent], tree = pick.tree }
  end
  return picks
end

--- The next `limit` points in order, as { talent, rank, tree } (rank after
--- the point). The trees are not changed.
function Talents.plan(tabs, template, limit)
  if template.build then
    return planBuild(tabs, template, limit)
  end
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
    picks[#picks + 1] = { talent = pick, rank = ranks[pick], tree = template.tree }
  end
  return picks
end

--- What a template does from level 10, for the preview: the points by
--- level (grouped), the points per tree, and the talents each tree ends
--- with. maxPoints: the points to show (51 at level 60).
function Talents.preview(tabs, template, maxPoints)
  -- The same trees, empty.
  local empty = {}
  for i, tab in ipairs(tabs) do
    local talents = {}
    for _, t in ipairs(tab.talents) do
      local copy = {}
      for k, v in pairs(t) do
        copy[k] = v
      end
      copy.rank = 0
      talents[#talents + 1] = copy
    end
    empty[i] = { name = tab.name, talents = talents }
  end
  local picks = Talents.plan(empty, template, maxPoints)
  local levels, points, final = {}, {}, {}
  for i, p in ipairs(picks) do
    local level = 9 + i
    local last = levels[#levels]
    if last and last.talent == p.talent then
      last.to, last.rankTo = level, p.rank
    else
      levels[#levels + 1] = { from = level, to = level, talent = p.talent, tree = p.tree, rankFrom = p.rank,
        rankTo = p.rank }
    end
    points[p.tree] = (points[p.tree] or 0) + 1
    final[p.talent] = p.rank
  end
  local trees = {}
  for i, tab in ipairs(empty) do
    local taken = {}
    for _, t in ipairs(tab.talents) do
      if final[t] then
        taken[#taken + 1] = { talent = t, rank = final[t] }
      end
    end
    table.sort(taken, function(a, b)
      if a.talent.tier ~= b.talent.tier then
        return a.talent.tier < b.talent.tier
      end
      return a.talent.column < b.talent.column
    end)
    trees[i] = { name = tab.name, points = points[i] or 0, taken = taken }
  end
  local split = {}
  for i = 1, #empty do
    split[i] = tostring(points[i] or 0)
  end
  return { levels = levels, trees = trees, split = table.concat(split, "/") }
end

-- Modern clients (WoW Forever) -------------------------------------------------
--
-- Forever draws classic-looking trees on the modern talent system: one list
-- of nodes with a position (posX, posY) and arrows between them, not three
-- numbered trees. These helpers turn the nodes back into trees, rows and
-- columns, so the rest of this file works the same.
--
-- nodes = { { nodeID, name, icon, posX, posY, rank, maxRank, subTreeID,
--   targets = { nodeID, ... } } }

local function distinct(values)
  local seen, out = {}, {}
  for _, v in ipairs(values) do
    if not seen[v] then
      seen[v] = true
      out[#out + 1] = v
    end
  end
  table.sort(out)
  return out
end

-- The grid step: the most common gap between neighbouring values (the
-- smallest one on a tie), or 1. Not simply the smallest gap: Forever has two
-- nodes of one row 10 units apart where rows are 600 apart.
local function step(sorted)
  local counts, best, bestCount = {}, nil, 0
  for i = 2, #sorted do
    local d = math.floor(sorted[i] - sorted[i - 1] + 0.5)
    if d > 0 then
      counts[d] = (counts[d] or 0) + 1
      if counts[d] > bestCount or (counts[d] == bestCount and d < best) then
        best, bestCount = d, counts[d]
      end
    end
  end
  return best or 1
end

local function round(v)
  return math.floor(v + 0.5)
end

-- Values far from every other one (more than ten grid steps): nodes the
-- game keeps outside the drawn tree (Forever has two), not real talents.
local function strays(sorted, gridStep)
  local out = {}
  if #sorted < 3 then
    return out
  end
  for i, v in ipairs(sorted) do
    local left = i > 1 and v - sorted[i - 1] or math.huge
    local right = i < #sorted and sorted[i + 1] - v or math.huge
    if math.min(left, right) > 10 * gridStep then
      out[v] = true
    end
  end
  return out
end

-- Which tree each grid column belongs to: by sub-tree when the game says,
-- else split where the columns have a wide gap, else in three equal bands.
local function treeOfColumn(columns, wanted)
  local groups, current = {}, 1
  -- Knowing how many trees there are (the specialisations), cut at the
  -- widest gaps: a tree may have an empty column, the gap between trees is wider.
  if wanted and wanted >= 2 and #columns >= wanted then
    local gaps = {}
    for i = 2, #columns do
      gaps[#gaps + 1] = { at = i, size = columns[i] - columns[i - 1] }
    end
    table.sort(gaps, function(a, b)
      if a.size ~= b.size then
        return a.size > b.size
      end
      return a.at < b.at
    end)
    local cut = {}
    for i = 1, wanted - 1 do
      cut[gaps[i].at] = true
    end
    for i, c in ipairs(columns) do
      if cut[i] then
        current = current + 1
      end
      groups[c] = current
    end
    return groups, current
  end
  for i, c in ipairs(columns) do
    if i > 1 and c - columns[i - 1] > 1 then
      current = current + 1
    end
    groups[c] = current
  end
  if current >= 2 and current <= 4 then
    return groups, current
  end
  local count = columns[#columns] - columns[1] + 1
  if count < 9 then
    for _, c in ipairs(columns) do
      groups[c] = 1
    end
    return groups, 1
  end
  local band = math.ceil(count / 3)
  for _, c in ipairs(columns) do
    groups[c] = math.floor((c - columns[1]) / band) + 1
  end
  return groups, 3
end

--- Trees (as Talents.plan wants them) from the modern node list.
--- names: the trees' names left to right (the class's specialisations).
function Talents.fromNodes(all, names)
  -- Leave out the stray nodes far away from the drawn trees.
  local px, py = {}, {}
  for _, n in ipairs(all) do
    px[#px + 1], py[#py + 1] = n.posX, n.posY
  end
  px, py = distinct(px), distinct(py)
  local farX, farY = strays(px, step(px)), strays(py, step(py))
  local nodes = {}
  for _, n in ipairs(all) do
    if not (farX[n.posX] or farY[n.posY]) then
      nodes[#nodes + 1] = n
    end
  end
  if #nodes == 0 then
    return {}
  end
  local xs, ys, subs = {}, {}, {}
  for _, n in ipairs(nodes) do
    xs[#xs + 1], ys[#ys + 1] = n.posX, n.posY
    if n.subTreeID and n.subTreeID ~= 0 then
      subs[#subs + 1] = n.subTreeID
    end
  end
  xs, ys, subs = distinct(xs), distinct(ys), distinct(subs)
  local xStep, yStep = step(xs), step(ys)
  local function col(n)
    return round((n.posX - xs[1]) / xStep)
  end

  local treeOf = {}
  local count
  if #subs >= 2 then
    -- Sub-trees, ordered left to right by their first column.
    local left = {}
    for _, n in ipairs(nodes) do
      local s = n.subTreeID
      if s and s ~= 0 and (not left[s] or col(n) < left[s]) then
        left[s] = col(n)
      end
    end
    table.sort(subs, function(a, b)
      return left[a] < left[b]
    end)
    local index = {}
    for i, s in ipairs(subs) do
      index[s] = i
    end
    for _, n in ipairs(nodes) do
      treeOf[n] = index[n.subTreeID] or 1
    end
    count = #subs
  else
    local columns = {}
    for _, n in ipairs(nodes) do
      columns[#columns + 1] = col(n)
    end
    local groups
    groups, count = treeOfColumn(distinct(columns), names and #names or nil)
    for _, n in ipairs(nodes) do
      treeOf[n] = groups[col(n)]
    end
  end

  local tabs, firstCol, byID = {}, {}, {}
  for i = 1, count do
    tabs[i] = { name = names and names[i] or ("Tree " .. i), talents = {} }
  end
  for _, n in ipairs(nodes) do
    local t = treeOf[n]
    firstCol[t] = math.min(firstCol[t] or math.huge, col(n))
  end
  for _, n in ipairs(nodes) do
    local t = treeOf[n]
    local talent = {
      nodeID = n.nodeID, name = n.name, icon = n.icon, rank = n.rank or 0, maxRank = n.maxRank,
      tier = round((n.posY - ys[1]) / yStep) + 1, column = col(n) - firstCol[t] + 1,
    }
    byID[n.nodeID] = talent
    local list = tabs[t].talents
    list[#list + 1] = talent
  end
  -- An arrow from A to B means B needs A maxed.
  for _, n in ipairs(nodes) do
    for _, target in ipairs(n.targets or {}) do
      local b, a = byID[target], byID[n.nodeID]
      if b and a then
        b.prereq = { tier = a.tier, column = a.column }
      end
    end
  end
  return tabs
end

--- Joins points in a row on the same talent: { talent, from, to }.
function Talents.group(picks)
  local out = {}
  for _, p in ipairs(picks) do
    local last = out[#out]
    if last and last.talent == p.talent then
      last.to = p.rank
    else
      out[#out + 1] = { talent = p.talent, from = p.rank, to = p.rank, tree = p.tree }
    end
  end
  return out
end
