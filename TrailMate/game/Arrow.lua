-- TrailMate's own on-screen arrow: points at the current target using the
-- player's facing, with the distance and the step text underneath.
-- Works without TomTom. Movable; the position is saved per character.

local _, ns = ...

local Arrow = {}
ns.Arrow = Arrow

local ARRIVED_YARDS = 8
-- Arrow art from the game, sharpest first: the modern client's navigation
-- arrow (an atlas), checked to exist before use; else the minimap arrow.
local ATLASES = { "Navigation-Tracked-Arrow", "MiniMap-QuestArrow" }
local FALLBACK = "Interface\\Minimap\\MinimapArrow"

-- Returns the name of the art used (for the self-test) and its native size.
local function setArrowArt(tex)
  if tex.SetAtlas and C_Texture and C_Texture.GetAtlasInfo then
    for _, atlas in ipairs(ATLASES) do
      local ok, info = pcall(C_Texture.GetAtlasInfo, atlas)
      if ok and type(info) == "table" and pcall(tex.SetAtlas, tex, atlas) then
        return atlas, info.width, info.height
      end
    end
  end
  tex:SetTexture(FALLBACK)
  return FALLBACK
end

-- Rotated textures look jagged when the game snaps them to the pixel grid.
local function smooth(tex)
  if tex.SetSnapToPixelGrid then
    pcall(tex.SetSnapToPixelGrid, tex, false)
  end
  if tex.SetTexelSnappingBias then
    pcall(tex.SetTexelSnappingBias, tex, 0)
  end
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
  local art, w, h = setArrowArt(f.icon)
  Arrow.art = art
  -- Never stretch the art beyond its own size: that is what makes it blurry.
  if type(w) == "number" and type(h) == "number" and w > 0 and h > 0 then
    local scale = math.min(1, 56 / math.max(w, h))
    f.icon:SetSize(w * scale, h * scale)
    Arrow.art = ("%s %dx%d"):format(art, w, h)
  else
    f.icon:SetSize(48, 48)
  end
  smooth(f.icon)
  if art == FALLBACK then
    f.icon:SetVertexColor(1, 0.82, 0)
  end

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
