-- Dots on the world map along the way to the target, like the dotted route
-- of Journey: the walked trail TrailMate follows (core/Trails.lua), then
-- the last bit to the target. Drawn on the map's own canvas, so they move
-- and zoom with it; redrawn when the map or the route changes.

local _, ns = ...

local MapTrail = {}
ns.MapTrail = MapTrail

local DOT = "Interface\\CharacterFrame\\TempPortraitAlphaMask" -- a soft white disc
local MAX_DOTS = 400
local GAP = 0.004 -- minimum distance between dots on the map (0 to 1)

local layer, dots = nil, {}
local path, version, drawn = nil, 0, nil

local function canvas()
  local map = rawget(_G, "WorldMapFrame")
  local scroll = type(map) == "table" and rawget(map, "ScrollContainer")
  local child = type(scroll) == "table" and rawget(scroll, "Child")
  return map, type(child) == "table" and child or nil
end

local function dot(i)
  if not dots[i] then
    local d = layer:CreateTexture(nil, "OVERLAY")
    d:SetTexture(DOT)
    dots[i] = d
  end
  return dots[i]
end

local function hideFrom(i)
  for k = i, #dots do
    dots[k]:Hide()
  end
end

--- Draws the current route on the open world map (nothing if it is shut).
function MapTrail.draw()
  local map, child = canvas()
  if not (child and map:IsShown()) then
    return
  end
  if not layer then
    layer = CreateFrame("Frame", nil, child)
    layer:SetAllPoints(child)
    layer:SetFrameLevel((child:GetFrameLevel() or 1) + 20)
  end
  local mapID = map.GetMapID and map:GetMapID()
  drawn = (mapID or 0) .. ":" .. version
  if not (path and mapID) then
    hideFrom(1)
    return
  end
  local w, h = child:GetWidth(), child:GetHeight()
  if not (w and h and w > 0 and h > 0) then
    return
  end
  local size = math.max(4, w / 160)
  local gold = ns.Theme.GOLD
  local n, lastX, lastY = 0, nil, nil
  for i, p in ipairs(path) do
    local mx, my = ns.Api.mapPosFromWorld(p.cont, p.x, p.y, mapID)
    local inside = mx and mx >= 0 and mx <= 1 and my >= 0 and my <= 1
    local spaced = inside and (not lastX or math.abs(mx - lastX) + math.abs(my - lastY) >= GAP or i == #path)
    if spaced and n < MAX_DOTS then
      n = n + 1
      local d = dot(n)
      d:ClearAllPoints()
      d:SetPoint("CENTER", layer, "TOPLEFT", mx * w, -my * h)
      -- The target itself is bigger.
      local s = i == #path and size * 2 or size
      d:SetSize(s, s)
      d:SetVertexColor(gold[1], gold[2], gold[3], 0.95)
      d:Show()
      lastX, lastY = mx, my
    end
  end
  hideFrom(n + 1)
end

-- Fills long straight parts (the last bit to the target) with dots every
-- SPACING yards, so the route reads as one dotted line.
local SPACING = 15

local function densify(points)
  if not points then
    return nil
  end
  local out = { points[1] }
  for i = 2, #points do
    local a, b = points[i - 1], points[i]
    local len = math.sqrt((b.x - a.x) ^ 2 + (b.y - a.y) ^ 2)
    local steps = math.min(200, math.floor(len / SPACING))
    for s = 1, steps - 1 do
      local f = s / steps
      out[#out + 1] = { cont = a.cont, x = a.x + (b.x - a.x) * f, y = a.y + (b.y - a.y) * f }
    end
    out[#out + 1] = b
  end
  return out
end

--- Sets the route to draw (dots { cont, x, y }), or nil to clear it.
function MapTrail.show(points)
  path = densify(points)
  version = version + 1
  MapTrail.draw()
end

--- Called a few times a second: redraws when the map opens or changes.
function MapTrail.tick()
  local map, child = canvas()
  if not (child and map:IsShown()) then
    drawn = nil
    return
  end
  local mapID = map.GetMapID and map:GetMapID()
  if drawn ~= (mapID or 0) .. ":" .. version then
    MapTrail.draw()
  end
end

--- What is drawn now, for the self-test.
function MapTrail.state()
  local _, child = canvas()
  local shown = 0
  for _, d in ipairs(dots) do
    if d:IsShown() then
      shown = shown + 1
    end
  end
  return child ~= nil, path and #path or 0, shown
end
