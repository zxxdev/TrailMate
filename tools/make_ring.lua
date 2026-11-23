-- Draws the two pictures of the flight map's mark (the point TrailMate says
-- to fly to): a thin gold ring with a dark edge, round the point's icon, and
-- a soft gold glow behind it that beats. TrailMate draws its own because the
-- game's glow and ping pictures are drawn on black, which showed as squares
-- and grey shadows on the parchment (seen in the game), and growing a small
-- picture goes in whole-pixel steps: only the glow's transparency moves, and
-- that is smooth.
--
-- Run it from the repository root (in the VM): lua tools/make_ring.lua

local M = {}

M.SIZE = 64
M.CENTER = 32
-- The ring: its middle radius and half its width, and the dark edge on both
-- sides, in pixels of the 64-pixel picture.
M.RING_R, M.RING_HALF, M.EDGE = 23, 2, 1.5
-- The glow: brightest at the ring, fading inwards and outwards.
M.GLOW_R, M.GLOW_SPREAD = 22, 8

local GOLD = { 1.00, 0.80, 0.22 }
local DARK = { 0.23, 0.15, 0.00 }

local function clamp(v)
  return v < 0 and 0 or (v > 1 and 1 or v)
end

local function mix(a, b, t)
  return a + (b - a) * t
end

local function radius(px, py)
  local x, y = px + 0.5 - M.CENTER, py + 0.5 - M.CENTER
  return math.sqrt(x * x + y * y)
end

--- The ring at pixel (px, py): r, g, b, a from 0 to 1.
function M.ring(px, py)
  local d = math.abs(radius(px, py) - M.RING_R) -- from the ring's middle
  local alpha = clamp(M.RING_HALF + M.EDGE + 0.5 - d)
  if alpha == 0 then
    return DARK[1], DARK[2], DARK[3], 0
  end
  -- Gold in the middle, the dark edge on both sides (antialiased).
  local edge = clamp(d - M.RING_HALF + 0.5)
  return mix(GOLD[1], DARK[1], edge), mix(GOLD[2], DARK[2], edge), mix(GOLD[3], DARK[3], edge), alpha
end

--- The glow at pixel (px, py): gold, with a soft transparency.
function M.glow(px, py)
  local d = (radius(px, py) - M.GLOW_R) / M.GLOW_SPREAD
  -- Tapered to nothing before the picture's edge: no square, no hard rim.
  local alpha = math.exp(-d * d) * clamp((M.CENTER - 1 - radius(px, py)) / 5)
  return GOLD[1], GOLD[2], GOLD[3], alpha
end

local function byte(v)
  return string.char(math.floor(clamp(v) * 255 + 0.5))
end

--- A picture (M.ring or M.glow) as an uncompressed 32-bit TGA file (rows
--- bottom-up).
function M.tga(pixel)
  local s = M.SIZE
  local out = { string.char(0, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0, s % 256, math.floor(s / 256), s % 256,
    math.floor(s / 256), 32, 8) }
  for py = s - 1, 0, -1 do
    local row = {}
    for px = 0, s - 1 do
      local r, g, b, a = pixel(px, py)
      row[#row + 1] = byte(b) .. byte(g) .. byte(r) .. byte(a)
    end
    out[#out + 1] = table.concat(row)
  end
  return table.concat(out)
end

if arg and arg[0] and arg[0]:match("make_ring%.lua$") then
  local dir = arg[1] or "TrailMate/media"
  for name, pixel in pairs({ Ring = M.ring, Glow = M.glow }) do
    local path = dir .. "/" .. name .. ".tga"
    local file = assert(io.open(path, "wb"))
    file:write(M.tga(pixel))
    file:close()
    print(path)
  end
end

return M
