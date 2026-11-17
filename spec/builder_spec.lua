local helper = require("spec.helper")

describe("Builder", function()
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

  local function titles(list)
    local out = {}
    for _, e in ipairs(list) do
      out[#out + 1] = e.title or e.zone
    end
    table.sort(out)
    return table.concat(out, ",")
  end

  describe("classify", function()
    it("follows the game's colours for a level 33 player", function()
      local c = ns.Builder.classify
      assert.equals(25, ns.Builder.grayLevel(33))
      assert.equals("ok", c({ level = 32 }, 33))
      assert.equals("ok", c({ level = 26 }, 33))
      assert.equals("trivial", c({ level = 25 }, 33))
      assert.equals("hard", c({ level = 37 }, 33))
      assert.equals("tooHard", c({ level = 38 }, 33))
      assert.equals("group", c({ level = 30, group = true }, 33))
      assert.equals("ready", c({ level = 40, complete = true }, 33))
      assert.equals("ok", c({}, 33))
    end)
  end)

  describe("fromQuestLog", function()
    it("returns nil for an empty log", function()
      assert.is_nil((ns.Builder.fromQuestLog({}, nil, L)))
    end)

    it("works one zone, the player's, nearest first; the rest goes to later", function()
      local quests = {
        { questID = 1, title = "Far", target = { mapID = 5, x = 0.9, y = 0.9 } },
        { questID = 2, title = "Done, place unknown", complete = true },
        { questID = 3, title = "Near", target = { mapID = 5, x = 0.2, y = 0.2 } },
        { questID = 4, title = "Other map", zone = "Six", target = { mapID = 6, x = 0.1, y = 0.1 } },
      }
      local plan, report = ns.Builder.fromQuestLog(quests, { mapID = 5, x = 0.1, y = 0.1 }, L)
      assert.equals("complete-3,complete-1,turnin-3,turnin-1", ids(plan))
      assert.equals("Six,Unknown place", titles(report.later))
      assert.is_true(ns.Plan.validate(plan))
      assert.is_true(ns.Builder.isAuto(plan))
    end)

    it("mixes turn-ins of complete quests into the route by distance", function()
      local quests = {
        { questID = 1, title = "Cook", complete = true, zone = "Far away", target = { mapID = 9, x = 0.5, y = 0.5 } },
        { questID = 2, title = "Mid", target = { mapID = 5, x = 0.5, y = 0.5 } },
        { questID = 3, title = "Ready here", complete = true, target = { mapID = 5, x = 0.3, y = 0.3 } },
      }
      local plan, report = ns.Builder.fromQuestLog(quests, { mapID = 5, x = 0.1, y = 0.1 }, L)
      assert.equals("turnin-3,complete-2,turnin-2", ids(plan))
      assert.equals("Far away", titles(report.later))
    end)

    it("moves to another zone when it is clearly better", function()
      local quests = {
        { questID = 1, title = "Lonely", zone = "Here", target = { mapID = 5, x = 0.5, y = 0.5 } },
        { questID = 2, title = "A", zone = "There", target = { mapID = 7, x = 0.1, y = 0.1 } },
        { questID = 3, title = "B", zone = "There", target = { mapID = 7, x = 0.9, y = 0.9 } },
        { questID = 4, title = "C", zone = "There", target = { mapID = 7, x = 0.2, y = 0.2 } },
      }
      local plan, report = ns.Builder.fromQuestLog(quests, { mapID = 5, x = 0.1, y = 0.1 }, L)
      assert.equals("There", report.zone)
      assert.equals("There", plan.title)
      assert.equals("complete-2,complete-4,complete-3,turnin-2,turnin-4,turnin-3", ids(plan))
      assert.equals("Here", titles(report.later))
    end)

    it("decides the user's real Arathi case at level 33", function()
      local function q(id, title, level, x, extra)
        local t = { questID = id, title = title, level = level, zone = "Arathi Highlands",
          target = { mapID = 1417, x = x, y = 0.5 } }
        for k, v in pairs(extra or {}) do
          t[k] = v
        end
        return t
      end
      local quests = {
        q(1, "Call to Arms", 32, 0.3),
        q(2, "Guile of the Raptor", 37, 0.6),
        q(3, "Sigil of Strom", 38, 0.2, { group = true }),
        q(4, "The Princess Trapped", 37, 0.5),
        q(5, "Anyone Can Cook", 40, 0.65, { complete = true }),
        { questID = 6, title = "Humbert's Sword", level = 30, group = true, zone = "Hillsbrad Foothills",
          target = { mapID = 1424, x = 0.5, y = 0.5 } },
        { questID = 7, title = "Warsong Supplies", level = 24, zone = "Ashenvale",
          target = { mapID = 1440, x = 0.5, y = 0.5 } },
      }
      local plan, report = ns.Builder.fromQuestLog(quests, { mapID = 1417, x = 0.74, y = 0.5, level = 33 }, L)
      assert.equals("Arathi Highlands", report.zone)
      assert.equals("turnin-5,complete-2,complete-4,complete-1,turnin-2,turnin-4,turnin-1", ids(plan))
      assert.matches("Hard %(level 37%)", plan.steps[2].why)
      assert.equals("Humbert's Sword,Sigil of Strom", titles(report.notNow))
      assert.equals("Warsong Supplies", titles(report.abandon))
      assert.equals("", titles(report.later))
    end)

    it("picks up nearby quest givers first, then does and turns in everything", function()
      local quests = { { questID = 1, title = "In log", target = { mapID = 5, x = 0.5, y = 0.5 } } }
      local available = {
        { questID = 20, title = "Far giver", target = { mapID = 5, x = 0.9, y = 0.9 } },
        { questID = 21, title = "Near giver", target = { mapID = 5, x = 0.2, y = 0.2 } },
        { questID = 1, title = "Already in log", target = { mapID = 5, x = 0.1, y = 0.1 } },
      }
      local plan = ns.Builder.fromQuestLog(quests, { mapID = 5, x = 0.1, y = 0.1 }, L, available)
      assert.equals("accept-21,accept-20,complete-1,complete-21,complete-20,turnin-1,turnin-21,turnin-20", ids(plan))
      assert.equals(0.2, plan.steps[1].x)
      assert.is_true(ns.Plan.validate(plan))
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

    it("still plans when no quest has a known place, in log order", function()
      local quests = {
        { questID = 7, title = string.rep("x", 500) },
        { questID = 8, title = "Second", complete = true },
      }
      local plan = ns.Builder.fromQuestLog(quests, nil, L)
      assert.equals("complete-7,turnin-8,turnin-7", ids(plan))
      assert.is_true(ns.Plan.validate(plan))
    end)

    it("uses the Spanish texts on a Spanish client", function()
      ns.setLocale("esES")
      local plan = ns.Builder.fromQuestLog({ { questID = 9, title = "Lobos", complete = true } }, nil, L)
      assert.equals("Entregar: Lobos", plan.steps[1].text)
    end)
  end)

  it("gives the same id to the same quests in any order", function()
    local a = ns.Builder.planId({ { questID = 1 }, { questID = 2 } })
    local b = ns.Builder.planId({ { questID = 2 }, { questID = 1 } })
    local c = ns.Builder.planId({ { questID = 1 }, { questID = 3 } })
    assert.equals(a, b)
    assert.are_not.equal(a, c)
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
