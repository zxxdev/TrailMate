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
-- plant) has its model too when the data knows it (from cMaNGOS and
-- wago.tools, see tools/questdb.lua); if not, the icon of the item looted
-- from it, or a plain box.
local PREVIEW_W, PREVIEW_PAD = 176, 8
local MODEL_W, MODEL_H = PREVIEW_W - 2 * PREVIEW_PAD, 168
local PREVIEW_DELAY, PREVIEW_FADE = 0.25, 0.12
local ICON_S, OBJECT_ICON = 44, "Interface\\Icons\\INV_Box_02"

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
  p.object = CreateFrame("PlayerModel", nil, p) -- an object's model (a chest)
  p.object:SetSize(MODEL_W, MODEL_H)
  p.object:SetPoint("TOP", 0, -PREVIEW_PAD)
  p.object:Hide()
  p.icon = p:CreateTexture(nil, "ARTWORK")
  p.icon:SetSize(ICON_S, ICON_S)
  p.icon:SetPoint("TOP", 0, -PREVIEW_PAD - 4)
  p.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93) -- the game draws a border into its icons
  p.icon:Hide()
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
  -- Never over a fight; a kept preview comes back after it.
  p:RegisterEvent("PLAYER_REGEN_DISABLED")
  p:RegisterEvent("PLAYER_REGEN_ENABLED")
  p:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_REGEN_DISABLED" then
      self:Hide()
      if UI.frame and UI.frame.hoverLight then
        UI.frame.hoverLight:Hide()
      end
    elseif UI.previewPinned() and UI.frame and UI.frame:IsShown() then
      UI.showPreview(UI.frame)
    end
  end)
  p:Hide()
  UI.preview = p
  return p
end

--- True if this client can draw a creature's model from its id.
function UI.canShowCreatures()
  local model = UI.preview and UI.preview.model
  if not model then
    local ok, made = pcall(CreateFrame, "PlayerModel", nil, UIParent)
    model = ok and made or nil
  end
  return model ~= nil and type(model.SetCreature) == "function"
end

-- Each hover gets a number: a wait that ends after the mouse left (or came
-- back) is not the current one and shows nothing.
local hoverTurn = 0

--- True when the player chose to keep the preview shown next to the window.
function UI.previewPinned()
  return UI.saved ~= nil and UI.saved.previewPinned == true
end

local function hidePreview()
  hoverTurn = hoverTurn + 1
  if UI.preview then
    UI.preview:Hide()
  end
  if UI.frame and UI.frame.hoverLight then
    UI.frame.hoverLight:Hide()
  end
end

-- The mouse left the step or the magnifier: a kept preview stays. Otherwise
-- it goes a moment later, so moving from the step onto the magnifier (whose
-- OnEnter comes right after) does not make it blink.
local LEAVE_DELAY = 0.1

local function leavePreview()
  hoverTurn = hoverTurn + 1
  if UI.frame and UI.frame.hoverLight then
    UI.frame.hoverLight:Hide()
  end
  if UI.previewPinned() then
    -- Kept: back to the kept one after looking at another objective.
    if UI.frame and UI.previewStep ~= UI.frame.current then
      UI.showPreview(UI.frame)
    end
    return
  end
  local turn = hoverTurn
  local function go()
    if turn == hoverTurn and not UI.previewPinned() then
      hidePreview()
    end
  end
  if C_Timer and C_Timer.After then
    C_Timer.After(LEAVE_DELAY, go)
  else
    go()
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

-- The picture of an object to search: the icon of the item looted from it,
-- or a plain box. nil for a creature or someone to talk to.
local function objectIcon(step)
  if step.creature or step.type ~= "complete" then
    return nil
  end
  local icon
  if step.loot then
    local byID = C_Item and C_Item.GetItemIconByID
    local ok, got = pcall(byID or GetItemIcon, step.loot)
    icon = ok and got or nil
  end
  return icon or OBJECT_ICON
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

