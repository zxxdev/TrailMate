-- Draws TrailMate's arrow picture: TrailMate/media/Arrow.tga.
--
-- Same idea as TomTom's arrow: instead of rotating one picture in the game
-- (which looks jagged), the file holds the arrow already drawn at 128
-- angles, each smoothed here. The game only picks the right cell.
--
-- The arrow is drawn white and grey (a lit and a shaded half, like a bevel)
-- with a dark outline, so the game can tint it with the addon's colours.
--
-- Run it from the repository root (in the VM): lua tools/make_arrow.lua
-- The numbers below must match game/Arrow.lua (CELL, COLS, ROWS).

local M = {}

M.CELL, M.COLS, M.ROWS = 64, 16, 8
M.FRAMES = M.COLS * M.ROWS
M.WIDTH, M.HEIGHT = M.CELL * M.COLS, M.CELL * M.ROWS

-- The arrow pointing up, in pixels from the cell centre, y up: tip, right
-- wing, notch, left wing.
-- A shallow notch keeps the tip the only sharp point, so it reads at a glance.
local SHAPE = { { 0, 27 }, { 18, -20 }, { 0, -8 }, { -18, -20 } }
local OUTLINE = 2 -- pixels of dark border
local DARK = { 0.08, 0.06, 0.03 }

local function clamp(v)
  return v < 0 and 0 or (v > 1 and 1 or v)
end

-- Distance from (x, y) to the segment a-b.
local function segment(x, y, a, b)
  local dx, dy = b[1] - a[1], b[2] - a[2]
  local t = clamp(((x - a[1]) * dx + (y - a[2]) * dy) / (dx * dx + dy * dy))
  local ex, ey = x - (a[1] + t * dx), y - (a[2] + t * dy)
  return math.sqrt(ex * ex + ey * ey)
end

--- Signed distance to the arrow's edge: positive inside, negative outside.
function M.distance(x, y)
  local nearest, inside = math.huge, false
  local n = #SHAPE
  for i = 1, n do
    local a, b = SHAPE[i], SHAPE[i % n + 1]
    nearest = math.min(nearest, segment(x, y, a, b))
    -- Crossing test: does a ray to the right cross this edge?
    if (a[2] > y) ~= (b[2] > y) and x < a[1] + (y - a[2]) * (b[1] - a[1]) / (b[2] - a[2]) then
      inside = not inside
    end
  end
  return inside and nearest or -nearest
end

--- Colour of the up-pointing arrow at (x, y): r, g, b, a from 0 to 1.
function M.pixel(x, y)
  local d = M.distance(x, y)
  local alpha = clamp(d + 0.5) -- one pixel of soft edge: no jagged steps
  -- Left half lit, right half in shade, blended across the ridge.
  local shade = 0.86 - 0.14 * math.max(-1, math.min(1, x))
  shade = shade * (0.88 + 0.12 * clamp((y + 22) / 49)) -- brighter towards the tip
  local body = clamp(d - OUTLINE + 0.5)
  local r = DARK[1] + (shade - DARK[1]) * body
  local g = DARK[2] + (shade - DARK[2]) * body
  local b = DARK[3] + (shade - DARK[3]) * body
  return r, g, b, alpha
end

--- The colour of one pixel of the whole picture, top-left origin.
function M.at(px, py)
  local cell = M.CELL
  local col, row = math.floor(px / cell), math.floor(py / cell)
  local angle = (row * M.COLS + col) * 2 * math.pi / M.FRAMES -- counter-clockwise
  local half = cell / 2
  local x = px % cell + 0.5 - half
  local y = half - (py % cell + 0.5)
  -- Turn the pixel back by the frame's angle and look at the upright arrow.
  local c, s = math.cos(angle), math.sin(angle)
  return M.pixel(x * c + y * s, -x * s + y * c)
end

local function byte(v)
  return string.char(math.floor(clamp(v) * 255 + 0.5))
end

--- The picture as an uncompressed 32-bit TGA file (rows bottom-up).
function M.tga()
  local w, h = M.WIDTH, M.HEIGHT
  local out = {
    string.char(0, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0, w % 256, math.floor(w / 256), h % 256, math.floor(h / 256), 32, 8),
  }
  for py = h - 1, 0, -1 do
    local row = {}
    for px = 0, w - 1 do
      local r, g, b, a = M.at(px, py)
      row[#row + 1] = byte(b) .. byte(g) .. byte(r) .. byte(a)
    end
    out[#out + 1] = table.concat(row)
  end
  return table.concat(out)
end

if arg and arg[0] and arg[0]:match("make_arrow%.lua$") then
  local path = arg[1] or "TrailMate/media/Arrow.tga"
  local file = assert(io.open(path, "wb"))
  file:write(M.tga())
  file:close()
  print(("%s: %dx%d, %d frames"):format(path, M.WIDTH, M.HEIGHT, M.FRAMES))
end

return M
