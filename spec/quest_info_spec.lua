local helper = require("spec.helper")

describe("QuestInfo", function()
  local ns, QuestInfo
  local info = {
    [2342] = { an = "Patrick Garrett", ac = 4551, dn = "Garrett Family Chest", dm = 196976, dl = 8026,
      tn = "Patrick Garrett", tc = 4551 },
    [99] = { tn = "Wanted Board", tm = 555 },
  }

  before_each(function()
    ns = helper.load()
    QuestInfo = ns.QuestInfo
  end)

  it("says who gives a quest, what it is about and who takes it back (the user asked)", function()
    assert.same({ type = "accept", creature = 4551, who = "Patrick Garrett" }, QuestInfo.about(info, 2342, "accept"))
    assert.same({ type = "complete", who = "Garrett Family Chest", model = 196976, loot = 8026 },
      QuestInfo.about(info, 2342, "complete"))
    assert.same({ type = "turnin", creature = 4551, who = "Patrick Garrett" }, QuestInfo.about(info, 2342, "turnin"))
    -- Handed in at an object: its model.
    assert.same({ type = "turnin", who = "Wanted Board", model = 555 }, QuestInfo.about(info, 99, "turnin"))
    assert.is_nil(QuestInfo.about(info, 99, "complete"))
    assert.is_nil(QuestInfo.about(info, 1, "turnin"))
    assert.is_nil(QuestInfo.about(nil, 2342, "turnin"))
  end)

  it("fills the steps of a route made from the quest log, and keeps what a step has", function()
    local steps = {
      { type = "turnin", questID = 2342 },
      { type = "complete", questID = 2342, who = "Someone", creature = 7 },
      { type = "goto" },
    }
    QuestInfo.fill(steps, info)
    assert.equals("Patrick Garrett", steps[1].who)
    assert.equals(4551, steps[1].creature)
    assert.equals("Someone", steps[2].who)
    assert.equals(7, steps[2].creature)
    assert.is_nil(steps[3].who)
  end)

  it("lets a marked quest no list knows show who takes it back", function()
    assert.same({ type = "turnin", who = "Wanted Board", model = 555 },
      ns.Marked.about(99, "turnin", { info = info }))
  end)
end)
