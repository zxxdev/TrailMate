-- TrailMate's look, in the style of the game: the gold border of Blizzard's
-- dialogs, a deep blue gradient, a round emblem with a gold ring and gold
-- titles. Besides the game's own textures, the addon has two pictures of its
-- own, drawn by scripts in tools/: the arrow and the icon. Nothing is
-- borrowed from other addons.

local _, ns = ...

local Theme = {}
ns.Theme = Theme

-- The icon: a cosy stone with a glowing paw print (tools/make_icon.lua).
-- The glow says who the companion is: gold with no AI, orange for Claude,
-- white on black stone for ChatGPT.
local MEDIA = "Interface\\AddOns\\TrailMate\\media\\"
Theme.ICONS = { none = MEDIA .. "Icon", claude = MEDIA .. "Icon-claude", chatgpt = MEDIA .. "Icon-chatgpt" }
Theme.ICON = Theme.ICONS.none
local iconTextures = {}

--- Shows the addon icon on a texture and keeps it in step with the companion.
function Theme.useIcon(tex)
  iconTextures[#iconTextures + 1] = tex
  tex:SetTexture(Theme.ICON)
end

--- "claude", "chatgpt" or anything else for none. Returns the kind used.
function Theme.setCompanion(kind)
  if not Theme.ICONS[kind] then
    kind = "none"
  end
  Theme.ICON = Theme.ICONS[kind]
  for _, tex in ipairs(iconTextures) do
    tex:SetTexture(Theme.ICON)
  end
  return kind
end
Theme.FLAT = "Interface\\Buttons\\WHITE8X8"
Theme.GOLD = { 1, 0.82, 0 }
Theme.ACCENT = { 0.61, 0.48, 0.83 }
Theme.BG_TOP = { 0.08, 0.13, 0.24, 0.97 }
Theme.BG_BOTTOM = { 0.02, 0.03, 0.08, 0.97 }
-- Borders are drawn with flat colours, not stretched pictures, so they stay
-- sharp at any screen size and UI scale: a dark outline, a gold band and a
-- dark inner line, the same as the icon's ring.
Theme.OUTLINE = { 0.04, 0.05, 0.09, 1 }
Theme.EDGE_GOLD = { 0.93, 0.71, 0.24, 1 }
Theme.EDGE_GOLD_DARK = { 0.58, 0.40, 0.12, 1 }
Theme.INSET = 5 -- outline 1 + gold 3 + inner line 1

-- Text colours by meaning, like quest text in the game.
Theme.COLORS = {
  accept = { 1, 0.82, 0 }, -- quest to pick up: gold
  complete = { 0.45, 0.75, 1 }, -- quest to do: light blue
  turnin = { 1, 0.9, 0.45 }, -- quest to hand in: pale gold
  ["goto"] = { 0.6, 1, 0.6 }, -- a place: green
  level = { 0.85, 0.7, 1 },
  note = { 0.9, 0.9, 0.9 },
  warning = { 1, 0.55, 0.2 },
  muted = { 0.62, 0.66, 0.74 },
}

-- Icons by step type, all from the game's own art.
Theme.STEP_ICONS = {
  accept = "Interface\\GossipFrame\\AvailableQuestIcon",
  turnin = "Interface\\GossipFrame\\ActiveQuestIcon",
  complete = "Interface\\CURSOR\\Attack",
  ["goto"] = "Interface\\Icons\\Ability_Hunter_Pathfinding",
  level = "Interface\\GossipFrame\\TrainerGossipIcon",
  note = "Interface\\GossipFrame\\GossipGossipIcon",
}

local function rgb(c)
  return c[1], c[2], c[3]
end
Theme.rgb = rgb

-- A flat rectangle inset from the frame's edges, on a draw sub-level.
local function rect(f, layer, sub, inset, c)
  local t = f:CreateTexture(nil, layer, nil, sub)
  t:SetPoint("TOPLEFT", inset, -inset)
  t:SetPoint("BOTTOMRIGHT", -inset, inset)
  t:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
  return t
end

-- A vertical gradient (bottom to top), or the top colour if the client
-- cannot draw one.
local function gradient(t, bottom, top)
  t:SetTexture(Theme.FLAT)
  local ok = t.SetGradient and CreateColor and pcall(t.SetGradient, t, "VERTICAL",
    CreateColor(bottom[1], bottom[2], bottom[3], bottom[4] or 1), CreateColor(top[1], top[2], top[3], top[4] or 1))
  if not ok then
    t:SetColorTexture(top[1], top[2], top[3], top[4] or 1)
  end
end

--- Sharp gold border (outline, gold band, inner line) and a deep blue
--- vertical gradient behind the content. Returns the background texture.
function Theme.panel(f)
  rect(f, "BACKGROUND", -8, 0, Theme.OUTLINE)
  rect(f, "BACKGROUND", -7, 1, Theme.EDGE_GOLD)
  rect(f, "BACKGROUND", -6, 4, Theme.EDGE_GOLD_DARK)
  local bg = rect(f, "BACKGROUND", -5, Theme.INSET, Theme.BG_TOP)
  gradient(bg, Theme.BG_BOTTOM, Theme.BG_TOP)
  return bg
end

--- The addon icon (a round badge with its own gold ring) in the top-left
--- corner of a frame. Returns the holder frame.
function Theme.emblem(f, size)
  local holder = CreateFrame("Frame", nil, f)
  holder:SetSize(size, size)
  holder:SetPoint("TOPLEFT", 10, -9)
  holder:SetFrameLevel((f:GetFrameLevel() or 1) + 5)
  local icon = holder:CreateTexture(nil, "ARTWORK")
  icon:SetAllPoints()
  Theme.useIcon(icon)
  return holder
end

--- Emblem plus a gold title next to it. Returns emblem, title.
function Theme.header(f, title, size)
  size = size or 28
  local emblem = Theme.emblem(f, size)
  local text = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  text:SetPoint("LEFT", emblem, "RIGHT", 8, 0)
  text:SetText(title)
  text:SetTextColor(rgb(Theme.GOLD))
  return emblem, text
end

-- Buttons: flat and sharp like the borders. Navy with a gold edge; lighter
-- under the mouse (the HIGHLIGHT layer, shown by the game itself), darker
-- while pressed, and gold-filled when disabled, which the panel uses for the
-- open tab.
Theme.BUTTON = {
  edge = { 0.80, 0.60, 0.20, 1 },
  top = { 0.15, 0.22, 0.38, 1 },
  bottom = { 0.07, 0.10, 0.19, 1 },
  hover = { 1, 1, 1, 0.12 },
  pressed = { 0, 0, 0, 0.30 },
  selectedTop = { 0.55, 0.40, 0.12, 1 },
  selectedBottom = { 0.36, 0.25, 0.07, 1 },
}

local function buttonLook(b, selected)
  local c = Theme.BUTTON
  if selected then
    gradient(b.fill, c.selectedBottom, c.selectedTop)
    b.edge:SetColorTexture(Theme.EDGE_GOLD[1], Theme.EDGE_GOLD[2], Theme.EDGE_GOLD[3], 1)
  else
    gradient(b.fill, c.bottom, c.top)
    b.edge:SetColorTexture(c.edge[1], c.edge[2], c.edge[3], c.edge[4])
  end
end

--- A TrailMate button with a click handler.
function Theme.button(parent, label, width, onClick)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(width or 110, 22)
  local c = Theme.BUTTON
  rect(b, "BACKGROUND", -8, 0, Theme.OUTLINE)
  b.edge = rect(b, "BACKGROUND", -7, 1, c.edge)
  b.fill = rect(b, "BACKGROUND", -6, 2, c.top)
  rect(b, "HIGHLIGHT", 0, 2, c.hover)
  local pressed = rect(b, "ARTWORK", 0, 2, c.pressed)
  if b.SetPushedTexture then
    pcall(b.SetPushedTexture, b, pressed)
  end
  pressed:Hide()
  local text = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  text:SetPoint("LEFT", 6, 0)
  text:SetPoint("RIGHT", -6, 0)
  if text.SetWordWrap then
    text:SetWordWrap(false)
  end
  if b.SetFontString then
    b:SetFontString(text)
  end
  if b.SetNormalFontObject then
    b:SetNormalFontObject("GameFontNormal")
    b:SetHighlightFontObject("GameFontHighlight")
    b:SetDisabledFontObject("GameFontHighlight")
  end
  if b.SetPushedTextOffset then
    b:SetPushedTextOffset(1, -1)
  end
  buttonLook(b, false)
  if b.HookScript then
    b:HookScript("OnDisable", function(self)
      buttonLook(self, true)
    end)
    b:HookScript("OnEnable", function(self)
      buttonLook(self, false)
    end)
  end
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
