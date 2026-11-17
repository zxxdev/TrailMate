local helper = require("spec.helper")

describe("Geo", function()
  local Geo
  local PI = math.pi

  before_each(function()
    Geo = helper.load().Geo
  end)

  local function near(expected, actual)
    assert.is_true(math.abs(expected - actual) < 1e-9, ("expected %s, got %s"):format(expected, actual))
  end

  it("measures yards with the map size", function()
    near(500, Geo.distance(0.5, 0.5, 0.5, 0.0, 2000, 1000))
    near(1000, Geo.distance(0.0, 0.5, 0.5, 0.5, 2000, 1000))
    assert.is_nil(Geo.distance(0, 0, 1, 1, nil, nil))
  end)

  it("gives the bearing counter-clockwise from north", function()
    near(0, Geo.bearing(0.5, 0.5, 0.5, 0.1, 1, 1)) -- north (y grows south)
    near(PI / 2, Geo.bearing(0.5, 0.5, 0.1, 0.5, 1, 1)) -- west
    near(PI, Geo.bearing(0.5, 0.5, 0.5, 0.9, 1, 1)) -- south
    near(3 * PI / 2, Geo.bearing(0.5, 0.5, 0.9, 0.5, 1, 1)) -- east
    assert.is_nil(Geo.bearing(0.5, 0.5, 0.5, 0.5, 1, 1))
  end)

  it("uses the real map shape, not the square of the map image", function()
    -- Same map offsets, but the map is four times wider than tall.
    local wide = Geo.bearing(0.5, 0.5, 0.4, 0.4, 4000, 1000)
    near(math.atan2(400, 100), wide)
  end)

  it("turns the arrow with the player's facing", function()
    -- Target to the west while facing west: straight ahead.
    near(0, Geo.arrowRotation(PI / 2, PI / 2))
    -- Target north while facing west: on the right, a quarter turn clockwise.
    near(3 * PI / 2, Geo.arrowRotation(0, PI / 2))
    assert.is_nil(Geo.arrowRotation(nil, 0))
    assert.is_nil(Geo.arrowRotation(0, nil))
  end)

  it("formats distances in metres", function()
    assert.equals("9 m", Geo.formatDistance(10))
    assert.equals("1.8 km", Geo.formatDistance(2000))
    assert.equals("?", Geo.formatDistance(nil))
  end)
end)
