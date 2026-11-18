-- The icon generator (tools/make_icon.lua) and the files it made.

describe("icon picture", function()
  local art = dofile("tools/make_icon.lua")
  local half = art.SIZE / 2

  it("is a round stone: clear in the corners, solid in the middle", function()
    local _, _, _, corner = art.pixel(0, 0, art.STYLES.default)
    local _, _, _, middle = art.pixel(half, half, art.STYLES.default)
    assert.equals(0, corner)
    assert.equals(1, middle)
  end)

  it("glows in the companion's colour on the paw", function()
    -- The main pad of the paw sits a little below the centre.
    local px, py = half, half + math.floor(0.2 * half)
    local r, g, b = art.pixel(px, py, art.STYLES.claude)
    assert.is_true(r > 0.9 and g > 0.45 and g < 0.7 and b < 0.4) -- orange
    r, g, b = art.pixel(px, py, art.STYLES.chatgpt)
    assert.is_true(r > 0.9 and g > 0.9 and b > 0.9) -- white
    -- ...on a black stone, away from the paw.
    r = art.pixel(half - 0.6 * half, half + 0.6 * half * 0.3, art.STYLES.chatgpt)
    assert.is_true(r < 0.35)
  end)

  it("matches the files the addon loads", function()
    for _, style in pairs(art.STYLES) do
      local file = assert(io.open("TrailMate/media/" .. style.file .. ".tga", "rb"))
      local data = file:read("*a")
      file:close()
      assert.equals(18 + art.SIZE * art.SIZE * 4, #data)
      assert.equals(art.SIZE, data:byte(13) + data:byte(14) * 256)
    end
  end)
end)
