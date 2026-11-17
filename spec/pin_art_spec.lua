-- The map pin generator (tools/make_pin.lua) and the file it made.

describe("map pin picture", function()
  local art = dofile("tools/make_pin.lua")

  it("is a purple pin with a light centre, clear around it", function()
    local _, _, _, corner = art.pixel(0, 0)
    assert.equals(0, corner)
    -- The centre of the head is light, the head around it purple.
    local r, g, b, a = art.pixel(art.HEAD_X, art.HEAD_Y)
    assert.is_true(r > 0.9 and g > 0.9 and b > 0.85 and a == 1)
    r, g, b = art.pixel(art.HEAD_X, art.HEAD_Y + 11)
    assert.is_true(b > r and r > g and g < 0.6)
  end)

  it("ends in a tip at the bottom middle: the target", function()
    local _, _, _, a = art.pixel(art.HEAD_X, art.TIP_Y - 2)
    assert.equals(1, a)
    local _, _, _, side = art.pixel(art.HEAD_X - 8, art.TIP_Y - 2)
    assert.equals(0, side)
  end)

  it("matches the file the addon loads", function()
    local file = assert(io.open("TrailMate/media/Pin.tga", "rb"))
    local data = file:read("*a")
    file:close()
    assert.equals(art.tga(), data)
  end)
end)
