local helper = require("spec.helper")

describe("Travel", function()
  local T

  before_each(function()
    T = helper.load().Travel
  end)

  -- A simple world: Eastern Kingdoms is continent 0, Kalimdor 1 (yards).
  local arathi = { cont = 0, x = 0, y = 0 }
  local stranglethorn = { cont = 0, x = 0, y = -12000 }
  local hammerfall = { name = "Hammerfall, Arathi", cont = 0, x = 300, y = 100, known = true,
    mapID = 1415, mx = 0.6, my = 0.4 }
  local gromgol = { name = "Grom'gol, Stranglethorn", cont = 0, x = 100, y = -11800, known = true,
    mapID = 1415, mx = 0.4, my = 0.9 }
  local unknownNear = { name = "Somewhere, Stranglethorn", cont = 0, x = 0, y = -11990, known = false }
  local orgrimmar = { name = "Orgrimmar, Durotar", cont = 1, x = 5000, y = 5000, known = true }

  local function kinds(trip)
    local out = {}
    for _, s in ipairs(trip.steps) do
      out[#out + 1] = s.kind
    end
    return table.concat(out, ",")
  end

  it("walks when the zone is close", function()
    local trip = T.plan({ here = arathi, dest = { cont = 0, x = 0, y = -1000 }, nodes = { hammerfall, gromgol } })
    assert.equals("walk", trip.mode)
    assert.equals("walk", kinds(trip))
  end)

  it("flies the user's real case: Arathi to Stranglethorn, Horde", function()
    local trip = T.plan({ here = arathi, dest = stranglethorn, nodes = { hammerfall, gromgol, unknownNear } })
    assert.equals("fly", trip.mode)
    assert.equals("walk,fly,walk", kinds(trip))
    assert.equals("Hammerfall, Arathi", trip.steps[1].to.name)
    assert.equals("Grom'gol, Stranglethorn", trip.steps[2].to.name)
    assert.is_false(trip.steps[2].confirmed)
    assert.is_true(trip.cost < 12000 / T.RUN)
  end)

  it("never flies to a point the player has not learned", function()
    local trip = T.plan({ here = arathi, dest = stranglethorn, nodes = { hammerfall, unknownNear } })
    assert.equals("walk", trip.mode)
  end)

  it("does not use a route seen closed, and marks a route seen open as confirmed", function()
    local closed = T.plan({ here = arathi, dest = stranglethorn, nodes = { hammerfall, gromgol },
      reach = function() return false end })
    assert.equals("walk", closed.mode)
    local open = T.plan({ here = arathi, dest = stranglethorn, nodes = { hammerfall, gromgol },
      reach = function() return true end })
    assert.is_true(open.steps[2].confirmed)
  end)

  it("uses the hearthstone when it is ready and lands closer", function()
    local hearth = { name = "Grom'gol", cont = 0, x = 100, y = -11800, ready = true }
    local trip = T.plan({ here = arathi, dest = stranglethorn, nodes = {}, hearth = hearth })
    assert.equals("hearth", trip.mode)
    assert.equals("hearth,walk", kinds(trip))
    hearth.ready = false
    assert.equals("walk", T.plan({ here = arathi, dest = stranglethorn, nodes = {}, hearth = hearth }).mode)
  end)

  it("does not spend the hearthstone to save a few seconds (the user's real case)", function()
    -- Standing near Hammerfall, hearthstone bound in Hammerfall: walk to the flight master.
    local hearth = { name = "Hammerfall", cont = 0, x = 300, y = 100, ready = true }
    local trip = T.plan({ here = { cont = 0, x = 0, y = 0 }, dest = stranglethorn, nodes = { hammerfall, gromgol },
      hearth = hearth })
    assert.equals("fly", trip.mode)
    assert.equals("walk,fly,walk", kinds(trip))
  end)

  it("says ship or zeppelin for another continent, with the nearest known flight master", function()
    local trip = T.plan({ here = arathi, dest = { cont = 1, x = 6000, y = 6000 },
      nodes = { hammerfall, orgrimmar } })
    assert.equals("ship", trip.mode)
    assert.equals("Hammerfall, Arathi", trip.steps[1].via.name)
  end)

  it("takes the zeppelin from Orgrimmar to Grom'gol (the user's real case)", function()
    -- In Orgrimmar, hearthstone bound in Hammerfall (far from Stranglethorn),
    -- no flights known on the other continent.
    local tower = { name = "Durotar tower", cont = 1, x = 5000, y = 5300, dock = true }
    local gromDock = { name = "Grom'gol dock", cont = 0, x = 100, y = -11700, dock = true }
    local hearth = { name = "Hammerfall", cont = 0, x = 300, y = 100, ready = true }
    local ships = { { kind = "zeppelin", a = tower, b = gromDock } }
    local trip = T.plan({ here = { cont = 1, x = 5000, y = 5000 }, dest = stranglethorn, nodes = {},
      hearth = hearth, ships = ships })
    assert.equals("ship", trip.mode)
    assert.equals("walk,ship,walk", kinds(trip))
    assert.equals("Durotar tower", trip.steps[1].to.name)
    assert.equals("Grom'gol dock", trip.steps[2].to.name)
    assert.equals("zeppelin", trip.steps[2].ship)
    -- Either way round.
    local back = T.plan({ here = stranglethorn, dest = { cont = 1, x = 5000, y = 5000 }, nodes = {}, ships = ships })
    assert.equals("ship", back.mode)
    assert.equals("Durotar tower", back.steps[2].to.name)
  end)

  it("takes the hearthstone across continents when it is bound there", function()
    local hearth = { name = "Orgrimmar", cont = 1, x = 5000, y = 5000, ready = true }
    local trip = T.plan({ here = arathi, dest = { cont = 1, x = 5200, y = 5000 }, nodes = {}, hearth = hearth })
    assert.equals("hearth", trip.mode)
  end)

  it("goes faster with a mount and returns nil without positions", function()
    local foot = T.plan({ here = arathi, dest = stranglethorn, nodes = {} })
    local mounted = T.plan({ here = arathi, dest = stranglethorn, nodes = {}, speed = T.MOUNT })
    assert.is_true(mounted.cost < foot.cost)
    assert.is_nil(T.plan({ here = nil, dest = stranglethorn }))
    assert.equals("4 min", T.minutes(240))
  end)
end)

describe("Atlas flights and binds", function()
  it("remembers open routes per flight master and where the hearthstone lands", function()
    local ns = helper.load()
    local atlas = ns.Atlas.ensure({})
    assert.is_nil(ns.Atlas.reach(atlas, "Hammerfall", "Grom'gol"))
    ns.Atlas.recordFlights(atlas, "Hammerfall", { "Grom'gol", "Tarren Mill" })
    assert.is_true(ns.Atlas.reach(atlas, "Hammerfall", "Grom'gol"))
    assert.is_false(ns.Atlas.reach(atlas, "Hammerfall", "Kargath"))
    ns.Atlas.recordBind(atlas, "Hammerfall", { mapID = 1417, x = 0.74, y = 0.33 })
    assert.same({ mapID = 1417, x = 0.74, y = 0.33 }, ns.Atlas.bind(atlas, "Hammerfall"))
    assert.is_nil(ns.Atlas.bind(atlas, "Nowhere"))
  end)
end)
