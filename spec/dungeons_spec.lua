local helper = require("spec.helper")

describe("Dungeons", function()
  local ns, Dungeons, data, L

  before_each(function()
    ns = helper.load()
    Dungeons, L = ns.Dungeons, ns.L
    assert(loadfile("TrailMate/data/Dungeons.lua"))("TrailMate", ns)
    data = ns.DUNGEONS
  end)

  local hunter = { faction = "Horde", class = "HUNTER", race = "Orc" }
  local human = { faction = "Alliance", class = "WARRIOR", race = "Human" }

  local function byName(name)
    for _, d in ipairs(data) do
      if d.name == name then
        return d
      end
    end
  end

  local function names(list)
    local out = {}
    for _, e in ipairs(list) do
      out[#out + 1] = e.name or e.quest.name
    end
    return out
  end

  it("knows which dungeon the player is in and what of the quest log is done there (the user's case)", function()
    local sm = Dungeons.here(data, 302)
    assert.equals("Scarlet Monastery", sm.name)
    assert.equals(sm, Dungeons.here(data, nil, "Scarlet Monastery")) -- by the instance's name
    assert.is_nil(Dungeons.here(data, 1434, "Somewhere else"))
    -- In the monastery with Stranglethorn quests only: nothing to do here.
    assert.same({}, Dungeons.toDoHere(sm, { [201] = { complete = false } }))
    -- One of its quests to do, one already done (handed in outside).
    local here = Dungeons.toDoHere(sm, { [1051] = { complete = false }, [1113] = { complete = true } })
    assert.equals(1, #here)
    assert.same({ 1051, "Vorrel's Revenge" }, { here[1].q, here[1].name })
    assert.same({ { c = 3984, n = "Nancy Vishas", d = true } }, here[1].targets)
    -- Who takes it back, for the magnifier once it is done.
    assert.is_string(here[1].tnpc)
    assert.same({}, Dungeons.toDoHere(nil, { [1051] = {} })) -- an unknown dungeon
    -- With the done ones too, marked: the window says when all are done.
    local all = Dungeons.toDoHere(sm, { [1051] = { complete = false }, [1113] = { complete = true } }, true)
    assert.same({ 1051, 1113 }, { all[1].q, all[2].q })
    assert.same({ false, true }, { all[1].done == true, all[2].done == true })
    assert.is_false(Dungeons.allDone(all))
    assert.is_true(Dungeons.allDone({ all[2] }))
    assert.is_false(Dungeons.allDone({}))
  end)

  it("knows who to kill for each quest, to show them (the user's case: Into The Scarlet Monastery)", function()
    local sm = Dungeons.here(data, 302)
    local into = Dungeons.toDoHere(sm, { [1048] = { complete = false } })[1]
    local bosses = {}
    for _, t in ipairs(into.targets) do
      bosses[#bosses + 1] = t.n
      assert.is_true(t.c > 0, t.n) -- each one has its creature, for the model
    end
    assert.same({ "High Inquisitor Whitemane", "Scarlet Commander Mograine", "Herod", "Houndmaster Loksey" }, bosses)
    -- Most quests of the dungeons say what they are about.
    local all, with = 0, 0
    for _, d in ipairs(data) do
      for _, q in ipairs(d.quests) do
        all, with = all + 1, with + (q.targets and 1 or 0)
      end
    end
    assert.is_true(with > all * 0.6, ("%d of %d"):format(with, all))
  end)

  it("has every 1-60 dungeon with an entrance and the level of its enemies", function()
    assert.equals(19, #data)
    for _, d in ipairs(data) do
      assert.is_true(d.min > 1 and d.min <= d.max and d.max <= 62, d.name)
      assert.is_true(#d.entrances >= 1, d.name)
      for _, e in ipairs(d.entrances) do
        assert.is_true(e.m > 0 and e.x > 0 and e.x < 1 and e.y > 0 and e.y < 1, d.name)
      end
      for _, q in ipairs(d.quests) do
        assert.is_true(q.level <= d.max + 5, q.name) -- no Season of Discovery versions
        if q.m then
          assert.is_true(q.x >= 0 and q.x <= 1 and q.y >= 0 and q.y <= 1, q.name)
        end
      end
    end
    -- Forever's own levels: Ragefire Chasm 13-16, The Deadmines 17-21.
    assert.same({ 13, 16, "H" }, { byName("Ragefire Chasm").min, byName("Ragefire Chasm").max,
      byName("Ragefire Chasm").side })
    assert.same({ 17, 21 }, { byName("The Deadmines").min, byName("The Deadmines").max })
  end)

  it("at level 34 a Horde hunter gets Gnomeregan to Razorfen Downs, and Uldaman next (the user's case)", function()
    local now, nextOne = Dungeons.forLevel(data, hunter, 34)
    assert.same({ "Gnomeregan", "Razorfen Kraul", "Scarlet Monastery", "Razorfen Downs" }, names(now))
    assert.equals("Uldaman", nextOne.name)
  end)

  it("never offers a dungeon inside the other faction's capital", function()
    local now = Dungeons.forLevel(data, human, 15)
    assert.same({ "The Deadmines" }, names(now)) -- not Ragefire Chasm, in Orgrimmar
    local horde = Dungeons.forLevel(data, hunter, 26)
    for _, d in ipairs(horde) do
      assert.not_equals("The Stockade", d.name)
    end
  end)

  it("sorts the quests: pick up first, starts inside, later (level or a quest before)", function()
    local gnomeregan = byName("Gnomeregan")
    local ready, inside, later = Dungeons.quests(gnomeregan, hunter, 34)
    assert.same({ "Rig Wars", "Chief Engineer Scooty" }, names(ready))
    -- An escort that starts inside, a machine inside, an item found inside.
    assert.same({ "A Fine Mess", "The Sparklematic 5200!", "Grime-Encrusted Ring" }, names(inside))
    local after = {}
    for _, l in ipairs(later) do
      after[l.quest.name] = l.after
    end
    assert.equals(2842, after["Gnomer-gooooone!"])
    -- No Alliance quests for a Horde hunter.
    for _, q in ipairs(ready) do
      assert.not_equals("A", q.side)
    end
    -- Once Chief Engineer Scooty is handed in, the next one is ready.
    ready = Dungeons.quests(gnomeregan, hunter, 34, function(id) return id == 2842 end)
    assert.same({ "Rig Wars", "Gnomer-gooooone!" }, names(ready))
  end)

  it("keeps class quests for their class", function()
    local d = { name = "Test", min = 20, max = 25, entrances = { { m = 1, x = 0.5, y = 0.5 } }, quests = {
      { q = 1, name = "For hunters", level = 22, classes = 4, m = 1, x = 0.1, y = 0.1 },
      { q = 2, name = "For warriors and paladins", level = 22, classes = 3, m = 1, x = 0.1, y = 0.1 },
      { q = 3, name = "For everyone", level = 22, req = 30, m = 1, x = 0.1, y = 0.1 },
    } }
    local ready, _, later = Dungeons.quests(d, hunter, 22)
    assert.same({ "For hunters" }, names(ready))
    assert.same({ "For everyone" }, names(later))
    assert.equals(30, later[1].level)
  end)

  it("plans the quests, then the entrance, then the hand-ins", function()
    local plan = Dungeons.toPlan(byName("Gnomeregan"), { who = hunter, level = 34, L = L })
    assert.is_true(ns.Plan.validate(plan))
    assert.is_true(Dungeons.isDungeon(plan))
    assert.equals("dungeon-721", plan.id)
    local kinds = {}
    for _, s in ipairs(plan.steps) do
      kinds[#kinds + 1] = s.type
    end
    assert.same({ "accept", "accept", "goto", "turnin", "turnin" }, kinds)
    local entrance = plan.steps[3]
    assert.same({ 1426, 0.243, 0.398 }, { entrance.mapID, entrance.x, entrance.y }) -- Dun Morogh
    assert.equals("Go to the entrance of Gnomeregan", entrance.text)
    assert.equals("From Nogg", plan.steps[1].why)
    assert.is_false(Dungeons.isDungeon({ id = "guide-x" }))
  end)

  it("uses the nearest entrance when there are two", function()
    local brd = byName("Blackrock Depths")
    assert.equals(2, #brd.entrances)
    local far = brd.entrances[1]
    local e = Dungeons.entrance(brd, function(p)
      return p == far and 900 or 100
    end)
    assert.equals(brd.entrances[2], e)
    assert.equals(far, Dungeons.entrance(brd, nil))
  end)
end)
