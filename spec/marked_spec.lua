local helper = require("spec.helper")

describe("Marked", function()
  local ns, Marked

  before_each(function()
    ns = helper.load()
    Marked = ns.Marked
  end)

  local function ctx(over)
    local c = { ours = 10, following = 10, now = 100, quietUntil = 50, questLog = { [10] = {}, [11] = {} } }
    for k, v in pairs(over or {}) do
      c[k] = v
    end
    return c
  end

  describe("isPlayerMark", function()
    it("counts a quest of the log the player clicked", function()
      assert.is_true(Marked.isPlayerMark(11, ctx()))
    end)

    it("ignores TrailMate's own choice and the guide's quest", function()
      assert.is_false(Marked.isPlayerMark(10, ctx()))
      assert.is_false(Marked.isPlayerMark(11, ctx({ ours = 11 })))
      assert.is_false(Marked.isPlayerMark(11, ctx({ ours = 12, following = 11 })))
    end)

    it("ignores nothing followed and quests not in the log", function()
      assert.is_false(Marked.isPlayerMark(nil, ctx()))
      assert.is_false(Marked.isPlayerMark(0, ctx()))
      assert.is_false(Marked.isPlayerMark(12, ctx()))
    end)

    it("ignores the game's own choice right after a quest event or the login", function()
      assert.is_false(Marked.isPlayerMark(11, ctx({ quietUntil = 101 })))
      assert.is_true(Marked.isPlayerMark(11, ctx({ quietUntil = 100 })))
    end)

    it("still works when the client gives no time", function()
      assert.is_true(Marked.isPlayerMark(11, ctx({ now = false, quietUntil = 200 })))
    end)
  end)

  describe("view", function()
    it("says what is left: doing it, then handing it in", function()
      local L = ns.L
      assert.same({ kind = "complete", text = L["Do: "] .. "Wolves" },
        Marked.view(11, "Wolves", { [11] = { complete = false } }, L))
      assert.same({ kind = "turnin", text = L["Turn in: "] .. "Wolves" },
        Marked.view(11, "Wolves", { [11] = { complete = true } }, L))
    end)

    it("names a quest by number when the game has not loaded its name", function()
      local L = ns.L
      assert.equals(L["Do: "] .. L["Quest %d"]:format(11), Marked.view(11, nil, { [11] = {} }, L).text)
    end)

    it("is nil once the quest has left the log", function()
      assert.is_nil(Marked.view(11, "Wolves", {}, ns.L))
    end)
  end)

  describe("about", function()
    local data = {
      dungeons = { { quests = {
        { q = 2342, tnpc = "Patrick Garrett", targets = { { n = "Garrett Family Chest", l = 8026, m = 196976 } } },
        { q = 2283, tnpc = "Dran Droffers", targets = { { c = 4844, n = "Shadowforge Surveyor", d = true } } },
        { q = 99, tnpc = "Wanted Board", tmodel = 555 },
      } } },
      guides = { { steps = {
        { q = 2283, t = "turnin", cid = 6986, npc = "Dran Droffers" },
        { q = 50, t = "complete", tgt = "Wolf", cid = 69 },
      } } },
      classQuests = { { q = 70, tnpc = "Uzzek", tcid = 5810 } },
    }

    it("shows the object of a dungeon quest with the item looted from it (the user's case)", function()
      assert.same({ type = "complete", who = "Garrett Family Chest", loot = 8026, model = 196976 },
        Marked.about(2342, "complete", data))
    end)

    it("shows the creature to kill, and who takes it back once done", function()
      assert.same({ type = "complete", creature = 4844, who = "Shadowforge Surveyor", drop = true },
        Marked.about(2283, "complete", data))
      -- The dungeon list has no model for him; the guide has.
      assert.same({ type = "turnin", creature = 6986, who = "Dran Droffers" }, Marked.about(2283, "turnin", data))
      assert.same({ type = "complete", creature = 69, who = "Wolf" }, Marked.about(50, "complete", data))
      assert.same({ type = "turnin", creature = 5810, who = "Uzzek" }, Marked.about(70, "turnin", data))
    end)

    it("shows an object a quest is handed in at, as its model (the user asked)", function()
      assert.same({ type = "turnin", who = "Wanted Board", model = 555 }, Marked.about(99, "turnin", data))
    end)

    it("is nil for a quest no list knows", function()
      assert.is_nil(Marked.about(999, "complete", data))
      assert.is_nil(Marked.about(999, "complete", {}))
    end)
  end)
end)
