-- TrailMate's own on-screen arrow: points at the current target using the
-- player's facing, with the distance and the step text underneath.
-- Works without TomTom. Movable; the position is saved per character.
--
-- Like TomTom's arrow, the picture (media/Arrow.tga, drawn by
-- tools/make_arrow.lua) holds the arrow already drawn at 128 angles and the
-- game only shows the right cell, so it stays smooth. It is tinted gold when
-- the target is ahead and turns to the addon's purple as it falls behind.

local _, ns = ...

local Arrow = {}
ns.Arrow = Arrow

local ARRIVED_YARDS = 8
local SIZE = 56
-- Must match tools/make_arrow.lua.
local TEXTURE = "Interface\\AddOns\\TrailMate\\media\\Arrow"
local COLS, ROWS = 16, 8
local FRAMES = COLS * ROWS
-- If the picture cannot be loaded: the minimap arrow, rotated by the game.
local FALLBACK = "Interface\\Minimap\\MinimapArrow"

local function setArrowArt(tex)
  if tex:SetTexture(TEXTURE) ~= false then
    tex:SetTexCoord(0, 1 / COLS, 0, 1 / ROWS)
    return true
  end
  tex:SetTexture(FALLBACK)
  return false
end

function Arrow.create(saved, L)
  local f = CreateFrame("Frame", "TrailMateArrow", UIParent)
  f:SetSize(120, 110)
  f:SetPoint(saved.point or "TOP", UIParent, saved.relPoint or "TOP", saved.x or 0, saved.y or -140)
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetClampedToScreen(true)
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local point, _, relPoint, x, y = self:GetPoint()
    saved.point, saved.relPoint, saved.x, saved.y = point, relPoint, x, y
  end)

  f.icon = f:CreateTexture(nil, "ARTWORK")
  f.icon:SetPoint("TOP", 0, -4)
  f.icon:SetSize(SIZE, SIZE)
  Arrow.sheet = setArrowArt(f.icon)
  Arrow.art = Arrow.sheet and ("TrailMate %d frames"):format(FRAMES) or FALLBACK

  f.distance = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
  f.distance:SetPoint("TOP", f.icon, "BOTTOM", 0, -2)
  f.label = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  f.label:SetPoint("TOP", f.distance, "BOTTOM", 0, -2)
  f.label:SetWidth(220)
  f:Hide()

  Arrow.frame, Arrow.saved, Arrow.L = f, saved, L
  return f
end

-- Places to bring the arrow back to, if it was dragged where it is lost.
Arrow.PLACES = {
  top = { "TOP", 0, -16 }, -- right at the top of the screen, in the middle
  center = { "CENTER", 0, 60 }, -- the middle of the screen, a little above the character
}

--- Moves the arrow to "top" or "center" and remembers it. False if unknown.
function Arrow.place(where)
  local p, f = Arrow.PLACES[where], Arrow.frame
  if not (p and f) then
    return false
  end
  f:ClearAllPoints()
  f:SetPoint(p[1], UIParent, p[1], p[2], p[3])
  local saved = Arrow.saved
  saved.point, saved.relPoint, saved.x, saved.y = p[1], p[1], p[2], p[3]
  return true
end

--- Hides the arrow for a while (in a dungeon) without changing the
--- player's choice to show it.
function Arrow.setAway(away)
  if Arrow.away ~= away then
    Arrow.away = away
    Arrow.update()
  end
end

--- Points the arrow at target ({ mapID, x, y }) with a label, or hides it.
--- note: what to say when there is no place to point at (nil: "not known").
function Arrow.setTarget(target, label, note)
  Arrow.target, Arrow.labelText, Arrow.note = target, label, note
  ns.MapTrail.setTarget(target)
  Arrow.update()
end

-- Turns the arrow and tints it: gold ahead, purple behind.
local function aim(icon, rotation)
  local Geo, Theme = ns.Geo, ns.Theme
  if Arrow.sheet then
    local k = Geo.arrowFrame(rotation, FRAMES)
    local col, row = k % COLS, math.floor(k / COLS)
    icon:SetTexCoord(col / COLS, (col + 1) / COLS, row / ROWS, (row + 1) / ROWS)
    Arrow.cell = k
  else
    icon:SetRotation(rotation)
  end
  local t, a, b = Geo.offCourse(rotation), Theme.GOLD, Theme.ACCENT
  icon:SetVertexColor(a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t, a[3] + (b[3] - a[3]) * t)
end

-- A target on another map of the same continent (Orgrimmar and Durotar):
-- compare world positions. Which way is north in world units is measured on
-- the player's own map, so no axis convention has to be assumed.
-- there: a world point { cont, x, y }. Returns bearing and distance, or nil.
local function towards(mapID, px, py, there)
  local Api = ns.Api
  local here = Api.worldPos(mapID, px, py)
  if not (here and there) or here.cont ~= there.cont then
    return nil
  end
  local north = Api.worldPos(mapID, px, py - 0.01)
  local east = Api.worldPos(mapID, px + 0.01, py)
  if not (north and east) then
    return nil
  end
  local function minus(a)
    return { x = a.x - here.x, y = a.y - here.y }
  end
  return ns.Geo.worldBearing(minus(there), minus(east), minus(north))
end

local function farAway(mapID, px, py, target)
  return towards(mapID, px, py, ns.Api.worldPos(target.mapID, target.x, target.y))
