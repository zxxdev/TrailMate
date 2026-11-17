-- TrailMate's own on-screen arrow: points at the current target using the
-- player's facing, with the distance and the step text underneath.
-- Works without TomTom. Movable; the position is saved per character.

local _, ns = ...

local Arrow = {}
ns.Arrow = Arrow

local ARRIVED_YARDS = 8
-- Built-in textures, tried in order: the first one the client has is used.
local TEXTURES = {
  "Interface\\Minimap\\MinimapArrow",
  "Interface\\Minimap\\ROTATING-MINIMAPGUIDEARROW",
}

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
  f.icon:SetSize(56, 56)
  f.icon:SetPoint("TOP", 0, -4)
  for _, path in ipairs(TEXTURES) do
    if f.icon:SetTexture(path) ~= false then
      break
    end
  end
  f.icon:SetVertexColor(1, 0.82, 0)

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
    f.icon:SetRotation(rotation)
    f.icon:Show()
  else
    f.icon:Hide()
  end
  f.distance:SetText(Geo.formatDistance(yards))
end
