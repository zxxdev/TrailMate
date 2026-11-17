local helper = require("spec.helper")

describe("Talents", function()
  local Talents

  -- A small hunter-like tree: two talents in row 1, one in row 2, and a
  -- row-3 talent that needs the row-2 one maxed.
  local function tree(ranks)
    ranks = ranks or {}
    local function t(index, name, tier, column, maxRank, prereq)
      return { index = index, name = name, tier = tier, column = column, rank = ranks[name] or 0,
        maxRank = maxRank, prereq = prereq }
    end
    return {
      { name = "Beast Mastery", talents = {
        t(1, "Deadly Aspects", 1, 2, 5),
        t(2, "Endurance Training", 1, 3, 5),
        t(3, "Unleashed Fury", 2, 2, 5),
        t(4, "Intimidation", 3, 2, 1, { tier = 2, column = 2 }),
        t(5, "Forever Only Talent", 1, 1, 3),
      } },
      { name = "Marksmanship", talents = { t(1, "Lethal Shots", 1, 2, 5) } },
      { name = "Survival", talents = { t(1, "Savage Strikes", 1, 1, 2) } },
    }
  end

  before_each(function()
    Talents = helper.load().Talents
  end)

  it("offers the class templates named after the real trees", function()
    local list = Talents.templates("HUNTER", tree())
    assert.equals(4, #list)
    assert.equals("Levelling build", list[1].label)
    assert.equals("Beast Mastery", list[2].label)
    assert.equals("easy", list[1].difficulty)
    -- Another class gets a plain "fill this tree" choice per tree.
    local other = Talents.templates("PRIEST", tree())
    assert.equals(3, #other)
    assert.is_true(other[2].auto)
  end)

  it("follows the template order and opens rows every five points", function()
    local tabs = tree()
    local bm = Talents.templates("HUNTER", tabs)[2]
    local picks = Talents.plan(tabs, bm, 11)
    -- Deadly Aspects 1-5, then Unleashed Fury in row 2 (open after 5 points),
    -- then Intimidation in row 3 once Unleashed Fury is maxed.
    assert.equals("Deadly Aspects", picks[1].talent.name)
    assert.equals(5, picks[5].rank)
    assert.equals("Unleashed Fury", picks[6].talent.name)
    assert.equals("Intimidation", picks[11].talent.name)
    local grouped = Talents.group(picks)
    assert.same({ 1, 5 }, { grouped[1].from, grouped[1].to })
    assert.equals("Intimidation", grouped[3].talent.name)
  end)

  it("never puts a point in a row that is not open yet", function()
    local tabs = tree()
    -- A template that wants the row-2 talent first.
    local eager = { tree = 1, priority = { "Unleashed Fury" } }
    local picks = Talents.plan(tabs, eager, 6)
    for i = 1, 5 do
      assert.equals(1, picks[i].talent.tier)
    end
    assert.equals("Unleashed Fury", picks[6].talent.name)
  end)

  it("waits for a prerequisite to be maxed", function()
    local tabs = tree({ ["Deadly Aspects"] = 5, ["Endurance Training"] = 5, ["Unleashed Fury"] = 4 })
    local bm = Talents.templates("HUNTER", tabs)[2]
    local picks = Talents.plan(tabs, bm, 2)
    assert.equals("Unleashed Fury", picks[1].talent.name)
    assert.equals("Intimidation", picks[2].talent.name)
  end)

  it("falls back to the lowest open row when the template has nothing left", function()
    local tabs = tree()
    local auto = { tree = 1, priority = {} }
    local picks = Talents.plan(tabs, auto, 1)
    assert.equals("Forever Only Talent", picks[1].talent.name) -- row 1, column 1
    -- A full tree gives no advice instead of looping.
    local full = { { name = "x", talents = { { name = "a", tier = 1, column = 1, rank = 1, maxRank = 1 } } } }
    assert.same({}, Talents.plan(full, auto, 3))
  end)

  describe("modern node lists (WoW Forever)", function()
    -- Three trees of four columns side by side, 100 units apart, with a
    -- one-column gap between trees; rows 150 units apart.
    local function node(id, name, treeIndex, column, row, rank, targets)
      local x = (treeIndex - 1) * 500 + (column - 1) * 100 + 1000
      return { nodeID = id, name = name, posX = x, posY = 2000 + (row - 1) * 150, rank = rank or 0, maxRank = 5,
        targets = targets }
    end
    local nodes = {
      node(1, "Deadly Aspects", 1, 2, 1, 0, { 3 }),
      node(2, "Endurance Training", 1, 3, 1),
      node(3, "Focused Fire", 1, 2, 3), -- row 2 is empty in this tree
      node(4, "Lethal Shots", 2, 2, 1, 2),
      node(5, "Improved Tracking", 3, 1, 1),
      node(6, "Savage Strikes", 3, 4, 1),
      node(7, "Entrapment", 3, 2, 2), -- row 2 exists in another tree
    }

    it("splits them into trees, rows and columns", function()
      local tabs = Talents.fromNodes(nodes, { "Beast Mastery", "Marksmanship", "Survival" })
      assert.equals(3, #tabs)
      assert.equals("Beast Mastery", tabs[1].name)
      local focused = tabs[1].talents[3]
      assert.equals("Focused Fire", focused.name)
      assert.same({ 3, 1 }, { focused.tier, focused.column }) -- the tree starts at column 2
      assert.same({ tier = 1, column = 1 }, focused.prereq)
      assert.equals(2, tabs[2].talents[1].rank)
      assert.same({ 1, 4 }, { tabs[3].talents[2].tier, tabs[3].talents[2].column })
    end)

    it("uses the game's sub-trees when it gives them", function()
      local list = {
        { nodeID = 1, name = "a", posX = 0, posY = 0, maxRank = 1, subTreeID = 77 },
        { nodeID = 2, name = "b", posX = 100, posY = 0, maxRank = 1, subTreeID = 55 },
      }
      local tabs = Talents.fromNodes(list, {})
      assert.equals(2, #tabs)
      assert.equals("a", tabs[1].talents[1].name) -- ordered left to right
    end)

    it("plans on the nodes like on a classic tree", function()
      local tabs = Talents.fromNodes(nodes, { "Beast Mastery", "Marksmanship", "Survival" })
      local bm = Talents.templates("HUNTER", tabs)[2]
      local picks = Talents.plan(tabs, bm, 6)
      assert.equals("Deadly Aspects", picks[1].talent.name)
      assert.equals("Endurance Training", picks[6].talent.name)
      assert.same({}, Talents.fromNodes({}, {}))
    end)

    it("reads the user's real Forever tree (self-test of 2026-11-17)", function()
      -- Columns 600 apart, trees about 2200 apart; rows 600 apart, but one
      -- node sits 10 lower than its row; two stray nodes far away.
      local X = { { 1020, 1620, 2220, 2820 }, { 5020, 5620, 6220, 6820 }, { 9080, 9680, 10280, 10880 } }
      local id = 0
      local function n(treeIndex, column, row, name, rank, maxRank, targets, dy)
        id = id + 1
        return { nodeID = id, name = name, posX = X[treeIndex][column], posY = 2130 + (row - 1) * 600 + (dy or 0),
          rank = rank, maxRank = maxRank, targets = targets }
      end
      local real = {
        n(1, 2, 1, "Deadly Aspects", 5, 5), n(1, 3, 1, "Endurance Training", 3, 5),
        n(1, 1, 2, "Focused Fire", 2, 2), n(1, 2, 2, "Improved Aspect of the Monkey", 0, 3),
        n(1, 3, 2, "Improved Revive Pet", 0, 2),
        n(1, 1, 3, "Pathfinding", 0, 2), n(1, 2, 3, "Bestial Swiftness", 1, 1, { 14 }),
        n(1, 3, 3, "Unleashed Fury", 5, 5),
        n(1, 1, 4, "Improved Mend Pet", 0, 2), n(1, 3, 4, "Ferocity", 5, 5, { 16 }), n(1, 4, 4, "Summon Hawk", 1, 1),
        n(1, 1, 5, "Spirit Bond", 0, 2), n(1, 4, 5, "Bestial Discipline", 2, 2),
        n(1, 2, 5, "Intimidation", 1, 1, { 15 }), -- id 14
        n(1, 2, 7, "Bestial Wrath", 0, 1), -- id 15
        n(1, 3, 6, "Frenzy", 0, 5), -- id 16
        n(2, 3, 1, "Lethal Attacks", 0, 5), n(3, 3, 1, "Deflection", 0, 5),
        n(3, 1, 6, "Survival Tactics", 0, 2, nil, 10), -- 10 lower than its row
        { nodeID = 98, name = "Lightning Reflexes", posX = 102800, posY = 5740, rank = 0, maxRank = 5 },
        { nodeID = 99, name = "Improved Serpent Sting", posX = 6820, posY = 39300, rank = 0, maxRank = 5 },
      }
      local tabs = Talents.fromNodes(real, Talents.TREE_NAMES.HUNTER)
      assert.equals(3, #tabs)
      assert.equals(16, #tabs[1].talents) -- the strays are left out
      local byName = {}
      for _, t in ipairs(tabs[1].talents) do
        byName[t.name] = t
      end
      assert.same({ 7, 2 }, { byName["Bestial Wrath"].tier, byName["Bestial Wrath"].column })
      assert.same({ tier = 5, column = 2 }, byName["Bestial Wrath"].prereq)
      assert.equals(6, tabs[3].talents[2].tier) -- 10 units off still counts as its row
      -- 25 points spent at level 34: the next point goes to Frenzy (row 6).
      local bm = Talents.templates("HUNTER", tabs)[2]
      local groups = Talents.group(Talents.plan(tabs, bm, 6))
      assert.equals("Frenzy", groups[1].talent.name)
      assert.same({ 1, 5 }, { groups[1].from, groups[1].to })
      assert.equals("Bestial Wrath", groups[2].talent.name)
    end)
  end)

  it("says how many template names the tree has and picks the busiest tree", function()
    local tabs = tree({ ["Savage Strikes"] = 2 })
    local list = Talents.templates("HUNTER", tabs)
    local found, total = Talents.found(tabs, list[2])
    assert.equals(4, found)
    assert.is_true(total > found)
    assert.equals("hunter-sv", Talents.choose(list, tabs).id)
    assert.equals("hunter-mm", Talents.choose(list, tabs, "hunter-mm").id)
  end)

  describe("the user's levelling build (31/16/4)", function()
    -- The talents the build uses, where Forever puts them (row, column).
    local function realTrees(ranks)
      ranks = ranks or {}
      local function t(name, tier, column, maxRank, prereq)
        return { name = name, tier = tier, column = column, rank = ranks[name] or 0, maxRank = maxRank,
          prereq = prereq }
      end
      return {
        { name = "Beast Mastery", talents = {
          t("Deadly Aspects", 1, 2, 5), t("Endurance Training", 1, 3, 5), t("Focused Fire", 2, 1, 2),
          t("Bestial Swiftness", 3, 2, 1), t("Unleashed Fury", 3, 3, 5), t("Ferocity", 4, 3, 5),
          t("Summon Hawk", 4, 4, 1), t("Intimidation", 5, 2, 1, { tier = 3, column = 2 }),
          t("Bestial Discipline", 5, 4, 2), t("Frenzy", 6, 3, 5, { tier = 4, column = 3 }),
          t("Bestial Wrath", 7, 2, 1, { tier = 5, column = 2 }),
        } },
        { name = "Marksmanship", talents = {
          t("Lethal Attacks", 1, 3, 5), t("Improved Stings", 2, 1, 3), t("Careful Aim", 2, 3, 5),
          t("Rapid Killing", 3, 1, 2), t("Trueshot Aura", 4, 2, 1),
        } },
        { name = "Survival", talents = { t("Improved Tracking", 1, 2, 5), t("Deflection", 1, 3, 5) } },
      }
    end

    it("goes level by level across the trees and ends 31/16/4", function()
      local tabs = realTrees()
      local build = Talents.templates("HUNTER", tabs)[1]
      local p = Talents.preview(tabs, build, 51)
      assert.equals("31/16/4", p.split)
      -- The user's own list: 10-14 Deadly Aspects, 15-16 Focused Fire, ... 57-60 Improved Tracking.
      assert.same({ 10, 14, "Deadly Aspects" }, { p.levels[1].from, p.levels[1].to, p.levels[1].talent.name })
      assert.same({ 25, 25, "Summon Hawk" }, { p.levels[5].from, p.levels[5].to, p.levels[5].talent.name })
      assert.same({ 40, "Bestial Wrath", 1 }, { p.levels[11].from, p.levels[11].talent.name, p.levels[11].tree })
      assert.same({ 41, 45, "Lethal Attacks", 2 },
        { p.levels[12].from, p.levels[12].to, p.levels[12].talent.name, p.levels[12].tree })
      local last = p.levels[#p.levels]
      assert.same({ 57, 60, "Improved Tracking", 3, 4 }, { last.from, last.to, last.talent.name, last.tree,
        last.rankTo })
      -- Each tree ends with its deepest talent.
      assert.equals("Bestial Wrath", p.trees[1].taken[#p.trees[1].taken].talent.name)
      assert.equals("Trueshot Aura", p.trees[2].taken[#p.trees[2].taken].talent.name)
      -- The preview does not touch the player's real trees.
      assert.equals(0, tabs[1].talents[1].rank)
    end)

    it("at level 34 with the build's 25 points, the next is Frenzy (the user's case)", function()
      local tabs = realTrees({ ["Deadly Aspects"] = 5, ["Focused Fire"] = 2, ["Endurance Training"] = 3,
        ["Unleashed Fury"] = 5, ["Summon Hawk"] = 1, ["Ferocity"] = 5, ["Bestial Swiftness"] = 1,
        ["Intimidation"] = 1, ["Bestial Discipline"] = 2 })
      local build = Talents.templates("HUNTER", tabs)[1]
      local groups = Talents.group(Talents.plan(tabs, build, 8))
      assert.same({ "Frenzy", 1, 5, 1 }, { groups[1].talent.name, groups[1].from, groups[1].to, groups[1].tree })
      assert.equals("Bestial Wrath", groups[2].talent.name)
      assert.same({ "Lethal Attacks", 2 }, { groups[3].talent.name, groups[3].tree }) -- then Marksmanship
      local found, total = Talents.found(tabs, build)
      assert.equals(total, found)
    end)
  end)
end)
