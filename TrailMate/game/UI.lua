-- The step window: current step, its reason and the next two steps.
-- Movable; its position is saved per character.

local _, ns = ...

local UI = {}
ns.UI = UI

local WIDTH = 300

local function text(parent, template, anchor, rel, y)
  local fs = parent:CreateFontString(nil, "OVERLAY", template)
  fs:SetPoint("TOPLEFT", rel or parent, rel and "BOTTOMLEFT" or "TOPLEFT", rel and 0 or 10, y)
  fs:SetWidth(WIDTH - 20)
  fs:SetJustifyH("LEFT")
  if anchor then
    fs:SetText(anchor)
  end
  return fs
end

function UI.create(saved)
  local template = BackdropTemplateMixin and "BackdropTemplate" or nil
  local f = CreateFrame("Frame", "TrailMateFrame", UIParent, template)
  f:SetSize(WIDTH, 130)
  f:SetPoint(saved.point or "RIGHT", UIParent, saved.relPoint or "RIGHT", saved.x or -40, saved.y or 120)
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
  if f.SetBackdrop then
    f:SetBackdrop({
      bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
      edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
      edgeSize = 12,
      insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    f:SetBackdropColor(0, 0, 0, 0.75)
  end
  f.title = text(f, "GameFontNormal", "TrailMate", nil, -8)
  f.counter = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  f.counter:SetPoint("TOPRIGHT", -10, -9)
  f.step = text(f, "GameFontHighlight", nil, f.title, -6)
  f.why = text(f, "GameFontDisableSmall", nil, f.step, -3)
  f.next = text(f, "GameFontHighlightSmall", nil, f.why, -6)
  f.arrow = text(f, "GameFontDisableSmall", nil, f.next, -6)
  if saved.hidden then
    f:Hide()
  end
  UI.frame, UI.saved = f, saved
  return f
end

function UI.setShown(shown)
  if not UI.frame then
    return
  end
  UI.saved.hidden = not shown
  UI.frame:SetShown(shown)
end

--- Draws the plan state. Any argument may be nil.
function UI.render(plan, current, statuses, L, arrowMethod)
  local f = UI.frame
  if not f then
    return
  end
  if not plan then
    f.counter:SetText("")
    f.step:SetText(L["No plan loaded. Type /tm questlog to build one from your quest log."])
    f.why:SetText("")
    f.next:SetText("")
    f.arrow:SetText("")
    return
  end
  if not current then
    f.counter:SetText("")
    f.step:SetText(L["Plan finished."])
    f.why:SetText("")
    f.next:SetText("")
    f.arrow:SetText("")
    return
  end
  local step = plan.steps[current]
  f.counter:SetText(L["Step %d of %d"]:format(current, #plan.steps))
  f.step:SetText(step.text)
  f.why:SetText(step.why or "")
  local upcoming = {}
  for i = current + 1, #plan.steps do
    if statuses[i] == "pending" then
      upcoming[#upcoming + 1] = "- " .. plan.steps[i].text
      if #upcoming == 2 then
        break
      end
    end
  end
  f.next:SetText(table.concat(upcoming, "\n"))
  f.arrow:SetText(L["Arrow: %s"]:format(arrowMethod or L["no arrow available"]))
end
