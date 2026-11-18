local helper = require("spec.helper")

describe("Atlas", function()
  local ns, Atlas, atlas

  before_each(function()
    ns = helper.load()
    Atlas = ns.Atlas
    atlas = Atlas.ensure({})
  end)

  local here = { mapID = 1417, x = 0.5, y = 0.5 }

  it("creates or repairs the saved table", function()
    local db = { atlas = { schema = 99, junk = true } }
    local a = Atlas.ensure(db)
    assert.equals(Atlas.SCHEMA, a.schema)
    assert.same({}, a.npcs)
    db.atlas.npcs = "broken"
    assert.same({}, Atlas.ensure(db).npcs)
  end)

  it("learns where a quest is picked up and turned in", function()
    assert.is_true(Atlas.recordStart(atlas, 677, { title = "Call to Arms", level = 32, npcID = 2700,
      faction = "Horde" }, here))
    assert.is_true(Atlas.recordFinish(atlas, 677, { npcID = 2700 }, { mapID = 1417, x = 0.7, y = 0.3 }))
    local q = atlas.quests[677]
    assert.equals("Call to Arms", q.title)
    assert.equals(2700, q.startNpc)
    assert.same({ mapID = 1417, x = 0.7, y = 0.3 }, Atlas.questTarget(atlas, 677, true, here))
  end)

  it("ignores places that are unknown, outside the map or 0,0 (instances)", function()
    assert.is_false(Atlas.recordStart(atlas, 1, {}, { mapID = 1417, x = 0, y = 0 }))
    assert.is_false(Atlas.recordStart(atlas, 1, {}, { mapID = 1417, x = 1.5, y = 0.2 }))
    assert.is_false(Atlas.recordStart(atlas, 1, {}, { mapID = nil, x = 0.2, y = 0.2 }))
    assert.is_false(Atlas.recordStart(atlas, -3, {}, here))
    assert.is_nil(atlas.quests[1])
  end)

  it("keeps a few distinct objective places and points at the nearest", function()
    Atlas.recordProgress(atlas, 5, { mapID = 1417, x = 0.2, y = 0.2 })
    assert.is_false(Atlas.recordProgress(atlas, 5, { mapID = 1417, x = 0.201, y = 0.2 }))
    Atlas.recordProgress(atlas, 5, { mapID = 1417, x = 0.6, y = 0.6 })
    assert.equals(2, #atlas.quests[5].areas)
    assert.equals(0.6, Atlas.questTarget(atlas, 5, false, here).x)
    for i = 1, Atlas.MAX_AREAS + 5 do
      Atlas.recordProgress(atlas, 6, { mapID = 1417, x = i / 40, y = 0.9 })
    end
    assert.equals(Atlas.MAX_AREAS, #atlas.quests[6].areas)
  end)

  it("offers quests seen before that fit level and faction and are not done", function()
    local function seen(id, level, faction, p)
      Atlas.recordStart(atlas, id, { title = "Q" .. id, level = level, faction = faction }, p or here)
    end
    seen(1, 33, "Horde")
    seen(2, 33, "Alliance")
    seen(3, 40, "Horde")
    seen(4, 20, "Horde")
    seen(5, 33, "Horde", { mapID = 1424, x = 0.5, y = 0.5 })
    seen(6, 34, "Horde")
    seen(7, 33, "Horde")
    local offers = Atlas.offers(atlas, {
      level = 33, faction = "Horde",
      isDone = function(id) return id == 6 end,
      inLog = function(id) return id == 7 end,
    }, here)
    assert.equals(1, #offers)
    assert.equals(1, offers[1].questID)
    assert.same(here, offers[1].target)
  end)

  it("finds the nearest NPC by role, class and faction", function()
    Atlas.recordNpc(atlas, { id = 1, name = "Far hunter trainer", role = "trainer", class = "HUNTER" },
      { mapID = 1417, x = 0.9, y = 0.9 })
    Atlas.recordNpc(atlas, { id = 2, name = "Near hunter trainer", role = "trainer", class = "HUNTER" },
      { mapID = 1417, x = 0.4, y = 0.4 })
    Atlas.recordNpc(atlas, { id = 3, name = "Mage trainer", role = "trainer", class = "MAGE" },
      { mapID = 1417, x = 0.5, y = 0.51 })
    Atlas.recordNpc(atlas, { id = 4, name = "Alliance vendor", role = "vendor", faction = "Alliance" },
      { mapID = 1417, x = 0.5, y = 0.52 })
    Atlas.recordNpc(atlas, { id = 5, name = "Horde vendor", role = "vendor", faction = "Horde" },
      { mapID = 1417, x = 0.1, y = 0.1 })
    local _, name = Atlas.findNpc(atlas, "trainer", "HUNTER", "Horde", here)
    assert.equals("Near hunter trainer", name)
    _, name = Atlas.findNpc(atlas, "vendor", nil, "Horde", here)
    assert.equals("Horde vendor", name)
    assert.is_nil(Atlas.findNpc(atlas, "flight", nil, "Horde", here))
    assert.same({ 5, 0 }, { Atlas.counts(atlas) })
  end)

  it("survives malformed saved data", function()
    atlas.quests[9] = "garbage"
    atlas.quests[10] = { start = { mapID = "x" }, areas = "nope" }
    atlas.npcs[3] = { roles = "nope" }
    assert.is_nil(Atlas.questTarget(atlas, 9, true, here))
    assert.is_nil(Atlas.questTarget(atlas, 10, false, here))
    assert.same({}, Atlas.offers(atlas, { level = 33, isDone = function() return false end,
      inLog = function() return false end }, here))
    assert.is_nil(Atlas.findNpc(atlas, "vendor", nil, nil, here))
  end)
end)