-- Lays out and shows the preview next to the window: of step (a dungeon
-- objective under the mouse), or of the current step.
local function showPreview(f, step)
  if type(step) ~= "table" then
    step = f.current
  end
  UI.previewStep = step
  if not (type(step) == "table" and (step.creature or step.who)) or (InCombatLockdown and InCombatLockdown()) then
    hidePreview()
    return
  end
  local L = (type(f.L) == "table" and f.L) or ns.L or setmetatable({}, { __index = function(_, k) return k end })
  local p = previewFrame()
  p.verb:SetText(verbOf(step, L))
  p.name:SetText(step.who or "")
  local shown, view = false, p.model -- view: the frame that shows it
  if step.creature and p.model.SetCreature then
    shown = pcall(function()
      p.model:ClearModel()
      p.model:SetCreature(step.creature)
    end)
  elseif step.model and p.object.SetModel then
    -- An object (a chest): its model file, in a frame of its own (the
    -- creature frame kept showing the creature before, seen in the game),
    -- and only when the game says it took that file.
    view = p.object
    local ok = pcall(function()
      p.object:ClearModel()
      p.object:SetModel(step.model)
    end)
    local took, file = pcall(function() return p.object:GetModelFileID() end)
    shown = ok and took and file == step.model
  end
  p.model:SetShown(shown and view == p.model)
  p.object:SetShown(shown and view == p.object)
  -- No model: an object to search (a chest) gets the icon of what is in it.
  local icon = not shown and objectIcon(step) or nil
  p.icon:SetShown(icon ~= nil)
  if icon then
    p.icon:SetTexture(icon)
  end
  p.verb:ClearAllPoints()
  if shown then
    p.verb:SetPoint("TOP", view, "BOTTOM", 0, -4)
  elseif icon then
    p.verb:SetPoint("TOP", p.icon, "BOTTOM", 0, -6)
  else
    p.verb:SetPoint("TOP", 0, -PREVIEW_PAD)
  end
  -- The height comes from the text, so two lines never run over the edge.
  local height = PREVIEW_PAD + (shown and (MODEL_H + 4) or 0) + (icon and (ICON_S + 10) or 0)
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
    pcall(view.SetFacing, view, left and 0.35 or -0.35)
  end
  -- Kept, it sits with the window (not over bags, map and tooltips); for a
  -- hover, over everything, and the step it is about lights up.
  local pinned = UI.previewPinned()
  if pinned then
    p:SetFrameStrata(f:GetFrameStrata() or "MEDIUM")
    p:SetFrameLevel((f:GetFrameLevel() or 0) + 5)
  else
    p:SetFrameStrata("TOOLTIP")
  end
  -- Only the step line it is about; a dungeon objective's row lights itself.
  if f.hoverLight then
    f.hoverLight:SetShown(not pinned and not step.dungeon)
  end
  local fadeIn = rawget(_G, "UIFrameFadeIn")
  if not p:IsShown() and fadeIn then
    fadeIn(p, PREVIEW_FADE, 0, 1)
  else
    p:Show()
  end
end

UI.showPreview = showPreview

-- After the mouse rests a moment on the step: passing over it on the way to
-- the buttons below shows nothing.
local function previewSoon(f, step)
  hoverTurn = hoverTurn + 1
  local turn = hoverTurn
  local function go()
    if turn == hoverTurn then
      showPreview(f, step)
    end
  end
  if C_Timer and C_Timer.After then
    C_Timer.After(PREVIEW_DELAY, go)
  else
    go()
  end
end

-- The magnifier next to a step that has someone to show: hover it to see
-- the preview, click it to keep the preview shown (or not).
local LENS, STEP_W, STEP_W_LENS = 14, 280, 260

local function lensLook(lens, lit)
  local Theme = ns.Theme
  local pinned
  if lens.isOn then
    pinned = lens.isOn() == true
  else
    pinned = UI.previewPinned()
  end
  if lit or pinned then
    lens.tex:SetVertexColor(1, 1, 1, 1)
  else
    local c = Theme.COLORS.muted
    lens.tex:SetVertexColor(c[1], c[2], c[3], 0.8)
  end
  lens.on:SetShown(pinned)
