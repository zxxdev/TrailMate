-- A round button on the minimap edge with the TrailMate icon.
-- Left click: the panel. Right click: show or hide the step window.
-- Drag it around the minimap; the position is saved.

local _, ns = ...

local MinimapButton = {}
ns.MinimapButton = MinimapButton

local RADIUS = 80

local function place(b, angle)
  local rad = math.rad(angle)
  b:ClearAllPoints()
  b:SetPoint("CENTER", Minimap, "CENTER", math.cos(rad) * RADIUS, math.sin(rad) * RADIUS)
end

function MinimapButton.create(saved, L, onLeft, onRight)
  if not Minimap then
    return nil
  end
  local b = CreateFrame("Button", "TrailMateMinimapButton", Minimap)
  b:SetSize(31, 31)
  b:SetFrameStrata("MEDIUM")
  b:SetFrameLevel(8)
  b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  b:RegisterForDrag("LeftButton")
  b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

  local icon = b:CreateTexture(nil, "BACKGROUND")
  icon:SetSize(20, 20)
  icon:SetPoint("TOPLEFT", 6, -5)
  ns.Theme.useIcon(icon)
  icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  local border = b:CreateTexture(nil, "OVERLAY")
  border:SetSize(53, 53)
  border:SetPoint("TOPLEFT")
  border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

  saved.angle = saved.angle or 200
  place(b, saved.angle)

  b:SetScript("OnDragStart", function(self)
    self:SetScript("OnUpdate", function()
      local mx, my = Minimap:GetCenter()
      local cx, cy = GetCursorPosition()
      local scale = Minimap:GetEffectiveScale()
      saved.angle = math.deg(math.atan2(cy / scale - my, cx / scale - mx))
      place(self, saved.angle)
    end)
  end)
  b:SetScript("OnDragStop", function(self)
    self:SetScript("OnUpdate", nil)
  end)
  b:SetScript("OnClick", function(_, button)
    if button == "RightButton" then
      onRight()
    else
      onLeft()
    end
  end)
  b:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine("TrailMate")
    GameTooltip:AddLine(L["Left click: panel"], 1, 1, 1)
    GameTooltip:AddLine(L["Right click: show or hide the steps"], 1, 1, 1)
    GameTooltip:AddLine(L["Drag: move this button"], 0.7, 0.7, 0.7)
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function()
    GameTooltip:Hide()
  end)
  if saved.hidden then
    b:Hide()
  end
  MinimapButton.button = b
  return b
end
