-- TrailMate's look: dark flat panels, a thin border, a violet accent line
-- and the addon icon in every header. Shared by the window, the arrow and
-- the panel so it all looks like one thing.

local _, ns = ...

local Theme = {}
ns.Theme = Theme

-- A built-in game icon (Pathfinding: a boot on a trail), so nothing is shipped.
Theme.ICON = "Interface\\Icons\\Ability_Hunter_Pathfinding"
Theme.ACCENT = { 0.61, 0.48, 0.83 }
Theme.BG = { 0.05, 0.04, 0.08, 0.92 }
Theme.EDGE = { 0.30, 0.24, 0.42, 1 }
Theme.FLAT = "Interface\\Buttons\\WHITE8X8"

--- Dark flat background, thin border and an accent line on top.
function Theme.panel(f)
  if f.SetBackdrop then
    f:SetBackdrop({ bgFile = Theme.FLAT, edgeFile = Theme.FLAT, edgeSize = 1 })
    f:SetBackdropColor(Theme.BG[1], Theme.BG[2], Theme.BG[3], Theme.BG[4])
    f:SetBackdropBorderColor(Theme.EDGE[1], Theme.EDGE[2], Theme.EDGE[3], Theme.EDGE[4])
  end
  local bar = f:CreateTexture(nil, "BORDER")
  bar:SetColorTexture(Theme.ACCENT[1], Theme.ACCENT[2], Theme.ACCENT[3], 0.9)
  bar:SetHeight(2)
  bar:SetPoint("TOPLEFT", 1, -1)
  bar:SetPoint("TOPRIGHT", -1, -1)
  return bar
end

--- Icon and title in the top-left corner. Returns icon, title.
function Theme.header(f, title)
  local icon = f:CreateTexture(nil, "ARTWORK")
  icon:SetSize(18, 18)
  icon:SetPoint("TOPLEFT", 8, -7)
  icon:SetTexture(Theme.ICON)
  icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  local text = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  text:SetPoint("LEFT", icon, "RIGHT", 6, 0)
  text:SetText(title)
  text:SetTextColor(Theme.ACCENT[1] + 0.2, Theme.ACCENT[2] + 0.2, Theme.ACCENT[3] + 0.15)
  return icon, text
end

--- A standard game button with a click handler.
function Theme.button(parent, label, width, onClick)
  local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  b:SetSize(width or 110, 22)
  b:SetText(label)
  b:SetScript("OnClick", onClick)
  return b
end

--- A text line in a panel.
function Theme.label(parent, template)
  local fs = parent:CreateFontString(nil, "OVERLAY", template or "GameFontHighlightSmall")
  fs:SetJustifyH("LEFT")
  return fs
end

--- Makes a frame movable with the left button and saves where it was left.
function Theme.movable(f, saved)
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
end
