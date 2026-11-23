-- The flight mark's pictures (tools/make_ring.lua) and the files it made.

describe("flight mark pictures", function()
  local art = dofile("tools/make_ring.lua")

  it("is a thin gold ring with a dark edge, clear inside and outside", function()
    local c = art.CENTER
    local _, _, _, inside = art.ring(c, c)
    local _, _, _, corner = art.ring(0, 0)
    assert.equals(0, inside)
    assert.equals(0, corner)
    -- The ring's middle is gold; just past its gold, the dark edge.
    local r, g, b, a = art.ring(c + art.RING_R, c)
    assert.is_true(r > 0.9 and g > 0.7 and b < 0.4 and a == 1)
    r, g = art.ring(c + art.RING_R + art.RING_HALF + 1, c)
    assert.is_true(r < 0.5 and g < 0.4)
  end)

  it("glows softly and fades to nothing before the picture's edge (no square)", function()
    local c = art.CENTER
    local _, _, _, at = art.glow(c + art.GLOW_R, c)
    local _, _, _, mid = art.glow(c + art.GLOW_R - art.GLOW_SPREAD, c)
    assert.is_true(at > 0.95)
    assert.is_true(mid > 0.2 and mid < 0.5)
    for _, p in ipairs({ { 0, 0 }, { 0, c }, { c, 0 }, { art.SIZE - 1, c } }) do
      local _, _, _, a = art.glow(p[1], p[2])
      assert.equals(0, a)
    end
  end)

  it("matches the files the addon loads", function()
    for name, pixel in pairs({ Ring = art.ring, Glow = art.glow }) do
      local file = assert(io.open("TrailMate/media/" .. name .. ".tga", "rb"))
      local data = file:read("*a")
      file:close()
      assert.equals(art.tga(pixel), data)
    end
  end)
end)
