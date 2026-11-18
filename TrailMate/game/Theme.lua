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
Theme.BORDER = "Interface\\DialogFrame\\UI-DialogBox-Gold-Border"
Theme.RING = "Interface\\Minimap\\MiniMap-TrackingBorder"
Theme.ROUND_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
Theme.FLAT = "Interface\\Buttons\\WHITE8X8"
Theme.GOLD = { 1, 0.82, 0 }
Theme.ACCENT = { 0.61, 0.48, 0.83 }
Theme.BG_TOP = { 0.08, 0.13, 0.24, 0.97 }
Theme.BG_BOTTOM = { 0.02, 0.03, 0.08, 0.97 }
Theme.EDGE_SIZE = 24
Theme.INSET = 6

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

--- Gold dialog border and a deep blue vertical gradient behind the content.
function Theme.panel(f)
  if f.SetBackdrop then
    f:SetBackdrop({
      edgeFile = Theme.BORDER, edgeSize = Theme.EDGE_SIZE,
      insets = { left = Theme.INSET, right = Theme.INSET, top = Theme.INSET, bottom = Theme.INSET },
    })
  end
  local bg = f:CreateTexture(nil, "BACKGROUND")
  bg:SetPoint("TOPLEFT", Theme.INSET, -Theme.INSET)
  bg:SetPoint("BOTTOMRIGHT", -Theme.INSET, Theme.INSET)
  bg:SetTexture(Theme.FLAT)
  local top, bottom = Theme.BG_TOP, Theme.BG_BOTTOM
  local gradient = bg.SetGradient and CreateColor and pcall(bg.SetGradient, bg, "VERTICAL",
    CreateColor(bottom[1], bottom[2], bottom[3], bottom[4]), CreateColor(top[1], top[2], top[3], top[4]))
  if not gradient then
    bg:SetColorTexture(top[1], top[2], top[3], top[4])
  end
  return bg
end

--- A round emblem with the addon icon and a gold ring, inside the top-left
--- corner of a frame. Returns the holder frame.
function Theme.emblem(f, size)
  local holder = CreateFrame("Frame", nil, f)
  holder:SetSize(size, size)
  holder:SetPoint("TOPLEFT", 9, -8)
  holder:SetFrameLevel((f:GetFrameLevel() or 1) + 5)
  local back = holder:CreateTexture(nil, "BACKGROUND")
  back:SetPoint("TOPLEFT", size * 0.12, -size * 0.12)
  back:SetSize(size * 0.76, size * 0.76)
  back:SetTexture(Theme.FLAT)
  back:SetColorTexture(0.02, 0.04, 0.1, 1)
  local icon = holder:CreateTexture(nil, "ARTWORK")
  icon:SetPoint("TOPLEFT", size * 6 / 31, -size * 5 / 31)
  icon:SetSize(size * 20 / 31, size * 20 / 31)
  Theme.useIcon(icon)
  if icon.SetMask then
    pcall(icon.SetMask, icon, Theme.ROUND_MASK)
  else
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  end
  local ring = holder:CreateTexture(nil, "OVERLAY")
  ring:SetPoint("TOPLEFT")
  ring:SetSize(size * 53 / 31, size * 53 / 31)
  ring:SetTexture(Theme.RING)
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
