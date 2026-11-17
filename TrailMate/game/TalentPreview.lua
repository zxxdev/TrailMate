-- A picture of a talent template, shown while hovering it: the three trees
-- side by side as small trees, every talent's icon in its place. Talents the
-- template takes are in colour with the level they are taken at and the rank
-- they end at; the ones you already have are marked green; the others are
-- grey. So you see where a template goes before choosing it.

local _, ns = ...

local TalentPreview = {}
ns.TalentPreview = TalentPreview

local CELL, ICON = 34, 28 -- one talent's square, and its icon
local COLS, ROWS = 4, 7
local TREE_GAP, PAD, TOP = 14, 14, 58
local TREE_COLORS = { { 0.55, 0.85, 0.40 }, { 0.45, 0.75, 1.00 }, { 1.00, 0.60, 0.30 } }

local frame
local nodes = {} -- pool of talent squares

local function color(i)
  local c = TREE_COLORS[i] or { 0.9, 0.9, 0.9 }
  return c[1], c[2], c[3]
end

local function create()
  local Theme = ns.Theme
  local template = BackdropTemplateMixin and "BackdropTemplate" or nil
  local f = CreateFrame("Frame", "TrailMateTalentPreview", UIParent, template)
  f:SetFrameStrata("TOOLTIP")
  f:SetSize(PAD * 2 + 3 * COLS * CELL + 2 * TREE_GAP, TOP + ROWS * CELL + 46)
  Theme.panel(f)
  f.title = Theme.label(f, "GameFontNormalLarge")
  f.title:SetPoint("TOPLEFT", PAD + 2, -12)
  f.heads = {}
  for t = 1, 3 do
    local head = Theme.label(f, "GameFontNormal")
    head:SetPoint("TOPLEFT", PAD + (t - 1) * (COLS * CELL + TREE_GAP), -36)
    head:SetWidth(COLS * CELL)
    head:SetJustifyH("CENTER")
    f.heads[t] = head
  end
  f.note = Theme.label(f, "GameFontHighlightSmall")
  f.note:SetPoint("BOTTOMLEFT", PAD + 2, 12)
  f.note:SetWidth(PAD * -2 + 3 * COLS * CELL + 2 * TREE_GAP)
  f.note:SetTextColor(Theme.rgb(Theme.COLORS.muted))
  f:Hide()
  frame = f
  return f
end

local function node(i)
  if nodes[i] then
    return nodes[i]
  end
  local n = {}
  n.border = frame:CreateTexture(nil, "BORDER")
  n.border:SetTexture(ns.Theme.FLAT)
  n.border:SetSize(ICON + 4, ICON + 4)
  n.icon = frame:CreateTexture(nil, "ARTWORK")
  n.icon:SetSize(ICON, ICON)
  n.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  n.level = frame:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
  n.level:SetPoint("TOPLEFT", n.icon, "TOPLEFT", 1, -1)
  n.rank = frame:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
  n.rank:SetPoint("BOTTOMRIGHT", n.icon, "BOTTOMRIGHT", 0, 1)
  nodes[i] = n
  return n
end

local function hideNodes(from)
  for i = from, #nodes do
    local n = nodes[i]
    n.border:Hide()
    n.icon:Hide()
    n.level:Hide()
    n.rank:Hide()
  end
end

--- What a template does to each talent, from Talents.preview: by talent
--- name, the first level it gets a point and the rank it ends at.
function TalentPreview.plan(preview)
  local out = {}
  for _, g in ipairs(preview.levels) do
    local name = g.talent.name
    local e = out[name]
    if not e then
      out[name] = { first = g.from, rank = g.rankTo }
    else
      e.rank = g.rankTo
    end
  end
  return out
end

--- Shows the picture next to owner. tabs: the player's trees (ranks taken
--- now); template and preview (Talents.preview) of the hovered template.
function TalentPreview.show(owner, template, tabs, preview, L)
  local f = frame or create()
  local planned = TalentPreview.plan(preview)
  f.title:SetText(L[template.label] .. "   " .. preview.split)
  local used = 0
  for t, tab in ipairs(tabs) do
    if t > 3 then
      break
    end
    local r, g, b = color(t)
    local head = f.heads[t]
    head:SetText(("%s  %d"):format(tab.name, preview.trees[t] and preview.trees[t].points or 0))
    head:SetTextColor(r, g, b)
    local left = PAD + (t - 1) * (COLS * CELL + TREE_GAP)
    for _, talent in ipairs(tab.talents) do
      if talent.column >= 1 and talent.column <= COLS and talent.tier >= 1 and talent.tier <= ROWS then
        used = used + 1
        local n = node(used)
        local x = left + (talent.column - 1) * CELL + (CELL - ICON) / 2
        local y = -TOP - (talent.tier - 1) * CELL - (CELL - ICON) / 2
        n.icon:ClearAllPoints()
        n.icon:SetPoint("TOPLEFT", f, "TOPLEFT", x, y)
        n.border:ClearAllPoints()
        n.border:SetPoint("CENTER", n.icon, "CENTER")
        n.icon:SetTexture(talent.icon)
        local p, have = planned[talent.name], (talent.rank or 0) > 0
        if p then
          -- Taken by the template: in colour, with the level and final rank.
          n.icon:SetDesaturated(false)
          n.icon:SetAlpha(1)
          n.border:SetVertexColor(r, g, b, 1)
          n.level:SetText(p.first)
          n.level:SetTextColor(1, 0.82, 0)
          n.level:Show()
          n.rank:SetText(("%d/%d"):format(p.rank, talent.maxRank))
          n.rank:SetTextColor(1, 1, 1)
          n.rank:Show()
        else
          n.icon:SetDesaturated(true)
          n.icon:SetAlpha(have and 0.8 or 0.35)
          n.border:SetVertexColor(0.2, 0.2, 0.2, 1)
          n.level:Hide()
          if have then
            n.rank:SetText(("%d/%d"):format(talent.rank, talent.maxRank))
            n.rank:Show()
          else
            n.rank:Hide()
          end
        end
        -- What you already have: green rank.
        if have then
          n.rank:SetTextColor(0.4, 1, 0.4)
        end
        n.border:Show()
        n.icon:Show()
      end
    end
  end
  hideNodes(used + 1)
  f.note:SetText(L["Number: level the talent is taken at. Bottom: rank it ends at (green: you have it)."])
  f:ClearAllPoints()
  f:SetPoint("TOPLEFT", owner, "TOPRIGHT", 6, 0)
  f:Show()
  TalentPreview.shown = used
end

function TalentPreview.hide()
  if frame then
    frame:Hide()
  end
end