end

-- Three soft blinks the first time the magnifier shows, never again.
local function blinkOnce(lens)
  if UI.saved.previewSeen then
    return
  end
  UI.saved.previewSeen = true
  local group = lens.CreateAnimationGroup and lens:CreateAnimationGroup()
  if not group then
    return
  end
  local fade = group:CreateAnimation("Alpha")
  fade:SetFromAlpha(1)
  fade:SetToAlpha(0.4)
  fade:SetDuration(0.2)
  group:SetLooping("BOUNCE")
  local loops = 0
  group:SetScript("OnLoop", function(self)
    loops = loops + 1
    if loops >= 6 then
      self:Stop()
    end
  end)
  group:Play()
end

-- A magnifier button in parent (the window, or a dungeon objective's row).
-- lens.step: what it shows (nil: the current step); lens.isOn: whether its
-- "kept" square shows (nil: whenever the preview is kept); lens.click: what
-- a click does (nil: keep the preview shown, or not).
local function newLens(f, parent)
  local Theme = ns.Theme
  local lens = CreateFrame("Button", nil, parent)
  lens:SetSize(LENS, LENS)
  -- Kept: a square behind it, like a button that stays pressed.
  lens.on = lens:CreateTexture(nil, "BACKGROUND")
  lens.on:SetSize(20, 20)
  lens.on:SetPoint("CENTER")
  lens.on:SetColorTexture(Theme.ACCENT[1], Theme.ACCENT[2], Theme.ACCENT[3], 0.35)
  lens.tex = lens:CreateTexture(nil, "ARTWORK")
  lens.tex:SetAllPoints()
  lens.tex:SetTexture("Interface\\Common\\UI-Searchbox-Icon")
  lens.step, lens.isOn, lens.click = false, false, false -- the window's own, until a row sets them
  local function tip(self)
    if GameTooltip then
      local L = (type(f.L) == "table" and f.L) or ns.L
      local on = self.isOn and self.isOn() or (not self.isOn and UI.previewPinned())
      GameTooltip:SetOwner(self, "ANCHOR_TOP")
      GameTooltip:SetText(on and L["Click to show it only on hover"] or L["Click to keep it shown"], 0.1, 1, 0.1)
      GameTooltip:Show()
    end
  end
  lens:SetScript("OnEnter", function(self)
    lensLook(self, true)
    -- Pointing at it means it: no wait.
    hoverTurn = hoverTurn + 1
    showPreview(f, self.step)
    tip(self)
  end)
  lens:SetScript("OnLeave", function(self)
    lensLook(self, false)
    if GameTooltip then
      GameTooltip:Hide()
    end
    leavePreview()
  end)
  lens:SetScript("OnClick", function(self)
    if self.click then
      self.click(self)
    else
      run("preview")
    end
    -- Still under the mouse: the look and the tip say the new state.
    lensLook(self, true)
    tip(self)
  end)
  lens:Hide()
  return lens
end

local function makeLens(f)
  local lens = newLens(f, f)
  lens:SetPoint("TOPRIGHT", -14, -42)
  lens:SetHitRectInsets(-4, -4, -4, -4)
  return lens
end

-- Shows the magnifier (and makes room for it) when the current step has
-- someone to show.
local function setLens(f)
  local step = f.current
  local has = type(step) == "table" and (step.creature ~= nil or step.who ~= nil)
  f.step:SetWidth(has and STEP_W_LENS or STEP_W)
  if not f.lens then
    return
  end
  f.lens:SetShown(has)
  if has then
    lensLook(f.lens, false)
    blinkOnce(f.lens)
  end
end

-- No step with someone to show (a trip, a dungeon, an empty plan).
local function noPreview(f)
  f.current = nil
  setLens(f)
  hidePreview()
end

--- Keeps the preview shown next to the window (true) or only on hover.
function UI.setPreviewPinned(on)
  if not UI.saved then
    return
  end
  UI.saved.previewPinned = on and true or nil
  local f = UI.frame
  if f and f.lens then
    lensLook(f.lens, false)
  end
  -- Shown, it only moves to its new layer (no fade again). Turned off with
  -- the mouse still on the step or the magnifier, it stays as a hover.
  local over = f and ((f.lens and f.lens.IsMouseOver and f.lens:IsMouseOver())
    or (f.hover and f.hover.IsMouseOver and f.hover:IsMouseOver()))
  if f and f:IsShown() and (on or over) then
    showPreview(f)
  else
    hidePreview()
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
  -- Under the dungeon view: the guide waits outside.
  f.foot = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  -- Both ends anchored and left-justified, so the text starts at the margin
  -- whatever the font object says.
  f.foot:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 16, 14)
  f.foot:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -14, 14)
  f.foot:SetJustifyH("LEFT")
  f.foot:SetMaxLines(1)
  f.foot:SetTextColor(ns.Theme.rgb(ns.Theme.COLORS.muted))
  f.foot:Hide()
  f.drows, f.inDungeon = {}, false
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
  hover:SetScript("OnLeave", leavePreview)
  -- Lights the step while its preview is open: this is what it is about.
  f.hoverLight = hover:CreateTexture(nil, "ARTWORK")
  f.hoverLight:SetAllPoints()
  f.hoverLight:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
  f.hoverLight:SetBlendMode("ADD")
  f.hoverLight:SetAlpha(0.3)
  f.hoverLight:Hide()
  f.hover = hover
  -- Over the hover area, so it gets the mouse and the clicks.
  f.lens = makeLens(f)
  -- Made now, so its combat events are there even when the game loads in
  -- the middle of a fight with the preview kept shown.
  previewFrame()
  f:HookScript("OnHide", hidePreview)
  f:HookScript("OnShow", function(self)
    if UI.previewPinned() then
      showPreview(self)
    end
  end)
  -- Dropped somewhere else: the kept preview picks its side again.
  f:HookScript("OnDragStop", function(self)
    if UI.preview and UI.preview:IsShown() then
      showPreview(self)
    end
  end)

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

