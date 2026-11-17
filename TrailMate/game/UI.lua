-- The step window: current step, its reason and the next two steps.
-- Drag it with the left button; right-click opens the panel.

local _, ns = ...

local UI = {}
ns.UI = UI

local WIDTH = 300

local function text(parent, template, rel, y)
  local fs = parent:CreateFontString(nil, "OVERLAY", template)
  if rel then
    fs:SetPoint("TOPLEFT", rel, "BOTTOMLEFT", 0, y)
  else
    fs:SetPoint("TOPLEFT", 10, y)
  end
  fs:SetWidth(WIDTH - 20)
  fs:SetJustifyH("LEFT")
  return fs
end

function UI.create(saved)
  local template = BackdropTemplateMixin and "BackdropTemplate" or nil
  local f = CreateFrame("Frame", "TrailMateFrame", UIParent, template)
  f:SetSize(WIDTH, 132)
  f:SetPoint(saved.point or "RIGHT", UIParent, saved.relPoint or "RIGHT", saved.x or -40, saved.y or 120)
  ns.Theme.movable(f, saved)
  ns.Theme.panel(f)
  local _, title = ns.Theme.header(f, "TrailMate")
  f.title = title
  f.counter = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  f.counter:SetPoint("TOPRIGHT", -10, -10)
  f.step = text(f, "GameFontHighlight", nil, -32)
  f.why = text(f, "GameFontDisableSmall", f.step, -3)
  f.next = text(f, "GameFontHighlightSmall", f.why, -6)
  f.arrow = text(f, "GameFontDisableSmall", f.next, -6)
  f:SetScript("OnMouseUp", function(_, button)
    if button == "RightButton" then
      ns.Panel.toggle()
    end
  end)
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

--- While travelling to a chosen zone the window shows the trip, not the
--- quests of the zone being left. lines: title, then "- step" lines.
function UI.renderTravel(lines, L)
  local f = UI.frame
  if not f then
    return
  end
  f.counter:SetText(L["Travel"])
  f.step:SetText(lines[2] and (lines[2]:gsub("^%- ", "")) or (lines[1] or ""))
  f.why:SetText(lines[1] or "")
  local rest = {}
  for i = 3, math.min(#lines, 5) do
    rest[#rest + 1] = lines[i]
  end
  f.next:SetText(table.concat(rest, "\n"))
  f.arrow:SetText(L["Back to the quests: /tm plan"])
end

--- Draws the plan state. Any argument may be nil.
function UI.render(plan, current, statuses, L, arrowMethod)
  local f = UI.frame
  if not f then
    return
  end
  if not plan or not current then
    f.counter:SetText("")
    local empty = L["No plan loaded. Type /tm questlog to build one from your quest log."]
    f.step:SetText(plan and L["Plan finished."] or empty)
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
