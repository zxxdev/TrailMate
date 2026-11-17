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

--- Points the arrow at target ({ mapID, x, y }) with a label, or hides it.
function Arrow.setTarget(target, label)
  Arrow.target, Arrow.labelText = target, label
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

--- Recomputes direction and distance. Called a few times per second.
function Arrow.update()
  local f, L = Arrow.frame, Arrow.L
  if not f then
    return
  end
  local target = Arrow.target
  if not target or Arrow.saved.disabled then
    f:Hide()
    return
  end
  f:Show()
  f.label:SetText(Arrow.labelText or "")

  local Api, Geo = ns.Api, ns.Geo
  local mapID, px, py = Api.position()
  local tx, ty
  if mapID then
    tx, ty = Api.translate(target, mapID)
  end
  if not (mapID and px and py and tx and ty) then
    f.icon:Hide()
    local name = Api.mapName(target.mapID)
    f.distance:SetText(name and L["In %s"]:format(name) or L["Position unknown here"])
    return
  end

  local w, h = Api.mapSize(mapID)
  local yards = Geo.distance(px, py, tx, ty, w, h)
  if yards and yards <= ARRIVED_YARDS then
    f.icon:Hide()
    f.distance:SetText(L["You are there"])
    return
  end
  local rotation = Geo.arrowRotation(Geo.bearing(px, py, tx, ty, w, h), Api.facing())
  if rotation then
    aim(f.icon, rotation)
    f.icon:Show()
  else
    f.icon:Hide()
  end
  f.distance:SetText(Geo.formatDistance(yards))
end