local endDungeon -- below, with the dungeon view

--- While travelling to a chosen zone the window shows the trip, not the
--- quests of the zone being left. lines: title, then "- step" lines.
function UI.renderTravel(lines, L)
  local f = UI.frame
  if not f then
    return
  end
  endDungeon(f)
  noPreview(f)
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

-- Inside a dungeon: a row per objective (and a heading per quest when there
-- are several), each with its done mark, the game's count in a column of its
-- own so it is never cut, and a magnifier for the creature it is about. All
-- of them share the one preview.
local DROW_H, DROWS = 16, 10
local DONE_MARK = "Interface\\RaidFrame\\ReadyCheck-Ready"
local TODO_MARK = "Interface\\COMMON\\Indicator-Gray"

local function sameTarget(a, b)
  return type(a) == "table" and type(b) == "table" and a.dungeon and b.dungeon and a.who ~= nil and a.who == b.who
end

local function dungeonRow(f, i)
  local r = CreateFrame("Button", nil, f)
  r:SetSize(WIDTH - 50, DROW_H) -- from x 36 to the window's right margin
  if i == 1 then
    r:SetPoint("TOPLEFT", f.step, "BOTTOMLEFT", 0, -6)
  else
    r:SetPoint("TOPLEFT", f.drows[i - 1], "BOTTOMLEFT", 0, 0)
  end
  -- Over the step's hover area, which reaches down here.
  local level = f.hover and f.hover.GetFrameLevel and f.hover:GetFrameLevel()
  if type(level) == "number" then
    r:SetFrameLevel(level + 2)
  end
  if r.SetMouseMotionEnabled and r.SetMouseClickEnabled then
    r:SetMouseMotionEnabled(true)
    r:SetMouseClickEnabled(false) -- the window still drags from here
  end
  r.mark = r:CreateTexture(nil, "ARTWORK")
  r.mark:SetSize(12, 12)
  r.mark:SetPoint("LEFT", 0, 0)
  r.label = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  r.label:SetPoint("LEFT", 16, 0)
  r.label:SetWidth(208)
  r.label:SetJustifyH("LEFT")
  r.label:SetMaxLines(1)
  r.count = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  r.count:SetPoint("RIGHT", -20, 0)
  r.count:SetWidth(32)
  r.count:SetJustifyH("RIGHT")
  r:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
  local light = r.GetHighlightTexture and r:GetHighlightTexture()
  if light and light.SetAlpha then
    light:SetAlpha(0.3)
  end
  r:SetScript("OnEnter", function(self)
    if self.step then
      previewSoon(f, self.step)
    end
  end)
  r:SetScript("OnLeave", function()
    leavePreview()
  end)
  -- Its magnifier: hover to see this one, click to keep this one shown.
  r.lens = newLens(f, r)
  r.lens:SetPoint("RIGHT", 0, 0)
  r.lens:SetHitRectInsets(-4, -4, -1, -1)
  r.lens.isOn = function()
    return UI.previewPinned() and sameTarget(f.current, r.lens.step)
  end
  r.lens.click = function(self)
    if self.isOn() then
      run("preview off")
      showPreview(f, self.step) -- the mouse is still on it: as a hover now
    else
      f.current = self.step
      if UI.previewPinned() then
        showPreview(f)
      else
        run("preview on")
      end
    end
    for _, other in ipairs(f.drows) do
      lensLook(other.lens, false)
    end
  end
  r:Hide()
  return r
