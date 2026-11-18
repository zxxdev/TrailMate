local helper = require("spec.helper")

describe("Hubs", function()
  local Hubs, data

  before_each(function()
    local ns = helper.load()
    Hubs = ns.Hubs
    assert(loadfile("TrailMate/data/Hubs.lua"))("TrailMate", ns)
    data = ns.HUBS
  end)

  local none = {
    inLog = function() return false end,
    isDone = function() return false end,
  }

  it("finds Grom'gol for a level 34 Horde hunter (the user's case)", function()
    local hubs = Hubs.forZone(data, 1434, "Horde", 34)
    assert.equals("Grom'gol Base Camp", hubs[1].name)
    assert.equals("Nesingwary's Expedition", hubs[2].name) -- for both factions
    -- Not for the Alliance, nor far below the hub's levels.
    assert.equals(1, #Hubs.forZone(data, 1434, "Alliance", 34))
    assert.equals(0, #Hubs.forZone(data, 1434, "Horde", 20))
  end)

  it("lists the quests still to pick up, optional ones last", function()
    local grom = Hubs.forZone(data, 1434, "Horde", 34)[1]
    local pending = Hubs.pending(grom, none)
    assert.same({ 581, false }, { pending[1].questID, pending[1].optional })
    assert.same({ 629, true }, { pending[#pending].questID, pending[#pending].optional })
    -- Taken or done quests are not listed again.
    local some = {
      inLog = function(id) return id == 581 end,
      isDone = function(id) return id == 596 end,
    }
    assert.equals(638, Hubs.pending(grom, some)[1].questID)
  end)

  it("keeps the shipped data well formed", function()
    for _, h in ipairs(data) do
      assert.is_number(h.mapID)
      assert.is_string(h.name)
      assert.is_true(h.x >= 0 and h.x <= 1 and h.y >= 0 and h.y <= 1)
      assert.is_true(h.min <= h.max)
      for _, id in ipairs(h.pickup or {}) do
        assert.is_true(id > 0 and id == math.floor(id))
      end
    end
  end)
end)
