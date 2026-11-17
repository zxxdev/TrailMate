-- The talent plan, docked to the right of the game's talent window: choose
-- a leveling template (one per tree), see the next talent with its icon,
-- the ones after it, and the next talent lit up in the game's window.
-- It only shows advice: the player clicks the talents.

local _, ns = ...

local TalentPanel = {}
ns.TalentPanel = TalentPanel

local WIDTH, HEIGHT = 250, 430
local CHOICES, ROWS = 4, 7
local GLOW = "Interface\\Buttons\\UI-ActionButton-Border"

--- saved: TrailMateCharDB.talents ({ template = id }).
function TalentPanel.init(saved, L)
  TalentPanel.saved, TalentPanel.L = saved, L
end

local function host()
  return ns.Api.talentHost()
end

--- The advice without any window: chosen template, grouped picks, trees and
--- points to spend. nil when the client shows no talent trees.
function TalentPanel.advice()
  local Api, Talents = ns.Api, ns.Talents
  local tabs, pending = Api.talentTree()
  if #tabs == 0 then
    return nil
  end
  local list = Talents.templates(Api.class(), tabs)
  local chosen = Talents.choose(list, tabs, TalentPanel.saved and TalentPanel.saved.template)
  if not chosen then
    return nil
  end
  local groups = Talents.group(Talents.plan(tabs, chosen, 15))
  local points = math.max(0, (Api.talentPoints() or 0) - (pending or 0))
  return { list = list, chosen = chosen, groups = groups, tabs = tabs, points = points }
end

local function pulse(tex)
  local group = tex.CreateAnimationGroup and tex:CreateAnimationGroup()
  if not group then
    return
  end
  local fade = group:CreateAnimation("Alpha")
  fade:SetFromAlpha(1)
  fade:SetToAlpha(0.35)
  fade:SetDuration(0.7)
  group:SetLooping("BOUNCE")
  group:Play()
end

--- Docks the panel to the talent window once the game has created it.
function TalentPanel.attach()
  if TalentPanel.frame or TalentPanel.failed then
    return TalentPanel.frame
  end
  local parent = host()
  if not (parent and TalentPanel.saved) then
    return nil
  end
  -- If building it fails half way, do not try again every second.
  TalentPanel.failed = true
  local Theme, L = ns.Theme, TalentPanel.L
  local template = BackdropTemplateMixin and "BackdropTemplate" or nil
  local f = CreateFrame("Frame", "TrailMateTalents", parent, template)
  f:SetSize(WIDTH, HEIGHT)
  f:SetPoint("TOPLEFT", parent, "TOPRIGHT", 2, 0)
  Theme.panel(f)
  Theme.header(f, L["Talent plan"], 28)

  f.choices = {}
  for i = 1, CHOICES do
    local b = Theme.button(f, "", WIDTH - 28, function()
      TalentPanel.pick(i)
    end)
    b:SetPoint("TOPLEFT", 14, -44 - (i - 1) * 24)
    b:Hide()
    f.choices[i] = b
  end
  f.note = Theme.label(f, "GameFontHighlightSmall")
  f.note:SetPoint("TOPLEFT", 16, -44 - CHOICES * 24 - 2)
  f.note:SetWidth(WIDTH - 32)
  f.note:SetTextColor(Theme.rgb(Theme.COLORS.muted))

  f.heading = Theme.label(f, "GameFontNormal")
  f.heading:SetPoint("TOPLEFT", 16, -186)
  f.heading:SetWidth(WIDTH - 32)
  f.icon = f:CreateTexture(nil, "ARTWORK")
  f.icon:SetSize(40, 40)
  f.icon:SetPoint("TOPLEFT", 16, -206)
  f.ring = f:CreateTexture(nil, "OVERLAY")
  f.ring:SetTexture(GLOW)
  f.ring:SetBlendMode("ADD")
  f.ring:SetVertexColor(Theme.rgb(Theme.GOLD))
  f.ring:SetSize(74, 74)
  f.ring:SetPoint("CENTER", f.icon, "CENTER")
  f.name = Theme.label(f, "GameFontHighlightLarge")
  f.name:SetPoint("TOPLEFT", f.icon, "TOPRIGHT", 10, -2)
  f.name:SetWidth(WIDTH - 90)
  f.info = Theme.label(f, "GameFontHighlightSmall")
  f.info:SetPoint("TOPLEFT", f.name, "BOTTOMLEFT", 0, -3)
  f.info:SetWidth(WIDTH - 90)
  f.info:SetTextColor(Theme.rgb(Theme.COLORS.muted))
  f.where = Theme.label(f, "GameFontNormalSmall")
  f.where:SetPoint("TOPLEFT", 16, -252)
  f.where:SetWidth(WIDTH - 32)
  f.where:SetTextColor(Theme.rgb(Theme.COLORS.warning))

  f.after = Theme.label(f, "GameFontNormal")
  f.after:SetPoint("TOPLEFT", 16, -272)
  f.after:SetText(L["After that"])
  f.rows = {}
  for i = 1, ROWS do
    local icon = f:CreateTexture(nil, "ARTWORK")
    icon:SetSize(16, 16)
    icon:SetPoint("TOPLEFT", 18, -292 - (i - 1) * 18)
    local text = Theme.label(f, "GameFontHighlightSmall")
    text:SetPoint("LEFT", icon, "RIGHT", 6, 0)
    text:SetWidth(WIDTH - 60)
    f.rows[i] = { icon = icon, text = text }
  end
  f.footer = Theme.label(f, "GameFontDisableSmall")
  f.footer:SetPoint("BOTTOMLEFT", 16, 12)
  f.footer:SetWidth(WIDTH - 32)

  -- Lights up the next talent in the game's own window.
  f.glow = CreateFrame("Frame", nil, f)
  f.glow:SetFrameStrata("HIGH")
  f.glow.tex = f.glow:CreateTexture(nil, "OVERLAY")
  f.glow.tex:SetAllPoints()
  f.glow.tex:SetTexture(GLOW)
  f.glow.tex:SetBlendMode("ADD")
  f.glow.tex:SetVertexColor(Theme.rgb(Theme.GOLD))
  pulse(f.glow.tex)
  f.glow:Hide()

  f:SetScript("OnShow", TalentPanel.refresh)
  if parent.HookScript then
    parent:HookScript("OnShow", TalentPanel.refresh)
  end
  TalentPanel.frame, TalentPanel.failed = f, nil
  TalentPanel.refresh()
  return f
