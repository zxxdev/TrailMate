-- Draws TrailMate's mark for the minimap and the world map: a map pin in the
-- addon's purple, with a light centre and a dark outline. Its tip is the
-- target, so the pin stands above the spot instead of covering it: the
-- game's own quest marks (yellow) stay visible underneath.
--
-- Run it from the repository root (in the VM): lua tools/make_pin.lua

local M = {}

M.SIZE = 64
-- In pixels, top-left origin: the round head and the tip.
M.HEAD_X, M.HEAD_Y, M.HEAD_R = 32, 23, 17
M.TIP_Y = 61
M.HOLE_R = 6.5
M.OUTLINE = 2.5

local PURPLE = { 0.61, 0.48, 0.83 } -- Theme.ACCENT
local DARK = { 0.08, 0.05, 0.12 }
local LIGHT = { 1.00, 0.97, 0.90 }

local function clamp(v)
  return v < 0 and 0 or (v > 1 and 1 or v)
end

local function mix(a, b, t)
  return a + (b - a) * t
end

-- Distance from point to segment.
local function segment(px, py, ax, ay, bx, by)
  local dx, dy = bx - ax, by - ay
  local t = clamp(((px - ax) * dx + (py - ay) * dy) / (dx * dx + dy * dy))
  local x, y = ax + dx * t - px, ay + dy * t - py
  return math.sqrt(x * x + y * y)
end

-- Which side of the line a->b the point is on.
local function side(px, py, ax, ay, bx, by)
  return (bx - ax) * (py - ay) - (by - ay) * (px - ax)
end

--- Signed distance in pixels to the pin's shape: negative inside.
function M.shape(x, y)
  local cx, cy, r = M.HEAD_X, M.HEAD_Y, M.HEAD_R
  local circle = math.sqrt((x - cx) ^ 2 + (y - cy) ^ 2) - r
  -- The two lines from the tip that touch the head.
  local d = M.TIP_Y - cy
  local g = math.acos(r / d)
  local ax, ay = cx - r * math.sin(g), cy + r * math.cos(g)
  local bx, by = cx + r * math.sin(g), ay
  local tx, ty = cx, M.TIP_Y
  local edge = math.min(segment(x, y, tx, ty, ax, ay), segment(x, y, ax, ay, bx, by), segment(x, y, bx, by, tx, ty))
  local s1, s2, s3 = side(x, y, tx, ty, ax, ay), side(x, y, ax, ay, bx, by), side(x, y, bx, by, tx, ty)
  local inside = (s1 >= 0 and s2 >= 0 and s3 >= 0) or (s1 <= 0 and s2 <= 0 and s3 <= 0)
  local triangle = inside and -edge or edge
  return math.min(circle, triangle)
end

--- Colour at pixel (px, py): r, g, b, a from 0 to 1.
function M.pixel(px, py)
  local x, y = px + 0.5, py + 0.5
  local d = M.shape(x, y)
  local alpha = clamp(M.OUTLINE + 0.5 - d)
  if alpha == 0 then
    return DARK[1], DARK[2], DARK[3], 0
  end
  -- Lit from the top left: lighter purple up there, deeper below.
  local shade = 1.12 - 0.35 * clamp((y - 6) / 55) - 0.12 * clamp((x - 15) / 34)
  local r, g, b = clamp(PURPLE[1] * shade), clamp(PURPLE[2] * shade), clamp(PURPLE[3] * shade)
  -- The light centre.
  local hole = math.sqrt((x - M.HEAD_X) ^ 2 + (y - M.HEAD_Y) ^ 2) - M.HOLE_R
  local fill = clamp(0.5 - hole)
  r, g, b = mix(r, LIGHT[1], fill), mix(g, LIGHT[2], fill), mix(b, LIGHT[3], fill)
  -- The dark outline around the whole pin.
  local outline = clamp(d + 0.5)
  r, g, b = mix(r, DARK[1], outline), mix(g, DARK[2], outline), mix(b, DARK[3], outline)
  return r, g, b, alpha
end

local function byte(v)
  return string.char(math.floor(clamp(v) * 255 + 0.5))
end

--- The picture as an uncompressed 32-bit TGA file (rows bottom-up).
function M.tga()
  local s = M.SIZE
  local out = { string.char(0, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0, s % 256, math.floor(s / 256), s % 256,
    math.floor(s / 256), 32, 8) }
  for py = s - 1, 0, -1 do
    local row = {}
    for px = 0, s - 1 do
      local r, g, b, a = M.pixel(px, py)
      row[#row + 1] = byte(b) .. byte(g) .. byte(r) .. byte(a)
    end
    out[#out + 1] = table.concat(row)
  end
  return table.concat(out)
end

if arg and arg[0] and arg[0]:match("make_pin%.lua$") then
  local path = (arg[1] or "TrailMate/media") .. "/Pin.tga"
  local file = assert(io.open(path, "wb"))
  file:write(M.tga())
  file:close()
  print(path)
end

return M