end

local worldYards, pinNow -- below, with Arrow.tick

--- The next dot of a walked trail to follow on the way to the target (a
--- world point), or nil to point straight at the target. The distance shown
--- stays the distance to the target.
function Arrow.setVia(point)
  Arrow.via = point
end

--- Recomputes direction and distance (the map work: where the player and
--- the target are). Arrow.tick calls it a few times per second.
function Arrow.update()
  local f, L = Arrow.frame, Arrow.L
  if not f then
    return
  end
  local target = Arrow.target
  local pin = ns.MinimapPin
  -- What this was worked out for: Arrow.tick reuses it while it holds.
  local last = { target = target, via = Arrow.via, label = Arrow.labelText,
    off = (Arrow.saved.disabled or Arrow.away) and true or false }
  Arrow.last = last
  if Arrow.saved.disabled or Arrow.away or not (target or Arrow.labelText) then
    f:Hide()
    pin.hide()
    return
  end
  f:Show()
  f.label:SetText(Arrow.labelText or "")
  if not target then
    -- A step with no known place yet: say so instead of vanishing.
    f.icon:Hide()
    pin.hide()
    f.distance:SetText(Arrow.note or L["Place not known yet"])
    return
  end

  local Api, Geo = ns.Api, ns.Geo
  local mapID, px, py = Api.position()
  local tx, ty
  if mapID then
    tx, ty = Api.translate(target, mapID)
  end
  local yards, bearing
  if mapID and px and py and tx and ty then
    local w, h = Api.mapSize(mapID)
    yards, bearing = Geo.distance(px, py, tx, ty, w, h), Geo.bearing(px, py, tx, ty, w, h)
  elseif mapID and px and py then
    bearing, yards = farAway(mapID, px, py, target)
  end
  if not bearing then
    f.icon:Hide()
    pin.hide()
    local name = Api.mapName(target.mapID)
    f.distance:SetText(name and L["In %s"]:format(name) or L["Position unknown here"])
    return
  end
  -- The minimap mark shows the target itself (not the trail's next dot).
  local pinBearing = bearing
  pin.update(bearing, yards, Api.facing())
  if yards and yards <= ARRIVED_YARDS then
    f.icon:Hide()
    f.distance:SetText(L["You are there"])
    return
  end
  -- Along a walked trail: point at its next dot (round the wall, through the gate).
  if Arrow.via then
    bearing = towards(mapID, px, py, Arrow.via) or bearing
  end
  local rotation = Geo.arrowRotation(bearing, Api.facing())
  if rotation then
    aim(f.icon, rotation)
    f.icon:Show()
  else
    f.icon:Hide()
  end
  f.distance:SetText(Geo.formatDistance(yards))
  last.bearing, last.pinBearing, last.yards = bearing, pinBearing, yards
  -- Where the player stood for this, to move the minimap mark while walking.
  last.north, last.west = worldYards()
end

-- Where the player stands in the world, in yards (north, west), or nil. A
-- cheap call, unlike the map position: read every frame so the minimap mark
-- stays on its spot while walking (it jumped five times a second, seen in
-- the game).
function worldYards()
  local fn = rawget(_G, "UnitPosition")
  if type(fn) ~= "function" then
    return nil
  end
  local ok, west, north = pcall(fn, "player")
  if ok and type(west) == "number" and type(north) == "number" then
    return north, west
  end
  return nil
end

-- The minimap mark now: the target as seen at the last map work, less the
-- way walked since. Returns bearing, yards and facing for MinimapPin.update.
function pinNow(last, north, west)
  local b, d = last.pinBearing, last.yards
  if not (north and last.north and b and d) then
    return b, d, last.facing
  end
  local east = -math.sin(b) * d - (last.west - west) -- walking west takes the target east
  local ahead = math.cos(b) * d - (north - last.north)
  return math.atan2(-east, ahead), math.sqrt(east * east + ahead * ahead), last.facing
end

-- How often the map work is done again; in between only the turning.
Arrow.GEO_EVERY = 0.2

--- Called every frame or so (now: seconds, growing). Turning the camera
--- needs the arrow to follow at once, and that only needs the facing; where
--- the player and the target are changes slowly, so that is worked out again
--- every GEO_EVERY seconds, or at once when the target, the trail's next dot
--- or the text change.
function Arrow.tick(now)
  local last, f = Arrow.last, Arrow.frame
  local off = (Arrow.saved and (Arrow.saved.disabled or Arrow.away)) and true or false
  if last and last.at and now - last.at < Arrow.GEO_EVERY and last.target == Arrow.target
    and last.via == Arrow.via and last.label == Arrow.labelText and last.off == off then
    if last.bearing and f then
      local facing = ns.Api.facing()
      local north, west = worldYards()
      local moved = north ~= nil and (north ~= last.nowNorth or west ~= last.nowWest)
      -- Not turned nor moved since the last frame: all is already right.
      if facing == last.facing and not moved then
        return
      end
      last.facing, last.nowNorth, last.nowWest = facing, north, west
      ns.MinimapPin.update(pinNow(last, north, west))
      local rotation = ns.Geo.arrowRotation(last.bearing, facing)
      if rotation then
        aim(f.icon, rotation)
      end
    end
    return
  end
  Arrow.update()
  if Arrow.last then
    Arrow.last.at = now
  end
end
