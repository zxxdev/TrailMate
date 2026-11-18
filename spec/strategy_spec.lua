local helper = require("spec.helper")

describe("Strategy", function()
  local ns, S

  before_each(function()
    ns = helper.load()
    S = ns.Strategy
  end)

  local arathi = { min = 30, max = 40, side = "AH" }

  it("rates how a zone fits a level", function()
    assert.equals(3, S.fit(arathi, 33))
    assert.equals(1, S.fit(arathi, 29))
    assert.equals(1, S.fit(arathi, 38))
    assert.equals(0, S.fit(arathi, 40))
    assert.is_nil(S.fit(arathi, 27))
  end)

  it("labels difficulty by where the level sits in the range", function()
    assert.equals("hard", S.difficulty(arathi, 31))
    assert.equals("normal", S.difficulty(arathi, 35))
    assert.equals("easy", S.difficulty(arathi, 38))
  end)

  it("recommends the user's real case: level 33 Horde in Arathi with quests there", function()
    local advice = S.advise(33, "Horde", 1417, { [1417] = 4, [1434] = 1 })
    assert.equals(1417, advice.best.mapID)
    assert.equals("normal", advice.best.difficulty)
    local options = {}
    for _, z in ipairs(advice.options) do
      options[z.mapID] = true
      assert.is_true(z.min <= 35 and z.max > 33)
    end
    assert.is_true(options[1434]) -- Stranglethorn Vale
    assert.is_true(options[1443]) -- Desolace
    assert.is_nil(options[1433]) -- Redridge: Alliance only
    assert.is_nil(options[1413]) -- The Barrens: outgrown
    local soon = {}
    for _, z in ipairs(advice.upcoming) do
      soon[z.mapID] = z.min
    end
    assert.equals(35, soon[1445]) -- Dustwallow Marsh
    assert.equals(35, soon[1418]) -- Badlands
    assert.is_false(advice.leaveHere)
  end)

  it("says when the current zone is outgrown", function()
    assert.is_true(S.advise(41, "Horde", 1417, {}).leaveHere)
  end)

  it("never sends a player to a zone far above their level", function()
    for _, z in ipairs(S.rank(12, "Alliance", 1436, {})) do
      assert.is_true(z.min <= 14)
    end
  end)

  it("weighs the route's zone choice by level", function()
    local bonus = S.zoneBonus(33)
    assert.equals(3, bonus(1417))
    assert.equals(0, bonus(1413))
    assert.equals(-3, bonus(1444)) -- Feralas, 40-50
    assert.equals(0, bonus(999999))
  end)
end)

describe("Builder with the strategy", function()
  local ns, L

  before_each(function()
    ns = helper.load()
    L = ns.L
  end)

  local function q(id, mapID, x)
    return { questID = id, title = "Q" .. id, level = 33, target = { mapID = mapID, x = x, y = 0.5 } }
  end

  it("breaks a tie between zones in favour of the one that suits the level", function()
    -- Two quests in an outgrown low zone and two in a fitting zone; the player is in neither.
    local quests = { q(1, 1413, 0.1), q(2, 1413, 0.2), q(3, 1417, 0.3), q(4, 1417, 0.4) }
    local plan, report = ns.Builder.fromQuestLog(quests, { mapID = 1, level = 33 }, L, nil,
      { zoneBonus = ns.Strategy.zoneBonus(33) })
    assert.equals(3, plan.steps[1].questID)
    assert.equals(2, report.counts[1413])
    assert.equals(2, report.counts[1417])
  end)

  it("works in the zone the player chose when it has quests", function()
    local quests = { q(1, 1417, 0.1), q(2, 1417, 0.2), q(3, 1434, 0.3) }
    local plan = ns.Builder.fromQuestLog(quests, { mapID = 1417, level = 33 }, L, nil, { focus = 1434 })
    assert.equals(3, plan.steps[1].questID)
  end)
end)
