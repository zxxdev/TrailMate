local helper = require("spec.helper")

describe("ClassQuests", function()
  local ns, CQ, L

  before_each(function()
    ns = helper.load()
    CQ, L = ns.ClassQuests, ns.L
  end)

  local ORC, TAUREN = 2, 32 -- race bits: 2 ^ (race id - 1)

  -- A context: level, race bit, handed-in quests and quests in the log.
  local function ctx(level, raceBit, done, log, distance)
    done, log = done or {}, log or {}
    return {
      level = level, raceBit = raceBit, distance = distance,
      done = function(id)
        return done[id] == true
      end,
      inLog = function(id)
        return log[id] == true
      end,
    }
  end

  local function names(list)
    local out = {}
    for _, q in ipairs(list) do
      out[#out + 1] = q.name .. " " .. q.q
    end
    return out
  end

  it("turns a race id of the game into the database's race bit", function()
    assert.equals(1, CQ.raceBit(1)) -- Human
    assert.equals(2, CQ.raceBit(2)) -- Orc
    assert.equals(2 ^ 32, CQ.raceBit(33)) -- beyond 32 bits still works
    assert.is_nil(CQ.raceBit(nil))
    assert.is_nil(CQ.raceBit(0))
  end)

  it("says what each quest is for the character now", function()
    local q = { q = 10, name = "Call of Fire", level = 10, req = 10, races = ORC + TAUREN, pre = { 9 } }
    assert.equals("race", CQ.status(q, ctx(10, 1, { [9] = true })))
    assert.equals("pre", CQ.status(q, ctx(10, ORC)))
    assert.equals("level", CQ.status(q, ctx(9, ORC, { [9] = true })))
    assert.equals("ready", CQ.status(q, ctx(10, ORC, { [9] = true })))
    assert.equals("log", CQ.status(q, ctx(10, ORC, { [9] = true }, { [10] = true })))
    assert.equals("done", CQ.status(q, ctx(10, ORC, { [9] = true, [10] = true })))
    -- A quest in the log is not handed in: it does not open the next one.
    assert.equals("pre", CQ.status(q, ctx(10, ORC, {}, { [9] = true })))
    -- Unknown race: every quest of the class fits.
    assert.equals("ready", CQ.status(q, ctx(10, nil, { [9] = true })))
  end)

  it("needs all of preAll, and closes a quest when another one is taken", function()
    local both = { q = 20, name = "Both", level = 10, req = 10, preAll = { 1, 2 } }
    assert.equals("pre", CQ.status(both, ctx(10, ORC, { [1] = true })))
    assert.equals("ready", CQ.status(both, ctx(10, ORC, { [1] = true, [2] = true })))
    local excl = { q = 21, name = "Either", level = 10, req = 10, excl = { 22 } }
    assert.equals("gone", CQ.status(excl, ctx(10, ORC, {}, { [22] = true })))
    local crumb = { q = 23, name = "Letter", level = 10, req = 10, crumb = 24 }
    assert.equals("gone", CQ.status(crumb, ctx(10, ORC, { [24] = true })))
  end)

  it("lists one quest per name with the nearest giver, highest level first", function()
    local quests = {
      { q = 1, name = "Etched Note", level = 1, req = 1 },
      { q = 2, name = "Call of Fire", level = 10, req = 10, m = 1 },
      { q = 3, name = "Call of Fire", level = 10, req = 10, m = 2 },
      { q = 4, name = "Call of Water", level = 20, req = 20 },
      { q = 5, name = "Call of Air", level = 30, req = 30 },
    }
    local yards = { [1] = 900, [2] = 120 }
    local ready, soon, soonLevel = CQ.forNow(quests, ctx(12, ORC, {}, {}, function(q)
      return q.m and yards[q.m]
    end))
    assert.same({ "Call of Fire 3", "Etched Note 1" }, names(ready))
    assert.same({ "Call of Water 4" }, names(soon)) -- only the next level that brings any
    assert.equals(20, soonLevel)
    -- Without distances: the first one.
    ready = CQ.forNow(quests, ctx(12, ORC))
    assert.same({ "Call of Fire 2", "Etched Note 1" }, names(ready))
  end)

  it("waits a level or two for a nearer giver of the same quest", function()
    local quests = {
      { q = 1, name = "Call of Earth", level = 4, req = 3, m = 2 }, -- far away, opens at 3
      { q = 2, name = "Call of Earth", level = 4, req = 4, m = 1 }, -- next door, opens at 4
      { q = 3, name = "Call of Fire", level = 10, req = 3, m = 2 }, -- far, but no nearer one: offered
    }
    local yards = { [1] = 40 } -- map 2 is another continent: no distance
    local function near(q)
      return yards[q.m]
    end
    local ready, soon, soonLevel = CQ.forNow(quests, ctx(3, ORC, {}, {}, near))
    assert.same({ "Call of Fire 3" }, names(ready))
    assert.same({ "Call of Earth 2" }, names(soon))
    assert.equals(4, soonLevel)
    assert.same({ "Call of Fire 3", "Call of Earth 2" }, names((CQ.forNow(quests, ctx(4, ORC, {}, {}, near)))))
    -- Too many levels to wait: the far one now.
    quests[2].req = 3 + CQ.WAIT_LEVELS + 1
    assert.same({ "Call of Fire 3", "Call of Earth 1" }, names((CQ.forNow(quests, ctx(3, ORC, {}, {}, near)))))
    -- Without distances, what is open now.
    quests[2].req = 4
    assert.same({ "Call of Fire 3", "Call of Earth 1" }, names((CQ.forNow(quests, ctx(3, ORC)))))
  end)

  it("goes straight to a quest when its breadcrumb is ready too", function()
    local quests = {
      { q = 1, name = "Heeding the Call", level = 10, req = 10, crumb = 2 },
      { q = 2, name = "Moonglade", level = 10, req = 10 },
    }
    assert.same({ "Moonglade 2" }, names((CQ.forNow(quests, ctx(10, ORC)))))
    -- The target is not ready yet (needs a quest first): the breadcrumb stays.
    quests[2].pre = { 99 }
    assert.same({ "Heeding the Call 1" }, names((CQ.forNow(quests, ctx(10, ORC)))))
  end)

  it("has nothing for a class with no data", function()
    local ready, soon, soonLevel = CQ.forNow(nil, ctx(10, ORC))
    assert.same({}, ready)
    assert.same({}, soon)
    assert.is_nil(soonLevel)
  end)

  it("tells about each ready quest once", function()
    local ready = { { q = 1, name = "A" }, { q = 2, name = "B" } }
    assert.same({ "B 2" }, names(CQ.news(ready, { [1] = true })))
    assert.same({ "A 1", "B 2" }, names(CQ.news(ready, nil)))
  end)

  describe("with the data of Forever", function()
    local data

    before_each(function()
      assert(loadfile("TrailMate/data/ClassQuests.lua"))("TrailMate", ns)
      data = ns.CLASS_QUESTS
    end)

    local function readyNames(class, level, raceID, done)
      local out = {}
      for _, q in ipairs((CQ.forNow(data[class], ctx(level, CQ.raceBit(raceID), done)))) do
        out[q.name] = q.q
      end
      return out
    end

    it("has every class, each quest once, with a level and a place to start", function()
      local seen = {}
      local classes = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }
      for _, class in ipairs(classes) do
        assert.is_true(#data[class] > 20, class)
        for _, q in ipairs(data[class]) do
          assert.is_nil(seen[q.q], "twice: " .. q.q)
          seen[q.q] = true
          assert.is_string(q.name)
          assert.is_true(q.req >= 1 and q.req <= 59 and q.level <= 59, q.name)
          assert.is_true(q.m > 0 and q.x >= 0 and q.x <= 1 and q.y >= 0 and q.y <= 1, q.name)
        end
      end
    end)

    it("gives each class the quests the user asked for", function()
      -- Shaman totems: earth at 4 (a Tauren), fire at 10 (an Orc).
      assert.is_number(readyNames("SHAMAN", 4, 6)["Call of Earth"])
      assert.is_number(readyNames("SHAMAN", 10, 2)["Call of Fire"])
      -- Warlock: the mount at 40.
      assert.is_number(readyNames("WARLOCK", 40, 2)["Summon Felsteed"])
      -- Paladin: resurrection at 12 (Human), Forever's undead paladin mount at 40.
      assert.is_number(readyNames("PALADIN", 12, 1)["The Tome of Divinity"])
      assert.equals(94971, readyNames("PALADIN", 40, 5)["A Paladin's Steed"])
      -- Hunter: the first pet at 10, each race from its own trainer.
      assert.equals(6062, readyNames("HUNTER", 10, 2)["Taming the Beast"]) -- Orc: Thotar
      assert.equals(6061, readyNames("HUNTER", 10, 6)["Taming the Beast"]) -- Tauren: Yaw Sharpmane
    end)

    it("does not offer the same step from another capital while doing it (the reviewer's case)", function()
      local orc = CQ.raceBit(2)
      -- 1516 handed in, 1517 (Canaga) in the log: 1520 (Seer Ravenfeather,
      -- same step in Thunder Bluff) is closed.
      local ready = readyNames("SHAMAN", 4, 2, { [1516] = true })
      assert.is_number(ready["Call of Earth"])
      local doing = CQ.forNow(data.SHAMAN, ctx(4, orc, { [1516] = true }, { [1517] = true }))
      assert.same({}, names(doing))
      -- 1517 handed in too: the next step is 1518, not 1520.
      assert.equals(1518, readyNames("SHAMAN", 4, 2, { [1516] = true, [1517] = true })["Call of Earth"])
    end)

    it("keeps a troll shaman in the Valley of Trials for Call of Earth (the user's case)", function()
      -- In Durotar (1411): distances there, none to Zephras Isle (2521).
      local function inDurotar(q)
        return q.m == 1411 and 50 or nil
      end
      local troll = CQ.raceBit(8)
      -- At level 1, what comes next is Canaga's at 4, not the island's at 3.
      local _, next1, level1 = CQ.forNow(data.SHAMAN, ctx(1, troll, {}, {}, inDurotar))
      assert.equals(4, level1)
      assert.same({ "Call of Earth 1516" }, names(next1))
      local ready, soon, soonLevel = CQ.forNow(data.SHAMAN, ctx(3, troll, {}, {}, inDurotar))
      assert.same({}, ready)
      assert.equals(4, soonLevel)
      assert.same({ "Call of Earth 1516" }, names(soon)) -- Canaga Earthcaller
      ready = CQ.forNow(data.SHAMAN, ctx(4, troll, {}, {}, inDurotar))
      assert.same({ "Call of Earth 1516" }, names(ready))
    end)
  end)

  it("makes a valid plan: pick it up at the giver, do it, hand it in", function()
    local q = { q = 1525, name = "Call of Fire", level = 12, req = 10, m = 1413, x = 0.5, y = 0.4,
      npc = "Telf Joolam", tm = 1413, tx = 0.6, ty = 0.3, tnpc = "Telf Joolam" }
    local p = CQ.toPlan(q, { L = L })
    assert.is_true(ns.Plan.validate(p))
    assert.is_true(CQ.isClassQuest(p))
    assert.is_false(CQ.isClassQuest({ id = "dungeon-1" }))
    assert.same({ "accept", "complete", "turnin" }, { p.steps[1].type, p.steps[2].type, p.steps[3].type })
    assert.equals(1413, p.steps[1].mapID)
    assert.equals("Telf Joolam", p.steps[1].why:match("Telf Joolam"))
    assert.is_nil(p.steps[2].mapID)
    assert.equals(0.6, p.steps[3].x)
    -- Handed in where nobody knows: the turn-in step has no place.
    q.tm = nil
    assert.is_nil(CQ.toPlan(q, { L = L }).steps[3].mapID)
  end)
end)
