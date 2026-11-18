-- The chat with your AI companion: a small window with the conversation and
-- a box to write in. Messages go to trailmate-bridge on your PC and the
-- answers come back through the inbox addons (core/Link.lua explains how).
-- Without the bridge, the window says so; nothing else changes.

local _, ns = ...

local Chat = {}
ns.Chat = Chat

local WIDTH, HEIGHT = 380, 300
local KEEP = 40 -- lines of conversation kept between sessions
local STATUS = {
  idle = "Write a question and press Enter.",
  sending = "Sending to the bridge...",
  nobridge = "The bridge does not answer: is trailmate-bridge running on your PC?",
  thinking = "Your companion is thinking...",
  error = "Your companion could not answer: %s",
  noreply = "No answer after three minutes. Try again.",
  combat = "In combat: the chat waits.",
  exhausted = "All inboxes used: type /reload to go on.",
  noinbox = "No inbox addons: run \"trailmate-bridge init\" and restart the game.",
  nokeys = "The keys the chat uses are taken (Ctrl+Alt+Shift+F5 to F8).",
}

local function api()
  local Api = ns.Api
  return {
    getAction = Api.bindingAction,
    setBinding = Api.setBinding,
    save = Api.saveBindings,
    combat = Api.inCombat,
    loadAddOn = Api.loadAddOn,
  }
end

--- saved: TrailMateCharDB.chat ({ lines, pos }); context(): the
--- character's state as text, sent with the first question and whenever it
--- changes.
function Chat.init(saved, L, context)
  Chat.saved, Chat.L, Chat.context = saved, L, context
  saved.lines = saved.lines or {}
  saved.pos = saved.pos or {}
  local random = math.random
  if type(time) == "function" then
    math.randomseed(time())
    random(); random()
  end
  Chat.link = ns.Link.new(api(), { session = ns.Link.newSession(random), onReply = Chat.reply })
  -- Frames a previous session left on the keys go first.
  if not ns.Api.inCombat() then
    Chat.link:scrub()
  end
end

-- The inbox addons call this while they load: data only, checked by the link.
function TrailMate_Inbox(payload)
  if Chat.link then
    Chat.link:receive(payload)
  end
end

local function add(who, text)
  local lines = Chat.saved.lines
  lines[#lines + 1] = { who = who, text = text }
  while #lines > KEEP do
    table.remove(lines, 1)
  end
  if Chat.frame then
    Chat.showLine(lines[#lines])
  end
end

function Chat.showLine(line)
  local Theme, L = ns.Theme, Chat.L
  local f = Chat.frame
  if line.who == "me" then
    local r, g, b = Theme.rgb(Theme.GOLD)
    f.history:AddMessage(L["You: %s"]:format(line.text), r, g, b)
  else
    local r, g, b = Theme.rgb(Theme.ACCENT)
    f.history:AddMessage(L["Companion: %s"]:format(line.text), r, g, b)
  end
end

--- An answer arrived: shown in the window, which opens if it was closed.
function Chat.reply(text)
  add("companion", text)
  if Chat.frame and not Chat.frame:IsShown() then
    Chat.frame:Show()
  end
  if ns.Api.notice then
    pcall(ns.Api.notice, Chat.L["Your companion answered."])
  end
end

--- Sends a question, with the character's context if it changed.
function Chat.ask(text)
  text = (text or ""):gsub("^%s+", ""):gsub("%s+$", "")
  if text == "" or not Chat.link then
    return false
  end
  local ctx = Chat.context and Chat.context() or ""
  if ctx ~= "" and ctx ~= Chat.lastContext then
    -- The context fits in one message: cut it, never the question.
    local max = ns.Link.MAX_PAYLOAD * ns.Link.MAX_PARTS - 1
    if Chat.link:send("C", ctx:sub(1, max)) then
      Chat.lastContext = ctx
    end
  end
  local ok = Chat.link:send("M", text)
  if ok then
    add("me", text)
  else
    add("companion", Chat.L["That is too long: write less, please."])
  end
  return ok
end

--- Starts a new conversation (the companion forgets the old one).
function Chat.restart()
  if Chat.link then
    Chat.link:send("N")
    Chat.lastContext = nil
    add("companion", Chat.L["New conversation."])
  end
end

function Chat.create()
  if Chat.frame then
    return Chat.frame
  end
  local Theme, L = ns.Theme, Chat.L
  local template = BackdropTemplateMixin and "BackdropTemplate" or nil
  local f = CreateFrame("Frame", "TrailMateChat", UIParent, template)
  f:SetSize(WIDTH, HEIGHT)
  local pos = Chat.saved.pos
  f:SetPoint(pos.point or "CENTER", UIParent, pos.relPoint or "CENTER", pos.x or 260, pos.y or 0)
  f:SetFrameStrata("MEDIUM")
  Theme.panel(f)
  Theme.header(f, L["Companion"], 26)
  Theme.movable(f, pos)
  local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", -4, -4)
  f.status = Theme.label(f, "GameFontHighlightSmall")
  f.status:SetPoint("TOPLEFT", 16, -42)
  f.status:SetWidth(WIDTH - 32)
  f.status:SetTextColor(Theme.rgb(Theme.COLORS.muted))

  local history = CreateFrame("ScrollingMessageFrame", nil, f)
  history:SetPoint("TOPLEFT", 16, -64)
  history:SetPoint("BOTTOMRIGHT", -16, 64)
  history:SetFontObject(ChatFontNormal)
  history:SetJustifyH("LEFT")
  history:SetFading(false)
  history:SetMaxLines(200)
  history:EnableMouseWheel(true)
  history:SetScript("OnMouseWheel", function(self, delta)
    if delta > 0 then
      self:ScrollUp()
    else
      self:ScrollDown()
    end
  end)
  f.history = history

  local input = CreateFrame("EditBox", "TrailMateChatInput", f, "InputBoxTemplate")
  input:SetPoint("BOTTOMLEFT", 22, 36)
  input:SetSize(WIDTH - 44, 22)
  input:SetAutoFocus(false)
  input:SetMaxLetters(500)
  input:SetScript("OnEnterPressed", function(self)
    if Chat.ask(self:GetText()) then
      self:SetText("")
    end
  end)
  input:SetScript("OnEscapePressed", function(self)
    self:ClearFocus()
  end)
  f.input = input

  local new = Theme.button(f, L["New conversation"], 150, Chat.restart)
  new:SetPoint("BOTTOMLEFT", 16, 10)
  f.new = new

  f:Hide()
  Chat.frame = f
  for _, line in ipairs(Chat.saved.lines) do
    Chat.showLine(line)
  end
  if UISpecialFrames then
    table.insert(UISpecialFrames, "TrailMateChat")
  end
  return f
end

function Chat.toggle()
  local f = Chat.frame or Chat.create()
  f:SetShown(not f:IsShown())
  if f:IsShown() then
    f.input:SetFocus()
  end
end

--- Moves the conversation on and shows how it is going.
function Chat.tick(now)
  if not Chat.link then
    return
  end
  local status = Chat.link:tick(now)
  local f = Chat.frame
  if f and f:IsShown() then
    local text = Chat.L[STATUS[status] or STATUS.idle]
    if status == "error" then
      text = text:format(tostring(Chat.link.error))
    end
    f.status:SetText(text)
  end
  Chat.status = status
end
