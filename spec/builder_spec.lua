local helper = require("spec.helper")

describe("Builder.fromQuestLog", function()
  local ns, L

  before_each(function()
    ns = helper.load()
    L = ns.L
  end)

  local function ids(plan)
    local out = {}
    for _, s in ipairs(plan.steps) do
      out[#out + 1] = s.id
    end
    return table.concat(out, ",")
  end

  it("returns nil for an empty log", function()
    assert.is_nil(ns.Builder.fromQuestLog({}, nil, L))
  end)

  it("turns in complete quests first, then visits the rest by distance", function()
    local quests = {
      { questID = 1, title = "Far", complete = false, target = { mapID = 5, x = 0.9, y = 0.9 } },
      { questID = 2, title = "Done", complete = true },
      { questID = 3, title = "Near", complete = false, target = { mapID = 5, x = 0.2, y = 0.2 } },
      { questID = 4, title = "Other map", complete = false, target = { mapID = 6, x = 0.1, y = 0.1 } },
    }
    local plan = ns.Builder.fromQuestLog(quests, { mapID = 5, x = 0.1, y = 0.1 }, L)
    assert.equals("turnin-2,complete-3,complete-1,complete-4,turnin-3,turnin-1,turnin-4", ids(plan))
    assert.is_true(ns.Plan.validate(plan))
  end)

  it("picks up nearby quest givers first, then does and turns in everything", function()
    local quests = { { questID = 1, title = "In log", complete = false, target = { mapID = 5, x = 0.5, y = 0.5 } } }
    local available = {
      { questID = 20, title = "Far giver", target = { mapID = 5, x = 0.9, y = 0.9 } },
      { questID = 21, title = "Near giver", target = { mapID = 5, x = 0.2, y = 0.2 } },
      { questID = 1, title = "Already in log", target = { mapID = 5, x = 0.1, y = 0.1 } },
    }
    local plan = ns.Builder.fromQuestLog(quests, { mapID = 5, x = 0.1, y = 0.1 }, L, available)
    assert.equals("accept-21,accept-20,complete-1,complete-21,complete-20,turnin-1,turnin-21,turnin-20", ids(plan))
    assert.equals(0.2, plan.steps[1].x)
    assert.is_true(ns.Plan.validate(plan))
    assert.is_true(ns.Builder.isAuto(plan))
  end)

  it("builds a plan from quest givers alone and caps how many it adds", function()
    local available = {}
    for i = 1, 15 do
      available[i] = { questID = 100 + i, title = "Q" .. i, target = { mapID = 5, x = i / 20, y = 0.5 } }
    end
    local plan = ns.Builder.fromQuestLog({}, { mapID = 5, x = 0, y = 0.5 }, L, available)
    assert.equals(ns.Builder.MAX_OFFERS * 3, #plan.steps)
    assert.equals("accept-101", plan.steps[1].id)
  end)

  it("gives the same id to the same quests in any order", function()
    local a = ns.Builder.planId({ { questID = 1 }, { questID = 2 } })
    local b = ns.Builder.planId({ { questID = 2 }, { questID = 1 } })
    local c = ns.Builder.planId({ { questID = 1 }, { questID = 3 } })
    assert.equals(a, b)
    assert.are_not.equal(a, c)
  end)

  it("cuts very long titles so the plan stays valid", function()
    local quests = { { questID = 7, title = string.rep("x", 500), complete = false } }
    assert.is_true(ns.Plan.validate(ns.Builder.fromQuestLog(quests, nil, L)))
  end)

  it("uses the Spanish texts on a Spanish client", function()
    ns.setLocale("esES")
    local plan = ns.Builder.fromQuestLog({ { questID = 9, title = "Lobos", complete = true } }, nil, L)
    assert.equals("Entregar: Lobos", plan.steps[1].text)
  end)
end)

describe("Throttle", function()
  it("runs once for a burst of a hundred events", function()
    local ns = helper.load()
    local t = ns.Throttle.new(0.25)
    local runs = 0
    for i = 1, 100 do
      t:mark()
      if t:tick(i * 0.001) then
        runs = runs + 1
      end
    end
    assert.equals(1, runs)
    assert.is_false(t:tick(0.2))
    t:mark()
    assert.is_true(t:tick(0.5))
  end)
end)
