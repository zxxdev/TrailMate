-- The step window: the zone as a gold title, the current step with its icon
-- and colour (like the game's quest text), why it matters, the next steps,
-- and Done / Skip buttons. Drag it with the left button; right-click opens
-- the panel.

local _, ns = ...

local UI = {}
ns.UI = UI

local WIDTH, HEIGHT = 330, 164

local function text(parent, template, x, y, width)
  local fs = parent:CreateFontString(nil, "OVERLAY", template)
  fs:SetPoint("TOPLEFT", x, y)
  fs:SetWidth(width or (WIDTH - x - 14))
  fs:SetJustifyH("LEFT")
  return fs
end

local function run(cmd)
  SlashCmdList.TRAILMATE(cmd)
end

-- Reminders hang under the window as bars: icon, text and a button that
-- takes the player there (trainer, vendor) or opens the talents.
local CHIPS, CHIP_HEIGHT = 3, 28

local function pulse(tex)
  local group = tex.CreateAnimationGroup and tex:CreateAnimationGroup()
  if not group then
    return
  end
  local fade = group:CreateAnimation("Alpha")
  fade:SetFromAlpha(1)
  fade:SetToAlpha(0.3)
  fade:SetDuration(0.8)
  group:SetLooping("BOUNCE")
  group:Play()
end

local function chip(f, i)
  local Theme = ns.Theme
  local b = CreateFrame("Button", nil, f)
  b:SetSize(WIDTH - 8, CHIP_HEIGHT)
  b:SetPoint("TOPLEFT", f, "BOTTOMLEFT", 4, 2 - (i - 1) * (CHIP_HEIGHT + 2))
  local bg = b:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints()
  bg:SetColorTexture(Theme.BG_BOTTOM[1], Theme.BG_BOTTOM[2], Theme.BG_BOTTOM[3], 0.94)
  local bar = b:CreateTexture(nil, "ARTWORK")
  bar:SetPoint("TOPLEFT")
  bar:SetPoint("BOTTOMLEFT")
  bar:SetWidth(4)
  bar:SetColorTexture(Theme.GOLD[1], Theme.GOLD[2], Theme.GOLD[3], 1)
  pulse(bar)
  b.icon = b:CreateTexture(nil, "ARTWORK")
  b.icon:SetSize(22, 22)
  b.icon:SetPoint("LEFT", 10, 0)
  b.label = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  b.label:SetPoint("LEFT", b.icon, "RIGHT", 8, 0)
  b.label:SetWidth(WIDTH - 130)
  b.label:SetJustifyH("LEFT")
  b.go = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  b.go:SetPoint("RIGHT", -10, 0)
  b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
  b:SetScript("OnClick", function(self)
    if self.cmd then
      run(self.cmd)
    end
  end)
  b:Hide()
  return b
end

function UI.create(saved)
  local template = BackdropTemplateMixin and "BackdropTemplate" or nil
  local f = CreateFrame("Frame", "TrailMateFrame", UIParent, template)
  f:SetSize(WIDTH, HEIGHT)
  f:SetPoint(saved.point or "RIGHT", UIParent, saved.relPoint or "RIGHT", saved.x or -40, saved.y or 120)
  ns.Theme.movable(f, saved)
  ns.Theme.panel(f)
  local _, title = ns.Theme.header(f, "TrailMate", 28)
  title:SetWidth(WIDTH - 110)
  title:SetJustifyH("LEFT")
  f.title = title
  f.counter = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  f.counter:SetPoint("TOPRIGHT", -14, -15)

  f.icon = f:CreateTexture(nil, "ARTWORK")
  f.icon:SetSize(18, 18)
  f.icon:SetPoint("TOPLEFT", 14, -40)
  f.step = text(f, "GameFontHighlight", 36, -42)
  f.why = text(f, "GameFontNormalSmall", 36, -62)
  f.why:SetTextColor(ns.Theme.rgb(ns.Theme.COLORS.warning))
  f.next = text(f, "GameFontHighlightSmall", 16, -82)
  f.next:SetTextColor(ns.Theme.rgb(ns.Theme.COLORS.muted))

  f.arrow = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  f.arrow:SetPoint("BOTTOMLEFT", 16, 14)
  f.chips = {}
  for i = 1, CHIPS do
    f.chips[i] = chip(f, i)
  end
  f.skip = ns.Theme.button(f, "", 64, function()
    run("skip")
  end)
  f.skip:SetSize(64, 20)
  f.skip:SetPoint("BOTTOMRIGHT", -12, 10)
  f.done = ns.Theme.button(f, "", 64, function()
    run("done")
  end)
  f.done:SetSize(64, 20)
  f.done:SetPoint("RIGHT", f.skip, "LEFT", -4, 0)

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

--- Standing reminders until they are done: { icon, text, cmd, action }.
function UI.setAlerts(list)
  if not UI.frame then
    return
  end
  for i, b in ipairs(UI.frame.chips) do
    local a = list[i]
    if a then
      b.icon:SetTexture(a.icon)
      b.label:SetText(a.text)
      b.go:SetText(a.action and ("|cffffd100" .. a.action .. " >|r") or "")
      b.cmd = a.cmd
      b:Show()
    else
      b.cmd = nil
      b:Hide()
    end
  end
end

function UI.setShown(shown)
  if not UI.frame then
    return
  end
  UI.saved.hidden = not shown
  UI.frame:SetShown(shown)
end

local function setButtons(f, L, visible)
  f.done:SetText(L["Done"])
  f.skip:SetText(L["Skip"])
  f.done:SetShown(visible)
  f.skip:SetShown(visible)
end

local function setStepLook(f, kind)
  local icon = ns.Theme.STEP_ICONS[kind]
  if icon then
    f.icon:SetTexture(icon)
    f.icon:Show()
  else
    f.icon:Hide()
  end
  f.step:SetTextColor(ns.Theme.rgb(ns.Theme.COLORS[kind] or ns.Theme.COLORS.note))
end

--- While travelling to a chosen zone the window shows the trip, not the
--- quests of the zone being left. lines: title, then "- step" lines.
function UI.renderTravel(lines, L)
  local f = UI.frame
  if not f then
    return
  end
  f.title:SetText(L["Travel"])
  f.counter:SetText(L["Travel"])
  setStepLook(f, "goto")
  f.step:SetText(lines[2] and (lines[2]:gsub("^%- ", "")) or (lines[1] or ""))
  f.why:SetText(lines[1] or "")
  f.why:SetTextColor(ns.Theme.rgb(ns.Theme.COLORS.muted))
  local rest = {}
  for i = 3, math.min(#lines, 5) do
    rest[#rest + 1] = lines[i]
  end
  f.next:SetText(table.concat(rest, "\n"))
  f.arrow:SetText(L["Back to the quests: /tm plan"])
  setButtons(f, L, false)
end

--- Draws the plan state. Any argument may be nil.
function UI.render(plan, current, statuses, L, arrowMethod)
  local f = UI.frame
  if not f then
    return
  end
  f.title:SetText(plan and plan.title or "TrailMate")
  f.why:SetTextColor(ns.Theme.rgb(ns.Theme.COLORS.warning))
  if not plan or not current then
    local empty = L["No plan loaded. Type /tm questlog to build one from your quest log."]
    f.counter:SetText("")
    setStepLook(f, "note")
    f.step:SetText(plan and L["Plan finished."] or empty)
    f.why:SetText("")
    f.next:SetText("")
    f.arrow:SetText("")
    setButtons(f, L, false)
    return
  end
  local step = plan.steps[current]
  f.counter:SetText(L["Step %d of %d"]:format(current, #plan.steps))
  setStepLook(f, step.type)
  f.step:SetText(step.text)
  f.why:SetText(step.why or "")
  local upcoming = {}
  for i = current + 1, #plan.steps do
    if statuses[i] == "pending" then
      upcoming[#upcoming + 1] = "- " .. plan.steps[i].text
      if #upcoming == 3 then
        break
      end
    end
  end
  f.next:SetText(table.concat(upcoming, "\n"))
  f.arrow:SetText(L["Arrow: %s"]:format(arrowMethod or L["no arrow available"]))
  setButtons(f, L, true)
end
