-- Draws TrailMate's icon: a round, worn stone (cosy, like a hearthstone)
-- with a carved paw print that glows: the companion at your side.
--
-- One picture per companion, so the icon says who is talking:
--   Icon.tga         no AI: warm gold glow on warm stone
--   Icon-claude.tga  Claude: orange glow
--   Icon-chatgpt.tga ChatGPT: white glow on a black stone
--
-- Run it from the repository root (in the VM): lua tools/make_icon.lua

local M = {}

M.SIZE = 128

M.STYLES = {
  default = { file = "Icon", stone = { 0.50, 0.44, 0.38 }, glow = { 1.00, 0.80, 0.38 } },
  claude = { file = "Icon-claude", stone = { 0.50, 0.42, 0.36 }, glow = { 1.00, 0.52, 0.24 } },
  chatgpt = { file = "Icon-chatgpt", stone = { 0.17, 0.17, 0.18 }, glow = { 0.97, 0.97, 0.97 } },
}

local DARK = { 0.09, 0.07, 0.06 }
-- Light from the top left, slightly in front.
local LX, LY, LZ = -0.48, 0.55, 0.68

-- Paw print in units of the icon radius, y up: main pad and four toes.
local PAW = {
  { 0, -0.20, 0.31, 0.25 },
  { -0.36, 0.10, 0.11, 0.145 },
  { -0.135, 0.29, 0.115, 0.15 },
  { 0.135, 0.29, 0.115, 0.15 },
  { 0.36, 0.10, 0.11, 0.145 },
}

local function clamp(v)
  return v < 0 and 0 or (v > 1 and 1 or v)
end

local function mix(a, b, t)
  return a + (b - a) * t
end

-- Repeatable pseudo-random value in [0, 1) for a grid point.
local function hash(ix, iy)
  local s = math.sin(ix * 12.9898 + iy * 78.233) * 43758.5453
  return s - math.floor(s)
end

-- Smooth noise: the grid values blended between points.
local function noise(x, y, cell)
  local gx, gy = x / cell, y / cell
  local ix, iy = math.floor(gx), math.floor(gy)
  local fx, fy = gx - ix, gy - iy
  fx, fy = fx * fx * (3 - 2 * fx), fy * fy * (3 - 2 * fy)
  local top = mix(hash(ix, iy), hash(ix + 1, iy), fx)
  local bottom = mix(hash(ix, iy + 1), hash(ix + 1, iy + 1), fx)
  return mix(top, bottom, fy)
end

--- Signed distance in pixels to the paw print: negative inside.
function M.paw(u, v, radius)
  local best = math.huge
  for _, e in ipairs(PAW) do
    local dx, dy = (u - e[1]) / e[3], (v - e[2]) / e[4]
    local d = (math.sqrt(dx * dx + dy * dy) - 1) * math.min(e[3], e[4]) * radius
    best = math.min(best, d)
  end
  return best
end

--- Colour at pixel (px, py), top-left origin: r, g, b, a from 0 to 1.
function M.pixel(px, py, style)
  local half = M.SIZE / 2
  local x, y = px + 0.5 - half, half - (py + 0.5)
  local rho = math.sqrt(x * x + y * y)
  local theta = math.atan2(y, x)
  -- A stone is never a perfect circle.
  local edge = half * 0.91 + 0.8 * math.sin(3 * theta + 0.7) + 0.4 * math.sin(7 * theta + 2.1)
  local inside = edge - rho
  local alpha = clamp(inside + 0.5)
  if alpha == 0 then
    return DARK[1], DARK[2], DARK[3], 0
  end

  -- A gentle dome lit from the top left.
  local q = math.min(1, rho / edge)
  local nz = math.sqrt(math.max(0.05, 1 - 0.8 * q * q))
  local nx, ny = x / edge, y / edge
  local len = math.sqrt(nx * nx + ny * ny + nz * nz)
  local light = math.max(0, (nx * LX + ny * LY + nz * LZ) / len)
  local shade = 0.42 + 0.78 * light
  local grain = (noise(px, py, 7) - 0.5) * 0.16 + (noise(px, py, 2) - 0.5) * 0.08
  local r = style.stone[1] * shade + grain
  local g = style.stone[2] * shade + grain
  local b = style.stone[3] * shade + grain

  -- A carved ring, dark groove with a lit lower lip.
  local ringR = edge * 0.78
  local groove = math.exp(-((rho - ringR) / 1.4) ^ 2)
  local lip = math.exp(-((rho - ringR - 1.8) / 1.1) ^ 2)
  local darken, lighten = 0.45 * groove, 0.18 * lip
  r = r * (1 - darken) + lighten
  g = g * (1 - darken) + lighten
  b = b * (1 - darken) + lighten

  -- The paw: glowing inside, a warm halo around it.
  local d = M.paw(x / half, y / half, half)
  local halo = 0.5 * math.exp(-math.max(d, 0) / 5)
  local glow = style.glow
  r, g, b = r + glow[1] * halo * 0.6, g + glow[2] * halo * 0.6, b + glow[3] * halo * 0.6
  local fill = clamp(0.5 - d)
  local core = 0.82 + 0.3 * clamp(-d / 7)
  r = mix(r, glow[1] * core, fill)
  g = mix(g, glow[2] * core, fill)
  b = mix(b, glow[3] * core, fill)

  -- Dark worn rim.
  local rim = 1 - clamp((inside - 1) / 2.5)
  r, g, b = mix(r, DARK[1], rim), mix(g, DARK[2], rim), mix(b, DARK[3], rim)
  return clamp(r), clamp(g), clamp(b), alpha
end

local function byte(v)
  return string.char(math.floor(clamp(v) * 255 + 0.5))
end

--- One style as an uncompressed 32-bit TGA file (rows bottom-up).
function M.tga(style)
  local s = M.SIZE
  local out = { string.char(0, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0, s % 256, math.floor(s / 256), s % 256,
    math.floor(s / 256), 32, 8) }
  for py = s - 1, 0, -1 do
    local row = {}
    for px = 0, s - 1 do
      local r, g, b, a = M.pixel(px, py, style)
      row[#row + 1] = byte(b) .. byte(g) .. byte(r) .. byte(a)
    end
    out[#out + 1] = table.concat(row)
  end
  return table.concat(out)
end

if arg and arg[0] and arg[0]:match("make_icon%.lua$") then
  local dir = arg[1] or "TrailMate/media"
  for _, style in pairs(M.STYLES) do
    local path = ("%s/%s.tga"):format(dir, style.file)
    local file = assert(io.open(path, "wb"))
    file:write(M.tga(style))
    file:close()
    print(path)
  end
end

return M