end

-- The game's objective text with its count apart: "Herod slain: 0/1" gives
-- "Herod slain", "0/1" (and "0/1 Herod slain" too).
local function splitCount(s)
  local name, count = s:match("^(.-):%s*(%d+%s*/%s*%d+)$")
  if not name then
    count, name = s:match("^(%d+%s*/%s*%d+)%s+(.+)$")
  end
  return name or s, count
end

-- The rows of one quest's objectives: the game's own (worded and counted
-- in the player's language), each matched to the creature it names; or,
-- when the game says nothing, the data's targets.
local function objectiveRows(q)
  local rows, targets, said = {}, q.targets or {}, q.objectives or {}
  local function about(t)
    return t and { type = "complete", creature = t.c, who = t.n, drop = t.d, loot = t.l, model = t.m,
      dungeon = true } or nil
  end
  if #said == 0 then
    for _, t in ipairs(targets) do
      rows[#rows + 1] = { text = t.n, done = q.done, step = about(t) }
    end
    return rows
  end
  -- Each creature goes with one objective at most ("X slain" and "Head of
  -- X" would both name X). The data's names are English: in another
  -- language they only match by their place in the list, and only when
  -- there are as many of each; otherwise that row has no magnifier.
  local used = {}
  for i, o in ipairs(said) do
    local name, count = splitCount(o.text)
    local found
    for _, t in ipairs(targets) do
      if not used[t] and o.text:find(t.n, 1, true) then
        found = t
        break
      end
    end
    -- Not named in the text (an item it drops): the same place in the list.
    if not found and #targets == #said and not used[targets[i]] then
      found = targets[i]
    end
    if found then
      used[found] = true
    end
    rows[#rows + 1] = { text = name, count = count, done = o.done or q.done, step = about(found) }
  end
  return rows
end

-- Back to the plain window after a dungeon.
function endDungeon(f)
  if not f.inDungeon then
    return
  end
  f.inDungeon = false
  for _, r in ipairs(f.drows or {}) do
    r:Hide()
  end
  if f.foot then
    f.foot:Hide()
  end
  f:SetHeight(HEIGHT)
end

--- In a dungeon with nothing of the log to do there: the window steps
--- aside, with no dungeon view or preview left behind.
function UI.stepAside()
  local f = UI.frame
  if not f then
    return
  end
  endDungeon(f)
  noPreview(f)
end

--- Inside a dungeon with quests of the log to do there: { name, quests =
--- { { name, targets, objectives = { { text, done } } } } }. No arrow and
--- no Done / Skip: the guide waits outside.
function UI.renderDungeon(d, L)
  local f = UI.frame
  if not f then
    return
  end
  local Theme = ns.Theme
  f.L, f.inDungeon = L, true
  f.title:SetText(d.name)
  goldCounter(f)
  local quests = d.quests or {}
  local multi = #quests > 1
  -- Every quest finished: say so, and that they are handed in outside.
  local finished = ns.Dungeons.allDone(quests)
  setStepLook(f, finished and "turnin" or "complete")
  if finished then
    f.step:SetText(L["All done here"])
  else
    f.step:SetText(multi and L["%d quests here"]:format(#quests) or (quests[1] and quests[1].name or ""))
  end
  f.why:SetText("")
  setNext(f, {})
  f.arrow:SetText("")
  setButtons(f, L, false)
  f.foot:SetText(finished and L["Turn them in outside."] or L["The guide waits outside."])
  f.foot:Show()

  local rows, done, total = {}, 0, 0
  for _, q in ipairs(quests) do
    if multi then
      rows[#rows + 1] = { header = q.done and (q.name .. " " .. L["(done)"]) or q.name, headerDone = q.done }
    end
    for _, row in ipairs(objectiveRows(q)) do
      total = total + 1
      done = done + (row.done and 1 or 0)
      rows[#rows + 1] = row
    end
  end
  f.counter:SetText(total > 0 and L["Dungeon %d/%d"]:format(done, total) or L["Dungeon"])
  -- Too many: what is done goes first, then the rest is in the quest log.
  if #rows > DROWS then
    local kept = {}
    for _, row in ipairs(rows) do
      if not row.done then
        kept[#kept + 1] = row
      end
    end
    -- A heading left with nothing under it goes too.
    rows = {}
    for i, row in ipairs(kept) do
      local following = kept[i + 1]
      if not (row.header and (following == nil or following.header)) then
        rows[#rows + 1] = row
      end
    end
  end
  if #rows > DROWS then
    local more = #rows - (DROWS - 1)
    for i = #rows, DROWS, -1 do
      rows[i] = nil
    end
    rows[DROWS] = { text = L["+%d more in the quest log"]:format(more), more = true }
  end

  f.drows = f.drows or {}
  local firstStep
  for i = 1, DROWS do
    local r = f.drows[i]
    local row = rows[i]
    if row and not r then
      r = dungeonRow(f, i)
      f.drows[i] = r
    end
    if r then
      r:SetShown(row ~= nil)
    end
    if row then
      local muted, todo = Theme.COLORS.muted, row.header and Theme.COLORS.complete or Theme.COLORS.note
      r.step = (not row.done) and row.step or false -- false, not nil: a field that is there
      r.lens.step = r.step
      r.label:ClearAllPoints()
      r.label:SetPoint("LEFT", row.header and 0 or 16, 0)
      r.label:SetText(row.header or row.text or "")
      r.label:SetTextColor(Theme.rgb((row.done or row.more or row.headerDone) and muted or todo))
      r.count:SetText(row.count or "")
      r.count:SetTextColor(Theme.rgb(row.done and muted or Theme.COLORS.note))
      r.mark:SetShown(not (row.header or row.more))
      r.mark:SetTexture(row.done and DONE_MARK or TODO_MARK)
      local showLens = r.step and r.step.who ~= nil or false
      r.lens:SetShown(showLens)
      if showLens then
        lensLook(r.lens, false)
        firstStep = firstStep or r.step
      end
    end
  end
  f:SetHeight(math.max(HEIGHT, 60 + #rows * DROW_H + 36))

  -- The one kept on show stays while it is still to do; else the first.
  local kept
  for i = 1, #rows do
    local r = f.drows[i]
    if r.step and sameTarget(r.step, f.current) then
      kept = r.step
    end
  end
  f.current = kept or firstStep
  f.step:SetWidth(STEP_W)
  if f.lens then
    f.lens:Hide() -- each row has its own
  end
  for i = 1, #rows do
    lensLook(f.drows[i].lens, false)
  end
  if UI.previewPinned() and f.current then
    showPreview(f)
  elseif not f.current and UI.preview and UI.preview:IsShown() then
    hidePreview()
  end
end

--- The arrow follows a quest the player marked. marked: { label, kind };
--- waiting: the guide's current step text (or nil); guide: the plan is a
--- guide (else a route). The guide's Done / Skip give way to the way back.
function UI.renderMarked(marked, waiting, guide, L)
  local f = UI.frame
  if not f then
    return
  end
  endDungeon(f)
  -- Its magnifier: the creature or object of the quest, when the data knows it.
  f.current, f.L = (type(marked.about) == "table" and marked.about) or nil, L
  setLens(f)
  if UI.previewPinned() or (UI.preview and UI.preview:IsShown()) then
    showPreview(f)
  end
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
  endDungeon(f)
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
    noPreview(f)
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
  setLens(f)
  -- Kept, or the step changed under the mouse: show the new one.
  if UI.previewPinned() or (UI.preview and UI.preview:IsShown()) then
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

-- On the open flight map, the point TrailMate says to fly to beats in gold
-- (the user asked). Tried in the game and simplified each time: a solid gold
-- halo that breathes (grows and shrinks, never lighter, so the map never
-- shows through), a small dark bronze disc that keeps the silver icon apart
-- from it, and TrailMate's purple pin floating just above the point, the
-- same mark as on the world map. The game's glow and ping pictures are drawn
-- on black and came out as squares, and a ring going out jumped back at
-- each beat: none of them now. Its tooltip gets a line that says why.
local DISC = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local PIN = "Interface\\AddOns\\TrailMate\\media\\Pin"
local BEAT_TIME = 0.8 -- the halo and the pin go together

-- Moved and grown by fractions of a pixel: snapped to whole pixels, a small
-- picture goes in steps (the user saw the beat stutter).
local function unsnap(texture)
  if texture.SetSnapToPixelGrid then
    pcall(texture.SetSnapToPixelGrid, texture, false)
    pcall(texture.SetTexelSnappingBias, texture, 0)
  end
end

-- An animation that goes back and forth, or nil when the client has none.
local function bounce(texture, build)
  local group = texture.CreateAnimationGroup and texture:CreateAnimationGroup()
  if not group then
    return nil
  end
  build(group)
  unsnap(texture)
  -- Eased at both ends: a beat, not a bounce off a wall.
  pcall(function()
    for _, a in ipairs({ group:GetAnimations() }) do
      a:SetSmoothing("IN_OUT")
    end
  end)
  group:SetLooping("BOUNCE")
  return group
end

local function scaleAnim(group, to, duration)
  local a = group:CreateAnimation("Scale")
  if a.SetScaleFrom then
    a:SetScaleFrom(1, 1)
    a:SetScaleTo(to, to)
  end
  a:SetDuration(duration)
  return a
end

local function flightMarkFrame()
  if UI.flightMark then
    return UI.flightMark
  end
  -- Under the point's icon.
  local m = CreateFrame("Frame", "TrailMateFlightMark", UIParent)
  m.anims = {}
  m:SetSize(52, 52)
  if m.EnableMouse then
    m:EnableMouse(false) -- the point keeps its clicks and tooltip
  end
  m.beat = m:CreateTexture(nil, "BACKGROUND", nil, 0)
  -- A round disc, a band of it showing around the dark one: the game's soft
  -- glow pictures came out as a square in Forever (seen twice in the game).
  m.beat:SetSize(40, 40)
  m.beat:SetPoint("CENTER")
  m.beat:SetTexture(DISC)
  m.beat:SetVertexColor(1, 0.75, 0.15, 1) -- warmer than the quest gold, still read as gold
  m.anims[#m.anims + 1] = bounce(m.beat, function(g)
    -- Solid gold that breathes: a lighter beat let the grey stone show
    -- through (seen in a video of the game).
    scaleAnim(g, 1.15, BEAT_TIME)
  end)
  m.disc = m:CreateTexture(nil, "BACKGROUND", nil, 1)
  m.disc:SetSize(26, 26) -- just past the icon: not a dark circle of its own
  m.disc:SetPoint("CENTER")
  m.disc:SetTexture(DISC)
  m.disc:SetVertexColor(0.40, 0.22, 0.00, 0.90) -- dark bronze, not black (the user saw a black circle)
  -- Over it.
  local top = CreateFrame("Frame", nil, UIParent)
  m.top = top
  top:SetSize(52, 52)
  if top.EnableMouse then
    top:EnableMouse(false)
  end
  -- The pin, its tip just above the point's icon, bobbing with the beat.
  m.pin = top:CreateTexture(nil, "OVERLAY", nil, 3)
  m.pin:SetSize(26, 26)
  m.pin:SetPoint("BOTTOM", top, "CENTER", 0, 14)
  m.pin:SetTexture(PIN)
  m.anims[#m.anims + 1] = bounce(m.pin, function(g)
    local up = g:CreateAnimation("Translation")
    up:SetOffset(0, 4)
    up:SetDuration(BEAT_TIME)
  end)
  top:Hide()
  m:Hide()
  UI.flightMark = m
  return m
end

-- The tooltip of the marked point says why it beats.
local function addFlightTip(button)
  if button.trailMateTip or not button.HookScript then
    return
  end
  button.trailMateTip = true
  button:HookScript("OnEnter", function(self)
    if UI.flightMarkOn == self and GameTooltip and GameTooltip:IsShown() then
      local c = ns.Theme.COLORS["goto"]
      GameTooltip:AddLine(UI.flightMarkText or "TrailMate", c[1], c[2], c[3])
      GameTooltip:Show()
    end
  end)
end

-- The point's own level, put back when the mark goes (the game reuses them).
local function restoreButton()
  local b = UI.flightRaised
  if b and b.trailMateLevel and b.SetFrameLevel then
    pcall(b.SetFrameLevel, b, b.trailMateLevel)
    b.trailMateLevel = nil
  end
  UI.flightRaised = nil
end

local function play(m, on)
  for _, a in ipairs(m.anims or {}) do
    if on then
      a:Play()
    else
      a:Stop()
    end
  end
end

--- Marks a flight map's point (its button or pin), or nothing (nil).
function UI.markFlight(button, L)
  local m = flightMarkFrame()
  restoreButton()
  UI.flightMarkOn = button
  if not button then
    play(m, false)
    m.top:Hide()
    m:Hide()
    return
  end
  UI.flightMarkText = L and L["TrailMate: fly here"] or "TrailMate: fly here"
  -- The buttons are reused from one opening to the next: anchored again.
  local parent = button.GetParent and button:GetParent() or UIParent
  local strata = button.GetFrameStrata and button:GetFrameStrata() or "DIALOG"
  for _, frame in ipairs({ m, m.top }) do
    frame:SetParent(parent)
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", button, "CENTER", 0, 0)
    frame:SetFrameStrata(strata)
  end
  -- Never level with the map (its route lines would draw over the mark):
  -- one over the map, the point over that, the rest over the point.
  local parentLevel = parent.GetFrameLevel and parent:GetFrameLevel()
  local level = button.GetFrameLevel and button:GetFrameLevel()
  if type(parentLevel) == "number" and type(level) == "number" then
    local under = parentLevel + 1
    m:SetFrameLevel(under)
    if level <= under and button.SetFrameLevel then
      button.trailMateLevel = level
      UI.flightRaised = button
      pcall(button.SetFrameLevel, button, under + 1)
      level = under + 1
    end
    m.top:SetFrameLevel(level + 3)
  end
  addFlightTip(button)
  m:Show()
  m.top:Show()
  play(m, true) -- together: one beat, not two rhythms
end

--- The flight map closed: no mark.
function UI.clearFlightMark()
  UI.flightMarkOn = nil
  restoreButton()
  local m = UI.flightMark
  if m then
    play(m, false)
    m.top:Hide()
    m:Hide()
  end
end
