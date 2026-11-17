local helper = require("spec.helper")

describe("Points", function()
  local P

  before_each(function()
    P = helper.load().Points
  end)

  it("turns 0-100 spawns by zone into map points, skipping unknown zones", function()
    local spawns = { [12] = { { 36.43, 55.89 }, { 10, 20, 3 } }, [99] = { { 50, 50 } }, [7] = { { 150, 10 } } }
    local points = P.fromSpawns(spawns, { [12] = 1429, [7] = 1411 })
    assert.equals(2, #points)
    for _, p in ipairs(points) do
      assert.equals(1429, p.mapID)
    end
    assert.same({}, P.fromSpawns(nil, {}))
    assert.same({}, P.fromSpawns(spawns, nil))
  end)

  it("picks the nearest point on the player's map, else a stable one elsewhere", function()
    local points = {
      { mapID = 2, x = 0.1, y = 0.1 }, { mapID = 1, x = 0.9, y = 0.9 }, { mapID = 1, x = 0.4, y = 0.4 },
    }
    assert.equals(0.4, P.nearest(points, { mapID = 1, x = 0.5, y = 0.5 }).x)
    assert.equals(1, P.nearest(points, { mapID = 3 }).mapID)
    assert.is_nil(P.nearest({}, { mapID = 1 }))
  end)

  it("reads race and class masks, 0 meaning everyone", function()
    assert.is_true(P.hasBit(0, 4))
    assert.is_true(P.hasBit(nil, 4))
    assert.is_true(P.hasBit(4 + 1, 4))
    assert.is_false(P.hasBit(8 + 1, 4))
    assert.is_true(P.hasBit(8, nil))
  end)

  describe("eligible", function()
    local done, log
    local function ctx()
      return {
        level = 33, raceBit = 2, classBit = 4,
        isDone = function(id) return done[id] == true end,
        inLog = function(id) return log[id] == true end,
      }
    end

    before_each(function()
      done, log = {}, {}
    end)

    it("offers a quest of the right level, race and class", function()
      assert.is_true(P.eligible({ questID = 1, requiredLevel = 30, questLevel = 34 }, ctx()))
    end)

    it("leaves out what is in the log, done, too low, too high or for others", function()
      log[1], done[2] = true, true
      local c = ctx()
      assert.is_false(P.eligible({ questID = 1, questLevel = 33 }, c))
      assert.is_false(P.eligible({ questID = 2, questLevel = 33 }, c))
      assert.is_false(P.eligible({ questID = 3, requiredLevel = 34 }, c))
      assert.is_false(P.eligible({ questID = 4, questLevel = 38 }, c))
      assert.is_false(P.eligible({ questID = 5, questLevel = 25 }, c))
      assert.is_false(P.eligible({ questID = 6, questLevel = 33, requiredRaces = 1 }, c))
      assert.is_false(P.eligible({ questID = 7, questLevel = 33, requiredClasses = 8 }, c))
    end)

    it("needs the previous quests of a chain and respects exclusive ones", function()
      local c = ctx()
      assert.is_false(P.eligible({ questID = 10, questLevel = 33, preQuestGroup = { 20, 21 } }, c))
      done[20] = true
      assert.is_false(P.eligible({ questID = 10, questLevel = 33, preQuestGroup = { 20, 21 } }, c))
      done[21] = true
      assert.is_true(P.eligible({ questID = 10, questLevel = 33, preQuestGroup = { 20, 21 } }, c))
      assert.is_false(P.eligible({ questID = 11, questLevel = 33, preQuestSingle = { 30, 31 } }, c))
      done[31] = true
      assert.is_true(P.eligible({ questID = 11, questLevel = 33, preQuestSingle = { 30, 31 } }, c))
      log[40] = true
      assert.is_false(P.eligible({ questID = 12, questLevel = 33, exclusiveTo = { 40 } }, c))
    end)
  end)

  it("recognises a class trainer by flag and title", function()
    assert.is_true(P.isClassTrainer({ npcFlags = 16 + 2, subName = "Hunter Trainer" }, "Hunter"))
    assert.is_false(P.isClassTrainer({ npcFlags = 2, subName = "Hunter Trainer" }, "Hunter"))
    assert.is_false(P.isClassTrainer({ npcFlags = 16, subName = "Pet Trainer" }, "Hunter"))
    assert.is_false(P.isClassTrainer({ npcFlags = 16, subName = "Warrior Trainer" }, "Hunter"))
    assert.is_false(P.isClassTrainer({ npcFlags = 0, subName = "Hunter Trainer" }, "Hunter"))
  end)

  it("keeps NPCs friendly to the player's faction", function()
    assert.is_true(P.friendly("AH", "Horde"))
    assert.is_true(P.friendly("H", "Horde"))
    assert.is_false(P.friendly("A", "Horde"))
    assert.is_true(P.friendly(nil, "Horde"))
  end)
end)
