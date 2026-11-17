-- TrailMate's own mark on the minimap, so no other addon is needed: a purple
-- pin with its tip on the target (the game's quest marks under it stay
-- visible), or, when the target is beyond the minimap's edge, a small purple
-- arrow on the edge pointing at it. Follows the minimap's zoom, indoors and
-- outdoors, and the "rotate minimap" option. Returns "pin" or "edge".

local _, ns = ...

local MinimapPin = {}
ns.MinimapPin = MinimapPin

-- How many yards the minimap shows across at each zoom level (the same
-- figures map addons use).
local ACROSS = {
  outdoor = { [0] = 466 + 2 / 3, [1] = 400, [2] = 333 + 1 / 3, [3] = 266 + 2 / 6, [4] = 200, [5] = 133 + 1 / 3 },
  indoor = { [0] = 300, [1] = 240, [2] = 180, [3] = 120, [4] = 80, [5] = 50 },
}
local PIN = "Interface\\AddOns\\TrailMate\\media\\Pin" -- drawn by tools/make_pin.lua
local PIN_SIZE = 20
local ARROW = "Interface\\AddOns\\TrailMate\\media\\Arrow"
local COLS, ROWS = 16, 8 -- the arrow picture, as in game/Arrow.lua
local EDGE_GAP = 6 -- pixels inside the edge

local frame

local function create()
  local map = rawget(_G, "Minimap")
  if type(map) ~= "table" then
    return nil
  end
  local f = CreateFrame("Frame", "TrailMateMinimapPin", map)
  f:SetSize(1, 1)
  f:SetPoint("CENTER", map, "CENTER")
  f:SetFrameLevel((map.GetFrameLevel and map:GetFrameLevel() or 1) + 10)
  -- The addon's purple, not gold: gold is the game's colour for quests.
  local purple = ns.Theme.ACCENT
  f.pin = f:CreateTexture(nil, "OVERLAY", nil, 2)
  f.pin:SetTexture(PIN)
  f.pin:SetSize(PIN_SIZE, PIN_SIZE)
  f.edge = f:CreateTexture(nil, "OVERLAY", nil, 3)
  f.edge:SetTexture(ARROW)
  f.edge:SetVertexColor(purple[1], purple[2], purple[3], 1)
  f.edge:SetSize(20, 20)
  frame = f
  return f
end

local function hideAll()
  if frame then
    frame.pin:Hide()
    frame.edge:Hide()
  end
end

--- Hides the mark (no target).
function MinimapPin.hide()
  hideAll()
  MinimapPin.state = "hidden"
end

local function across()
  local map = rawget(_G, "Minimap")
  local zoom = map and map.GetZoom and map:GetZoom() or 0
  local indoors = type(IsIndoors) == "function" and IsIndoors()
  local list = indoors and ACROSS.indoor or ACROSS.outdoor
  return list[zoom] or list[0]
end

local function rotating()
  return type(GetCVar) == "function" and GetCVar("rotateMinimap") == "1"
end

local function square()
  return type(GetMinimapShape) == "function" and GetMinimapShape() == "SQUARE"
end

--- Places the mark: bearing (radians counter-clockwise from north, like the
--- arrow's) and distance in yards to the target; facing for a rotating
--- minimap. Returns "dot" or "edge".
function MinimapPin.update(bearing, yards, facing)
  if not (bearing and yards) then
    MinimapPin.hide()
    return nil
  end
  local f = frame or create()
  local map = rawget(_G, "Minimap")
  if not (f and map) then
    return nil
  end
  local radius = (map.GetWidth and map:GetWidth() or 140) / 2
  local px = yards / (across() / 2) * radius
  -- East and north offsets in pixels.
  local x, y = -math.sin(bearing) * px, math.cos(bearing) * px
  if rotating() and facing then
    x, y = x * math.cos(facing) + y * math.sin(facing), -x * math.sin(facing) + y * math.cos(facing)
  end
  local limit = radius - EDGE_GAP
  -- How far out, as the minimap's shape measures it (round or square).
  local reach
  if square() then
    reach = math.max(math.abs(x), math.abs(y))
  else
    reach = math.sqrt(x * x + y * y)
  end
  if reach > limit then
    x, y = x * limit / reach, y * limit / reach
    -- The arrow points outwards, at the target.
    local k = ns.Geo.arrowFrame(math.atan2(-x, y), COLS * ROWS)
    local col, row = k % COLS, math.floor(k / COLS)
    f.edge:SetTexCoord(col / COLS, (col + 1) / COLS, row / ROWS, (row + 1) / ROWS)
    f.edge:ClearAllPoints()
    f.edge:SetPoint("CENTER", map, "CENTER", x, y)
    f.edge:Show()
    f.pin:Hide()
    MinimapPin.state = "edge"
  else
    -- The pin's tip on the target (3 of the picture's 64 pixels above its
    -- bottom edge): it stands above the spot and leaves it visible.
    f.pin:ClearAllPoints()
    f.pin:SetPoint("BOTTOM", map, "CENTER", x, y - PIN_SIZE * 3 / 64)
    f.pin:Show()
    f.edge:Hide()
    MinimapPin.state = "pin"
  end
  MinimapPin.x, MinimapPin.y = x, y
  return MinimapPin.state
end
