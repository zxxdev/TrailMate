local helper = require("spec.helper")

describe("Trainer.advise", function()
  local ns, L

  before_each(function()
    ns = helper.load()
    L = ns.L
  end)

  local services = {
    { index = 1, name = "Raptor Strike (Rank 2)", spellID = 14260, cost = 100, status = "available" },
    { index = 2, name = "Track Beasts", spellID = 1494, cost = 50, status = "available" },
    { index = 3, name = "Rastrear humanoides", cost = 50, status = "available" },
    { index = 4, name = "Aspect of the Hawk", cost = 200, status = "unavailable", reqLevel = 10 },
    { index = 5, name = "Serpent Sting", cost = 80, status = "used" },
  }

  local function byIndex(results)
    local out = {}
    for _, r in ipairs(results) do
      out[r.index] = r
    end
    return out
  end

  it("skips hunter tracking when the player asked to, by id or by name", function()
    local results, spend = ns.Trainer.advise(services, {
      class = "HUNTER", level = 8, money = 10000, prefs = { skipTracking = true },
    }, L)
    local r = byIndex(results)
    assert.equals("learn", r[1].verdict)
    assert.equals("skip", r[2].verdict)
    assert.equals("skip", r[3].verdict)
    assert.equals("later", r[4].verdict)
    assert.matches("level 10", r[4].reason)
    assert.is_nil(r[5])
    assert.equals(100, spend)
  end)

  it("learns tracking when the player did not opt out", function()
    local r = byIndex((ns.Trainer.advise(services, { class = "HUNTER", level = 8, money = 10000 }, L)))
    assert.equals("learn", r[2].verdict)
  end)

  it("ignores a spell in every rank, even before it is available", function()
    local list = {
      { index = 1, name = "Aspect of the Monkey", baseName = "Aspect of the Monkey", cost = 10, status = "available" },
      { index = 2, name = "Aspect of the Hawk (Rank 2)", baseName = "Aspect of the Hawk", cost = 10,
        status = "available" },
      { index = 3, name = "Aspect of the Hawk (Rank 3)", baseName = "Aspect of the Hawk", cost = 10,
        status = "unavailable", reqLevel = 20 },
    }
    local results, spend = ns.Trainer.advise(list, {
      class = "HUNTER", level = 12, money = 1000, prefs = { ignored = { ["Aspect of the Hawk"] = true } },
    }, L)
    local r = byIndex(results)
    assert.equals("learn", r[1].verdict)
    assert.equals("skip", r[2].verdict)
    assert.equals("skip", r[3].verdict)
    assert.matches("ignore", r[3].reason)
    assert.equals(10, spend)
  end)

  it("remembers the trainer and only announces what unlocks at a new level", function()
    local memory = {}
    ns.Trainer.remember(memory, {
      { name = "Serpent Sting (Rank 2)", baseName = "Serpent Sting", status = "unavailable", reqLevel = 10 },
      { name = "Aspect of the Hawk (Rank 2)", baseName = "Aspect of the Hawk", status = "unavailable",
        reqLevel = 18 },
      { name = "Scorpid Sting", baseName = "Scorpid Sting", status = "unavailable", reqLevel = 10 },
      { name = "Arcane Shot", baseName = "Arcane Shot", status = "available", reqLevel = 6 },
    })
    local ignored = { ["Scorpid Sting"] = true }
    assert.same({ "Serpent Sting (Rank 2)" }, ns.Trainer.newAtLevel(memory, 10, ignored))
    assert.same({}, ns.Trainer.newAtLevel(memory, 11, ignored))
    -- Once the trainer shows it as learned, it is forgotten.
    ns.Trainer.remember(memory, { { name = "Arcane Shot", status = "used" } })
    assert.is_nil(memory["Arcane Shot"])
  end)

  it("never spends the reserve", function()
    local r = byIndex((ns.Trainer.advise(services, {
      class = "HUNTER", level = 8, money = 160, prefs = { reserve = 50 },
    }, L)))
    assert.equals("learn", r[1].verdict)
    assert.equals("later", r[2].verdict)
    assert.matches("reserve", r[2].reason)
  end)
end)

