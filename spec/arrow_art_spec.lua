-- The arrow picture generator (tools/make_arrow.lua) and the file it made.

describe("arrow picture", function()
  local art = dofile("tools/make_arrow.lua")

  it("is solid inside the arrow, clear outside and soft only at the edge", function()
    local _, _, _, inside = art.pixel(0, 10)
    local _, _, _, outside = art.pixel(25, 25)
    local _, _, _, edge = art.pixel(0, 27) -- right on the tip
    assert.equals(1, inside)
    assert.equals(0, outside)
    assert.is_true(edge > 0 and edge < 1)
  end)

  it("has a dark outline and a lit and a shaded half", function()
    local r = art.pixel(0, 26)
    local left = art.pixel(-6, 0)
    local right = art.pixel(6, 0)
    assert.is_true(r < 0.3) -- outline near the tip
    assert.is_true(left > right)
  end)

  it("draws each cell at its own angle, counter-clockwise like the game", function()
    -- Cell 32 is a quarter turn: the tip points left (west).
    local cell = art.CELL
    local x0, y0 = (32 % art.COLS) * cell, math.floor(32 / art.COLS) * cell
    local _, _, _, tip = art.at(x0 + cell / 2 - 22, y0 + cell / 2)
    local _, _, _, back = art.at(x0 + cell / 2 + 22, y0 + cell / 2)
    assert.equals(1, tip)
    assert.equals(0, back)
  end)

  it("matches the file the addon loads", function()
    local file = assert(io.open("TrailMate/media/Arrow.tga", "rb"))
    local data = file:read("*a")
    file:close()
    assert.equals(18 + art.WIDTH * art.HEIGHT * 4, #data)
    local w = data:byte(13) + data:byte(14) * 256
    local h = data:byte(15) + data:byte(16) * 256
    assert.equals(art.WIDTH, w)
    assert.equals(art.HEIGHT, h)
    assert.equals(32, data:byte(17))
  end)
end)
