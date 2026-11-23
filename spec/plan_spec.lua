local helper = require("spec.helper")

describe("Plan", function()
  local ns, Plan

  local function sample()
    return {
      version = 1,
      id = "demo",
      title = "Demo",
      steps = {
        { id = "a", type = "accept", questID = 100, text = "Take the wolves quest" },
        { id = "g", type = "goto", mapID = 1, x = 0.4, y = 0.4, text = "Go to the farm" },
        { id = "c", type = "complete", questID = 100, text = "Kill wolves" },
        { id = "t", type = "turnin", questID = 100, text = "Turn it in" },
        { id = "l", type = "level", level = 12, text = "Reach level 12" },
        { id = "n", type = "note", text = "Buy arrows" },
      },
    }
  end

  before_each(function()
    ns = helper.load()
    Plan = ns.Plan
  end)

  describe("validate", function()
    it("accepts a valid plan", function()
      assert.is_true(Plan.validate(sample()))
    end)

    it("rejects a plan with a function inside", function()
      local p = sample()
      p.steps[1].text = function() end
      local ok, err = Plan.validate(p)
      assert.is_nil(ok)
      assert.matches("only data", err)
    end)

    it("rejects a table with a metatable", function()
      local p = sample()
      p.steps[2] = setmetatable({ id = "x", type = "note", text = "x" }, {})
      assert.is_nil((Plan.validate(p)))
    end)

    it("rejects unknown types, repeated ids and long texts", function()
      local p = sample()
      p.steps[1].type = "teleport"
      assert.matches("unknown type", select(2, Plan.validate(p)))

      p = sample()
      p.steps[2].id = "a"
      assert.matches("repeats id", select(2, Plan.validate(p)))

      p = sample()
      p.steps[1].text = string.rep("x", Plan.MAX_TEXT + 1)
      assert.matches("valid text", select(2, Plan.validate(p)))
    end)

    it("rejects bad quest ids, coordinates, versions and too many steps", function()
      local p = sample()
      p.steps[1].questID = 1.5
      assert.matches("questID", select(2, Plan.validate(p)))

      p = sample()
      p.steps[2].x = 2
      assert.matches("map point", select(2, Plan.validate(p)))

      p = sample()
      p.version = 2
      assert.matches("version", select(2, Plan.validate(p)))

      p = sample()
      for i = 1, Plan.MAX_STEPS + 1 do
        p.steps[i] = { id = "s" .. i, type = "note", text = "n" }
      end
      assert.matches("too many", select(2, Plan.validate(p)))
    end)

    it("takes who a step is about, and rejects a bad creature id or name", function()
      local p = sample()
      p.steps[1].creature, p.steps[1].who = 3143, "Gornek"
      assert.is_true(Plan.validate(p))
      p.steps[1].creature = 0
      assert.matches("creature", select(2, Plan.validate(p)))
      p.steps[1].creature = "3143"
      assert.matches("creature", select(2, Plan.validate(p)))
      p.steps[1].creature, p.steps[1].who = 3143, ("x"):rep(Plan.MAX_TEXT + 1)
      assert.matches("who", select(2, Plan.validate(p)))
    end)

    it("rejects non-finite numbers and holes in the step list", function()
      local p = sample()
      p.steps[5].level = 0 / 0
      assert.is_nil((Plan.validate(p)))

      p = sample()
      p.steps[8] = { id = "late", type = "note", text = "gap" }
      assert.matches("list of steps", select(2, Plan.validate(p)))
    end)
  end)

  describe("evaluate", function()
    it("starts at the first step", function()
      local p = sample()
      local current = Plan.evaluate(p, Plan.newProgress(p), helper.facts())
      assert.equals(1, current)
    end)

    it("advances when the quest enters the log", function()
      local p = sample()
      local f = helper.facts({ questLog = { [100] = { complete = false } } })
      assert.equals(2, (Plan.evaluate(p, Plan.newProgress(p), f)))
    end)

    it("marks a goto step when the player arrives and keeps it after leaving", function()
      local p = sample()
      local progress = Plan.newProgress(p)
      local f = helper.facts({ questLog = { [100] = { complete = false } }, x = 0.401, y = 0.4 })
      local current, _, changed = Plan.evaluate(p, progress, f)
      assert.equals(3, current)
      assert.is_true(changed)
      f.x, f.y = 0.9, 0.9
      assert.equals(3, (Plan.evaluate(p, progress, f)))
    end)

    it("does not arrive with an unknown or zero position (instances)", function()
      local p = sample()
      local f = helper.facts({ questLog = { [100] = { complete = false } }, x = 0, y = 0 })
      p.steps[2].x, p.steps[2].y = 0.001, 0.001
      assert.equals(2, (Plan.evaluate(p, Plan.newProgress(p), f)))
      f.x, f.y = nil, nil
      assert.equals(2, (Plan.evaluate(p, Plan.newProgress(p), f)))
    end)

    it("counts a turn-in only when the game flags the quest as completed", function()
      local p = sample()
      local progress = Plan.newProgress(p)
      progress.done.g = true
      -- Gone from the log but not flagged: abandoned, not turned in.
      local f = helper.facts()
      local current, statuses = Plan.evaluate(p, progress, f)
      assert.equals(1, current)
      assert.equals("pending", statuses[3])
      assert.equals("pending", statuses[4])
      f.turned[100] = true
      assert.equals(5, (Plan.evaluate(p, progress, f)))
    end)

    it("skips what is already done when a plan is loaded", function()
      local p = sample()
      local progress = Plan.newProgress(p)
      progress.done.g = true
      local f = helper.facts({ turned = { [100] = true } })
      assert.equals(5, (Plan.evaluate(p, progress, f)))
    end)

    it("marks a later step done out of order", function()
      local p = sample()
      local f = helper.facts({ level = 12 })
      local _, statuses = Plan.evaluate(p, Plan.newProgress(p), f)
      assert.equals("done", statuses[5])
      assert.equals("pending", statuses[1])
    end)

    it("does not mark a later goto step out of order", function()
      local p = sample()
      local f = helper.facts({ x = 0.4, y = 0.4 })
      local current, statuses = Plan.evaluate(p, Plan.newProgress(p), f)
      assert.equals(1, current)
      assert.equals("pending", statuses[2])
    end)

    it("returns nil when the plan is finished", function()
      local p = sample()
      local progress = Plan.newProgress(p)
      progress.done.g, progress.done.n = true, true
      local f = helper.facts({ level = 12, turned = { [100] = true } })
      assert.is_nil((Plan.evaluate(p, progress, f)))
    end)
  end)

  describe("manual marks", function()
    it("skips, marks done and undoes", function()
      local p = sample()
      local progress = Plan.newProgress(p)
      local f = helper.facts()
      assert.equals("a", Plan.skip(p, progress, f).id)
      assert.equals(2, (Plan.evaluate(p, progress, f)))
      assert.equals("g", Plan.markDone(p, progress, f).id)
      -- The quest was never picked up: doing and handing it in are passed too.
      assert.equals(5, (Plan.evaluate(p, progress, f)))
      assert.equals("g", Plan.undo(progress))
      assert.equals(2, (Plan.evaluate(p, progress, f)))
      assert.equals("a", Plan.undo(progress))
      assert.equals(1, (Plan.evaluate(p, progress, f)))
      assert.is_nil(Plan.undo(progress))
    end)

    it("passes a hand-in for a quest you never had (Hemet Nesingwary, the user's case)", function()
      local p = { version = 1, id = "guide-stv", steps = {
        { id = "t1", type = "turnin", questID = 5762, text = "Turn in: Hemet Nesingwary" },
        { id = "t2", type = "turnin", questID = 583, text = "Turn in: Welcome to the Jungle" },
        { id = "a3", type = "accept", questID = 194, text = "Pick up: Raptor Mastery" },
        { id = "c3", type = "complete", questID = 194, text = "Do: Raptor Mastery" },
      } }
      local progress = Plan.newProgress(p)
      -- Welcome to the Jungle is in the log, Hemet Nesingwary never was.
      local f = helper.facts({ questLog = { [583] = { complete = true } } })
      assert.equals(2, (Plan.evaluate(p, progress, f)))
      -- Handed in: on to Raptor Mastery, whose "do" step waits for its pick-up.
      f.questLog[583], f.turned[583] = nil, true
      assert.equals(3, (Plan.evaluate(p, progress, f)))
      local _, statuses = Plan.evaluate(p, progress, f)
      assert.equals("pending", statuses[4])
    end)

    it("lets the player choose which pending step to do now", function()
      local p = sample()
      local progress = Plan.newProgress(p)
      local f = helper.facts()
      assert.equals("c", Plan.choose(p, progress, f, 3).id)
      assert.equals(3, (Plan.evaluate(p, progress, f)))
      -- Once it is done, the plan goes back to its own order.
      f.questLog[100] = { complete = true }
      assert.equals(2, (Plan.evaluate(p, progress, f)))
      assert.is_nil(progress.chosen)
      -- A step that is not pending cannot be chosen.
      assert.is_nil(Plan.choose(p, progress, f, 1))
      assert.is_nil(Plan.choose(p, progress, f, 99))
    end)
  end)

  describe("progress", function()
    it("keeps saved progress for the same plan and resets for another id", function()
      local p = sample()
      local saved = Plan.newProgress(p)
      saved.done.g = true
      assert.equals(saved, Plan.ensureProgress(p, saved))
      local other = sample()
      other.id = "other"
      assert.are_not.equal(saved, Plan.ensureProgress(other, saved))
      assert.is_nil(Plan.ensureProgress(other, saved).done.g)
    end)
  end)
end)