describe("Bags", function()
  local ns, L

  before_each(function()
    ns = helper.load()
    L = ns.L
  end)

  local function verdict(item, ctx)
    return (ns.Bags.adviseItem(item, ctx or {}, L))
  end

  it("sells grey junk with a vendor price", function()
    assert.equals("sell", verdict({ itemID = 1, quality = 0, sellPrice = 5 }))
    assert.equals("keep", verdict({ itemID = 1, quality = 0, sellPrice = 0 }))
  end)

  it("keeps quest items, consumables and the keep list", function()
    assert.equals("keep", verdict({ itemID = 2, quality = 1, isQuest = true, sellPrice = 9 }))
    assert.equals("keep", verdict({ itemID = 3, quality = 1, classID = 0, sellPrice = 9 }))
    assert.equals("keep", verdict({ itemID = 4, quality = 0, sellPrice = 9 }, { prefs = { keep = { [4] = true } } }))
  end)

  it("sends unbound greens and trade goods to the auction house when there is one", function()
    local green = { itemID = 5, quality = 2, classID = 4, equipLoc = "INVTYPE_CHEST", isBound = false, sellPrice = 30 }
    assert.equals("auction", verdict(green))
    assert.equals("keep", verdict(green, { auctionAvailable = false }))
    assert.equals("auction", verdict({ itemID = 6, quality = 1, classID = 7, sellPrice = 2 }))
  end)

  it("sells bound gear below what is worn, keeps possible upgrades", function()
    local worse = { itemID = 7, quality = 1, classID = 4, equipLoc = "INVTYPE_FEET", isBound = true,
      itemLevel = 8, equippedLevel = 12, sellPrice = 10 }
    assert.equals("sell", verdict(worse))
    worse.itemLevel = 15
    assert.equals("keep", verdict(worse))
  end)

  it("adds up the vendor value of what to sell", function()
    local _, value = ns.Bags.advise({
      { itemID = 1, quality = 0, sellPrice = 5, count = 3 },
      { itemID = 2, quality = 0, sellPrice = 10, count = 1 },
      { itemID = 3, quality = 1, classID = 0, sellPrice = 99 },
    }, {}, L)
    assert.equals(25, value)
  end)

  it("says when to go back to a vendor", function()
    assert.is_true(ns.Bags.shouldReturn(2, {}))
    assert.is_false(ns.Bags.shouldReturn(3, {}))
    assert.is_true(ns.Bags.shouldReturn(5, { minFreeSlots = 5 }))
  end)
end)

describe("State", function()
  local ns, L

  before_each(function()
    ns = helper.load()
    L = ns.L
  end)

  it("keeps only whitelisted fields, so names cannot leak", function()
    local snap = ns.State.build({
      class = "HUNTER", level = 11, money = 12345, mapID = 1429, x = 0.5, y = 0.6,
      name = "Somebody", realm = "Somewhere", guild = "Someguild",
      quests = { { questID = 33, title = "Wolves", complete = true, giver = "Someone" } },
      items = { { itemID = 9, count = 2, quality = 0, link = "|Hitem:9|h" } },
      bagsFree = 3, bagsTotal = 16,
    }, 1000)
    assert.is_true(ns.State.validate(snap))
    assert.is_nil(snap.name)
    assert.is_nil(snap.realm)
    assert.is_nil(snap.guild)
    assert.is_nil(snap.quests[1].giver)
    assert.is_nil(snap.bags.items[1].link)
    assert.equals(1429, snap.position.mapID)
  end)

  it("rejects snapshots with unknown fields or the wrong schema", function()
    local snap = ns.State.build({ class = "MAGE", level = 3 })
    snap.name = "x"
    assert.is_nil((ns.State.validate(snap)))
    assert.is_nil((ns.State.validate({ schema = 99 })))
  end)

  it("summarises the character", function()
    local lines = ns.State.summary(ns.State.build({ class = "HUNTER", level = 11, money = 12345,
      xp = 50, xpMax = 200, bagsFree = 3, bagsTotal = 16 }), L)
    local all = table.concat(lines, "\n")
    assert.matches("level 11", all)
    assert.matches("XP 25%%", all)
    assert.matches("1g 23s 45c", all)
    assert.matches("3 of 16", all)
  end)
end)
