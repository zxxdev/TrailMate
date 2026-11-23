-- The step window: the zone as a gold title, the current step with its icon
-- and colour (like the game's quest text), why it matters, the next steps,
-- and Done / Skip buttons. Drag it with the left button; right-click opens
-- the panel.

local _, ns = ...

local UI = {}
ns.UI = UI

local WIDTH, HEIGHT = 330, 172

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

local NEXT_ROWS = 3

-- lines: texts; indices: the plan step of each (nil: not clickable).
local function setNext(f, lines, indices)
  for i, b in ipairs(f.rows) do
    b.label:SetText(lines[i] or "")
    b.index = indices and indices[i] or nil
    b:SetShown(lines[i] ~= nil)
  end
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

-- The preview: hovering the current step shows who it is about, the quest
-- giver, or the creature to kill or that drops the item, as the game's own
-- 3D model, with what to do and the name under it. An object (a chest, a
-- plant) has no model here: only the two lines of text.
local PREVIEW_W, PREVIEW_PAD = 176, 8
local MODEL_W, MODEL_H = PREVIEW_W - 2 * PREVIEW_PAD, 168
local PREVIEW_DELAY, PREVIEW_FADE = 0.25, 0.12

local function previewFrame()
  if UI.preview then
    return UI.preview
  end
  local template = BackdropTemplateMixin and "BackdropTemplate" or nil
  local p = CreateFrame("Frame", "TrailMatePreview", UIParent, template)
  p:SetFrameStrata("TOOLTIP")
  p:SetClampedToScreen(true)
  ns.Theme.panel(p)
  p.model = CreateFrame("PlayerModel", nil, p)
  p.model:SetSize(MODEL_W, MODEL_H)
  p.model:SetPoint("TOP", 0, -PREVIEW_PAD)
  -- What to do with it ("Talk to", "Kill"), small and grey, then the name.
  p.verb = p:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  p.verb:SetWidth(MODEL_W)
  p.verb:SetJustifyH("CENTER")
  p.verb:SetMaxLines(1)
  p.verb:SetTextColor(ns.Theme.rgb(ns.Theme.COLORS.muted))
  p.name = p:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  p.name:SetWidth(MODEL_W)
  p.name:SetPoint("TOP", p.verb, "BOTTOM", 0, -2)
  p.name:SetJustifyH("CENTER")
  p.name:SetMaxLines(2)
  -- Never over a fight.
  p:RegisterEvent("PLAYER_REGEN_DISABLED")
  p:SetScript("OnEvent", function(self)
    self:Hide()
  end)
  p:Hide()
  UI.preview = p
  return p
end

--- True if this client can draw a creature's model from its id.
function UI.canShowCreatures()
  local ok, model = pcall(CreateFrame, "PlayerModel", nil, UIParent)
  return ok and model ~= nil and type(model.SetCreature) == "function"
end

-- Each hover gets a number: a wait that ends after the mouse left (or came
-- back) is not the current one and shows nothing.
local hoverTurn = 0

local function hidePreview()
  hoverTurn = hoverTurn + 1
  if UI.preview then
    UI.preview:Hide()
  end
  if UI.frame and UI.frame.hoverLight then
    UI.frame.hoverLight:Hide()
  end
end

-- What the player does with who the step is about.
local function verbOf(step, L)
  if step.type == "accept" then
    return L["Talk to"]
  elseif step.type == "turnin" then
    return L["Turn in to"]
  elseif step.drop then
    return L["Dropped by"]
  elseif step.creature then
    return L["Kill"]
  end
  return L["Search"]
end

local function overlaps(a1, a2, b1, b2)
  return a1 and a2 and b1 and b2 and a1 < b2 and b1 < a2
end

-- On the right of the window, unless it would leave the screen or cover the
-- arrow (its text and item button sit in the middle, near the window's top).
local function previewOnLeft(f, height)
  local right, top, screen = f:GetRight(), f:GetTop(), UIParent:GetWidth()
  if right and screen and right + PREVIEW_W + 8 > screen then
    return true
  end
  local arrow = ns.Arrow and ns.Arrow.frame
  if right and top and arrow and arrow:IsShown() then
    local left, aRight = arrow:GetLeft(), arrow:GetRight()
    local aTop, aBottom = arrow:GetTop(), arrow:GetBottom()
    if aBottom then
      aBottom = aBottom - 40 -- the item button hangs under it
    end
    if overlaps(right + 8, right + 8 + PREVIEW_W, left, aRight) and overlaps(top - height, top, aBottom, aTop) then
      return true
    end
  end
  return false
end

local function heightOf(fs, fallback)
  local h = fs.GetStringHeight and fs:GetStringHeight()
  return (type(h) == "number" and h > 0) and h or fallback
end

-- Lays out and shows the preview of the current step next to the window.
local function showPreview(f)
  local step = f.current
  if not (step and (step.creature or step.who)) or (InCombatLockdown and InCombatLockdown()) then
    hidePreview()
    return
  end
  local L = f.L or ns.L or setmetatable({}, { __index = function(_, k) return k end })
  local p = previewFrame()
  p.verb:SetText(verbOf(step, L))
  p.name:SetText(step.who or "")
  local shown = false
  if step.creature and p.model.SetCreature then
    shown = pcall(function()
      p.model:ClearModel()
      p.model:SetCreature(step.creature)
    end)
  end
  p.model:SetShown(shown)
  p.verb:ClearAllPoints()
  if shown then
    p.verb:SetPoint("TOP", p.model, "BOTTOM", 0, -4)
  else
    p.verb:SetPoint("TOP", 0, -PREVIEW_PAD)
  end
  -- The height comes from the text, so two lines never run over the edge.
  local height = PREVIEW_PAD + (shown and (MODEL_H + 4) or 0)
    + heightOf(p.verb, 10) + 2 + heightOf(p.name, 14) + PREVIEW_PAD
  height = math.max(48, math.floor(height + 0.5))
  p:SetSize(PREVIEW_W, height)
  p:ClearAllPoints()
  local left = previewOnLeft(f, height)
  if left then
    -- Clear of the item button left of the window when it is there.
    local item = rawget(_G, "TrailMateItemButton")
    p:SetPoint("TOPRIGHT", f, "TOPLEFT", (item and item:IsShown()) and -46 or -8, 0)
  else
    p:SetPoint("TOPLEFT", f, "TOPRIGHT", 8, 0)
  end
  if shown then
    -- A little turned, towards the window.
    pcall(p.model.SetFacing, p.model, left and 0.35 or -0.35)
  end
  if f.hoverLight then
    f.hoverLight:Show()
  end
  local fadeIn = rawget(_G, "UIFrameFadeIn")
  if not p:IsShown() and fadeIn then
    fadeIn(p, PREVIEW_FADE, 0, 1)
  else
    p:Show()
  end
end

-- After the mouse rests a moment on the step: passing over it on the way to
-- the buttons below shows nothing.
local function previewSoon(f)
  hoverTurn = hoverTurn + 1
  local turn = hoverTurn
  local function go()
    if turn == hoverTurn then
      showPreview(f)
    end
  end
  if C_Timer and C_Timer.After then
    C_Timer.After(PREVIEW_DELAY, go)
  else
    go()
  end
end

function UI.create(saved)
  local template = BackdropTemplateMixin and "BackdropTemplate" or nil
  local f = CreateFrame("Frame", "TrailMateFrame", UIParent, template)
  f:SetSize(WIDTH, HEIGHT)
  -- First time: top left, under the target frame and right of the party
  -- frames, with room on its left for the item button.
  f:SetPoint(saved.point or "TOPLEFT", UIParent, saved.relPoint or "TOPLEFT", saved.x or 240, saved.y or -200)
  ns.Theme.movable(f, saved)
  ns.Theme.panel(f)
  local _, title = ns.Theme.header(f, "TrailMate", 28)
  title:SetWidth(WIDTH - 150)
  title:SetJustifyH("LEFT")
  title:SetMaxLines(1)
  f.title = title
  f.counter = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  f.counter:SetPoint("TOPRIGHT", -14, -15)

  f.icon = f:CreateTexture(nil, "ARTWORK")
  f.icon:SetSize(18, 18)
  f.icon:SetPoint("TOPLEFT", 14, -40)
  f.step = text(f, "GameFontHighlight", 36, -42)
  f.step:SetMaxLines(2)
  -- Under the step text, so a long quest name never runs over it.
  f.why = text(f, "GameFontNormalSmall", 36, -62)
  f.why:ClearAllPoints()
  f.why:SetPoint("TOPLEFT", f.step, "BOTTOMLEFT", 0, -6)
  f.why:SetMaxLines(1)
  f.why:SetTextColor(ns.Theme.rgb(ns.Theme.COLORS.warning))
  -- The next steps, under the "why" line: click one to do it now instead.
  f.rows = {}
  for i = 1, NEXT_ROWS do
    local b = CreateFrame("Button", nil, f)
    b:SetSize(WIDTH - 28, 14)
    if i == 1 then
      b:SetPoint("TOPLEFT", f.why, "BOTTOMLEFT", -22, -6)
    else
      b:SetPoint("TOPLEFT", f.rows[i - 1], "BOTTOMLEFT", 0, 0)
    end
    b.label = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.label:SetPoint("LEFT", 2, 0)
    b.label:SetWidth(WIDTH - 32)
    b.label:SetJustifyH("LEFT")
    b.label:SetMaxLines(1)
    b.label:SetTextColor(ns.Theme.rgb(ns.Theme.COLORS.muted))
    b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    b:SetScript("OnClick", function(self)
      if self.index then
        run("pick " .. self.index)
      end
    end)
    f.rows[i] = b
  end

  -- How the target is marked on the map: kept for the self-test, not shown
  -- (its place is the Undo button's).
  f.arrow = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  f.arrow:SetPoint("BOTTOMLEFT", 16, 14)
  f.arrow:Hide()
  -- A Done or Skip by mistake is one click away from being undone.
  f.undo = ns.Theme.button(f, "", 72, function()
    run("undo")
  end)
  f.undo:SetSize(72, 20)
  f.undo:SetPoint("BOTTOMLEFT", 14, 10)
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
  ns.Theme.primary(f.done)
  -- While the arrow follows a quest the player marked: the way back.
  f.back = ns.Theme.button(f, "", 132, function()
    run("plan")
  end)
  f.back:SetSize(132, 20)
  ns.Theme.primary(f.back)
  f.back:SetPoint("BOTTOMRIGHT", -12, 10)
  f.back:Hide()

  -- Hovering the current step (its icon, text and "why" line) shows the
  -- preview. Only the mouse's movement is caught here: clicks and drags go
  -- on to the window, so it still moves from anywhere.
  local hover = CreateFrame("Frame", nil, f)
  hover:SetPoint("TOPLEFT", f.icon, "TOPLEFT", -4, 4)
  hover:SetPoint("BOTTOMRIGHT", f.why, "BOTTOMRIGHT", 4, -4)
  if hover.SetMouseMotionEnabled and hover.SetMouseClickEnabled then
    hover:SetMouseMotionEnabled(true)
    hover:SetMouseClickEnabled(false)
  else
    hover:EnableMouse(true)
  end
  hover:SetScript("OnEnter", function()
    previewSoon(f)
  end)
  hover:SetScript("OnLeave", hidePreview)
  -- Lights the step while its preview is open: this is what it is about.
  f.hoverLight = hover:CreateTexture(nil, "ARTWORK")
  f.hoverLight:SetAllPoints()
  f.hoverLight:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
  f.hoverLight:SetBlendMode("ADD")
  f.hoverLight:SetAlpha(0.3)
  f.hoverLight:Hide()
  f.hover = hover
  f:HookScript("OnHide", hidePreview)

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

--- Steps aside for a while (in a dungeon with nothing to do there) without
--- changing the player's choice to show or hide the window.
function UI.setAway(away)
  if not UI.frame then
    return
  end
  if away or UI.saved.hidden then
    UI.frame:Hide()
  else
    UI.frame:Show()
  end
end

local function goldCounter(f)
  local g = ns.Theme.GOLD
  f.counter:SetTextColor(g[1], g[2], g[3])
end

local function setButtons(f, L, visible)
  f.done:SetText(L["Done"])
  f.skip:SetText(L["Skip"])
  f.undo:SetText(L["Undo"])
  f.done:SetShown(visible)
  f.skip:SetShown(visible)
  f.undo:SetShown(visible)
  f.back:Hide()
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
  f.current = nil
  hidePreview()
  f.title:SetText(L["Travel"])
  f.counter:SetText(L["Travel"])
  goldCounter(f)
  setStepLook(f, "goto")
  f.step:SetText(lines[2] and (lines[2]:gsub("^%- ", "")) or (lines[1] or ""))
  f.why:SetText(lines[1] or "")
  f.why:SetTextColor(ns.Theme.rgb(ns.Theme.COLORS.muted))
  local rest = {}
  for i = 3, math.min(#lines, 5) do
    rest[#rest + 1] = lines[i]
  end
  setNext(f, rest)
  f.arrow:SetText(L["Back to the quests: /tm plan"])
  setButtons(f, L, false)
end

--- Inside a dungeon with quests of the log to do there: { name, quests =
--- { { name } } }. No arrow and no Done / Skip: the guide waits outside.
function UI.renderDungeon(d, L)
  local f = UI.frame
  if not f then
    return
  end
  f.current = nil
  hidePreview()
  f.title:SetText(d.name)
  f.counter:SetText(L["Dungeon"])
  goldCounter(f)
  setStepLook(f, "complete")
  local names = {}
  for _, q in ipairs(d.quests) do
    names[#names + 1] = q.name
  end
  f.step:SetText(L["Do here: %s"]:format(table.concat(names, ", ")))
  f.why:SetText(L["The guide waits outside."])
  f.why:SetTextColor(ns.Theme.rgb(ns.Theme.COLORS.muted))
  setNext(f, {})
  f.arrow:SetText("")
  setButtons(f, L, false)
end

--- The arrow follows a quest the player marked. marked: { label, kind };
--- waiting: the guide's current step text (or nil); guide: the plan is a
--- guide (else a route). The guide's Done / Skip give way to the way back.
function UI.renderMarked(marked, waiting, guide, L)
  local f = UI.frame
  if not f then
    return
  end
  f.current = nil
  hidePreview()
  f.title:SetText(L["Your marked quest"])
  f.counter:SetText(guide and L["Guide paused"] or L["Route paused"])
  f.counter:SetTextColor(ns.Theme.rgb(ns.Theme.COLORS.muted))
  setStepLook(f, marked.kind or "complete")
  f.step:SetText(marked.label or "")
  f.why:SetText(waiting and L["Next in the guide - %s"]:format(waiting) or "")
  f.why:SetTextColor(ns.Theme.rgb(ns.Theme.COLORS.muted))
  setNext(f, {})
  f.arrow:SetText("")
  setButtons(f, L, false)
  f.back:SetText(guide and L["Back to the guide"] or L["Back to the route"])
  f.back:Show()
end

--- Draws the plan state. Any argument may be nil.
function UI.render(plan, current, statuses, L, arrowMethod)
  local f = UI.frame
  if not f then
    return
  end
  -- Say what is being followed: a guide, or TrailMate's own route.
  local title = plan and plan.title or "TrailMate"
  if plan and ns.Guide.isGuide(plan) then
    title = L["Guide: %s"]:format(title)
  elseif plan then
    title = L["Route: %s"]:format(title)
  end
  f.title:SetText(title)
  goldCounter(f)
  f.why:SetTextColor(ns.Theme.rgb(ns.Theme.COLORS.warning))
  if not plan or not current then
    f.current = nil
    hidePreview()
    local empty = L["No plan loaded. Type /tm questlog to build one from your quest log."]
    f.counter:SetText("")
    setStepLook(f, "note")
    f.step:SetText(plan and L["Plan finished."] or empty)
    f.why:SetText("")
    setNext(f, {})
    f.arrow:SetText("")
    setButtons(f, L, false)
    return
  end
  local step = plan.steps[current]
  f.current, f.L = step, L
  -- The step changed under the mouse: show the new one.
  if UI.preview and UI.preview:IsShown() then
    showPreview(f)
  end
  -- How far along: steps done or skipped, not the place of the current one
  -- (a step chosen from the list would make that look further than it is).
  local passed = 0
  for i = 1, #plan.steps do
    if statuses and (statuses[i] == "done" or statuses[i] == "skipped") then
      passed = passed + 1
    end
  end
  f.counter:SetText(L["%d of %d done"]:format(passed, #plan.steps))
  setStepLook(f, step.type)
  f.step:SetText(step.text)
  f.why:SetText(step.why or "")
  -- The other pending steps, in plan order (a chosen step may lead).
  local upcoming, indices = {}, {}
  for i = 1, #plan.steps do
    if i ~= current and statuses[i] == "pending" then
      upcoming[#upcoming + 1] = "- " .. plan.steps[i].text
      indices[#indices + 1] = i
      if #upcoming == NEXT_ROWS then
        break
      end
    end
  end
  setNext(f, upcoming, indices)
  f.arrow:SetText(L["Map mark: %s"]:format(arrowMethod or L["none"]))
  setButtons(f, L, true)
end
