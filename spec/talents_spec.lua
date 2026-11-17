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
