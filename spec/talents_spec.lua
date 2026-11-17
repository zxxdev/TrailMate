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
        t(1, "Improved Aspect of the Hawk", 1, 2, 5),
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
    assert.equals(3, #list)
    assert.equals("Beast Mastery", list[1].label)
    assert.equals("easy", list[1].difficulty)
    -- Another class gets a plain "fill this tree" choice per tree.
    local other = Talents.templates("PRIEST", tree())
    assert.equals(3, #other)
    assert.is_true(other[2].auto)
  end)

  it("follows the template order and opens rows every five points", function()
    local tabs = tree()
    local bm = Talents.templates("HUNTER", tabs)[1]
    local picks = Talents.plan(tabs, bm, 11)
    -- Hawk 1-5, then Endurance Training 1-5, then Unleashed Fury in row 2.
    assert.equals("Improved Aspect of the Hawk", picks[1].talent.name)
    assert.equals(5, picks[5].rank)
    assert.equals("Endurance Training", picks[6].talent.name)
    assert.equals("Unleashed Fury", picks[11].talent.name)
    local grouped = Talents.group(picks)
    assert.same({ 1, 5 }, { grouped[1].from, grouped[1].to })
    assert.equals("Unleashed Fury", grouped[3].talent.name)
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
    local tabs = tree({ ["Improved Aspect of the Hawk"] = 5, ["Endurance Training"] = 5, ["Unleashed Fury"] = 4 })
    local bm = Talents.templates("HUNTER", tabs)[1]
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
      node(1, "Improved Aspect of the Hawk", 1, 2, 1, 0, { 3 }),
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
      local bm = Talents.templates("HUNTER", tabs)[1]
      local picks = Talents.plan(tabs, bm, 6)
      assert.equals("Improved Aspect of the Hawk", picks[1].talent.name)
      assert.equals("Endurance Training", picks[6].talent.name)
      assert.same({}, Talents.fromNodes({}, {}))
    end)
  end)

  it("says how many template names the tree has and picks the busiest tree", function()
    local tabs = tree({ ["Savage Strikes"] = 2 })
    local list = Talents.templates("HUNTER", tabs)
    local found, total = Talents.found(tabs, list[1])
    assert.equals(4, found)
    assert.is_true(total > found)
    assert.equals("hunter-sv", Talents.choose(list, tabs).id)
    assert.equals("hunter-mm", Talents.choose(list, tabs, "hunter-mm").id)
  end)
end)
