local helper = require("spec.helper")

describe("Guide", function()
  local ns, Guide, L
  local hunter = { faction = "Horde", class = "HUNTER", race = "ORC" }

  before_each(function()
    ns = helper.load()
    Guide, L = ns.Guide, ns.L
    assert(loadfile("TrailMate/data/Guides.lua"))("TrailMate", ns)
  end)

  local small = {
    name = "33-34 Test Vale", faction = "Horde", min = 33, max = 34,
    steps = {
      { t = "note", text = "Take the Zeppelin" },
      { t = "accept", q = 581, name = "Hunt for Yenniku", npc = "Nimboya", m = 1434, x = 0.322, y = 0.277 },
      { t = "accept", q = 629, name = "The Vile Reef", opt = true, m = 1434, x = 0.323, y = 0.277 },
      { t = "accept", q = 3108, name = "Hunter only", only = { "HUNTER" } },
      { t = "accept", q = 3112, name = "Warrior only", only = { "WARRIOR" } },
      { t = "complete", q = 581, name = "Hunt for Yenniku", m = 1434, x = 0.2, y = 0.3 },
      { t = "turnin", q = 581, name = "Hunt for Yenniku", npc = "Nimboya", m = 1434, x = 0.322, y = 0.277 },
    },
  }

  it("turns a guide into a plan with a place for every quest step", function()
    local plan = Guide.toPlan(small, { who = hunter, L = L })
    assert.is_true(ns.Plan.validate(plan))
    assert.is_true(Guide.isGuide(plan))
    -- Steps for other classes are left out.
    assert.equals(6, #plan.steps)
    local first = plan.steps[2]
    assert.same({ "accept", 581, "Pick up: Hunt for Yenniku", "From Nimboya", 1434 },
      { first.type, first.questID, first.text, first.why, first.mapID })
    assert.matches("^Optional", plan.steps[3].why)
    assert.is_true(plan.steps[1].soft)
    -- The game's own (localized) name wins when it has it.
    local named = Guide.toPlan(small, { who = hunter, L = L, title = function() return "Caza de Yenniku" end })
    assert.equals("Pick up: Caza de Yenniku", named.steps[2].text)
    -- Where the player saw the quest giver wins over the data's place.
    local seen = Guide.toPlan(small, { who = hunter, L = L, place = function(s)
      return s.q == 581 and s.t == "accept" and { mapID = 1434, x = 0.4, y = 0.5 } or nil
    end })
    assert.same({ 1434, 0.4, 0.5 }, { seen.steps[2].mapID, seen.steps[2].x, seen.steps[2].y })
    assert.equals(0.322, seen.steps[6].x) -- the turn-in keeps the data's place
  end)

  it("passes the guide's notes once something after them is done", function()
    local plan = Guide.toPlan(small, { who = hunter, L = L })
    local progress = ns.Plan.newProgress(plan)
    local f = helper.facts()
    assert.equals(1, (ns.Plan.evaluate(plan, progress, f))) -- "Take the Zeppelin" first
    f.questLog[581] = { complete = false } -- picked up Yenniku: the note is behind
    assert.equals(3, (ns.Plan.evaluate(plan, progress, f)))
  end)

  it("picks Stranglethorn at level 34 for a Horde hunter, then the next guide (the user's case)", function()
    local list = Guide.list(ns.GUIDES, hunter)
    assert.is_true(#list > 20)
    local stv = Guide.pick(list, 34)
    assert.equals("33-34 Stranglethorn Vale", stv.name)
    -- When its quests are all handed in, the next one.
    local done = function(g) return g == stv end
    assert.equals("34-35 Dalaran City", Guide.pick(list, 34, nil, done).name)
    assert.equals(Guide.after(list, stv), Guide.pick(list, 34, nil, done))
    -- A chosen guide wins.
    assert.equals("36-39 Desolace", Guide.pick(list, 34, "36-39 Desolace").name)
  end)

  it("has a real place for the Grom'gol quests and a valid plan for every guide", function()
    local stv = Guide.pick(Guide.list(ns.GUIDES, hunter), 34)
    local plan = Guide.toPlan(stv, { who = hunter, L = L })
    local yenniku
    for _, s in ipairs(plan.steps) do
      if s.type == "accept" and s.questID == 581 then
        yenniku = s
        break
      end
    end
    assert.same({ 1434, "From Nimboya" }, { yenniku.mapID, yenniku.why })
    assert.is_true(math.abs(yenniku.x - 0.322) < 0.01 and math.abs(yenniku.y - 0.277) < 0.01)
    for _, g in ipairs(ns.GUIDES) do
      local who = { faction = g.faction, class = "HUNTER", race = "ORC" }
      local ok, err = ns.Plan.validate(Guide.toPlan(g, { who = who, L = L }))
      assert(ok, g.name .. ": " .. tostring(err))
    end
  end)

  it("notices when the quest giver does not offer the step's quest (Trollbane at Grom'gol, the user's case)", function()
    local step = { type = "accept", questID = 638, npc = "Nimboya", text = "Pick up: Trollbane" }
    -- Nimboya offers other quests, not Trollbane: the guide must not wait.
    assert.is_true(Guide.notOffered(step, "Nimboya", { { questID = 581 } }))
    assert.is_true(Guide.notOffered(step, "Nimboya", {}))
    -- Offered, someone else, or not a pick-up step: nothing to do.
    assert.is_false(Guide.notOffered(step, "Nimboya", { { questID = 638 } }))
    assert.is_false(Guide.notOffered(step, "Kin'weelay", {}))
    assert.is_false(Guide.notOffered({ type = "turnin", questID = 638, npc = "Nimboya" }, "Nimboya", {}))
    -- Guide steps know their quest giver.
    local plan = Guide.toPlan(small, { who = hunter, L = L })
    assert.equals("Nimboya", plan.steps[2].npc)
  end)

  it("knows when a guide is finished", function()
    assert.is_false(Guide.finished(small, hunter, function() return false end))
    assert.is_true(Guide.finished(small, hunter, function() return true end))
  end)
end)