end

function TalentPanel.pick(i)
  local list = TalentPanel.list
  if list and list[i] then
    TalentPanel.saved.template = list[i].id
    TalentPanel.refresh()
    if ns.onTalentsChanged then
      ns.onTalentsChanged()
    end
  end
end

local function showGlow(f, button)
  if not button then
    f.glow:Hide()
    return
  end
  local size = (button.GetWidth and button:GetWidth() or 37) * 1.9
  f.glow:ClearAllPoints()
  f.glow:SetPoint("CENTER", button, "CENTER")
  f.glow:SetSize(size, size)
  f.glow:Show()
end

local function rankText(g, L)
  if g.from == g.to then
    return L["rank %d/%d"]:format(g.to, g.talent.maxRank)
  end
  return L["ranks %d-%d/%d"]:format(g.from, g.to, g.talent.maxRank)
end

function TalentPanel.refresh()
  local f, L = TalentPanel.frame, TalentPanel.L
  if not f then
    return
  end
  local a = TalentPanel.advice()
  TalentPanel.list = a and a.list
  for i, b in ipairs(f.choices) do
    local t = a and a.list[i]
    if t then
      local mark = t == a.chosen and "> " or ""
      b:SetText(mark .. t.label .. (t.difficulty and (" - " .. L[t.difficulty]) or ""))
      b:Show()
    else
      b:Hide()
    end
  end
  if not a then
    f.note:SetText("")
    f.heading:SetText("")
    f.name:SetText(L["This client shows no talent trees."])
    f.info:SetText("")
    f.where:SetText("")
    f.icon:Hide()
    f.ring:Hide()
    showGlow(f, nil)
    return
  end
  local chosen, tab = a.chosen, a.tabs[a.chosen.tree]
  f.note:SetText(chosen.note and L[chosen.note] or L["No template for this tree: it is filled row by row."])
  local first = a.groups[1]
  if not first then
    f.heading:SetText("")
    f.name:SetText(L["This tree is complete."])
    f.info:SetText("")
    f.where:SetText("")
    f.icon:Hide()
    f.ring:Hide()
    showGlow(f, nil)
  else
    local t = first.talent
    f.heading:SetText(a.points > 0 and L["Spend your point here (%d to spend)"]:format(a.points)
      or L["Your next point goes here"])
    f.icon:SetTexture(t.icon)
    f.icon:Show()
    f.ring:SetShown(a.points > 0)
    f.name:SetText(t.name)
    f.info:SetText(L["%s - %s, row %d"]:format(rankText(first, L), tab.name, t.tier))
    local button = a.points > 0 and ns.Api.talentButton(chosen.tree, t) or nil
    showGlow(f, button)
    f.where:SetText(a.points > 0 and not button and L["Open the %s tab to see it lit up."]:format(tab.name) or "")
  end
  for i, row in ipairs(f.rows) do
    local g = a.groups[i + 1]
    if g then
      row.icon:SetTexture(g.talent.icon)
      row.icon:Show()
      row.text:SetText(("%s (%s)"):format(g.talent.name, rankText(g, L)))
    else
      row.icon:Hide()
      row.text:SetText("")
    end
  end
  if chosen.auto then
    f.footer:SetText("")
  else
    local found, total = ns.Talents.found(a.tabs, chosen)
    f.footer:SetText(L["A guide from the classic trees, not checked in Forever: %d of %d names found in yours."]
      :format(found, total))
  end
end
