-- Wiring: saved variables, game events, slash commands.
-- TrailMate advises and never plays: nothing here presses keys, moves the
-- character, buys, sells or trains. It only reads the game and shows text.

local addonName, ns = ...
local L = ns.L
local Api, Plan = ns.Api, ns.Plan

local cdb -- TrailMateCharDB, per character
local plan, progress, current, statuses
local arrowStep, arrowMethod
local warnedFull = false
local questThrottle = ns.Throttle.new(0.3)
local bagThrottle = ns.Throttle.new(1)
local clock, sinceMove = 0, 0

local COLORS = {
  learn = "|cff40c040", skip = "|cffc04040", later = "|cffd0a020",
}

local function say(msg)
  print("|cff9b7bd4TrailMate|r: " .. msg)
end

local function facts()
  local log = {}
  for _, q in ipairs(Api.questLog()) do
    log[q.questID] = { complete = q.complete }
  end
  local mapID, x, y = Api.position()
  return { level = Api.level(), mapID = mapID, x = x, y = y, questLog = log, turnedIn = Api.turnedIn }
end

local function updateArrow()
  local step = current and plan and plan.steps[current] or nil
  if step == arrowStep then
    return
  end
  arrowStep = step
  local target
  if step and step.mapID then
    target = { mapID = step.mapID, x = step.x, y = step.y }
  elseif step and step.questID then
    target = Api.questTarget(step.questID)
  end
  if target then
    arrowMethod = Api.setArrow(target, step.text)
  else
    Api.clearArrow()
    arrowMethod = nil
  end
end

local function refresh()
  if not plan then
    ns.UI.render(nil, nil, nil, L)
    return
  end
  local ok, cur, st = pcall(Plan.evaluate, plan, progress, facts())
  if not ok then
    return
  end
  local finishedNow = current ~= nil and cur == nil
  current, statuses = cur, st
  if finishedNow then
    say(L["Plan finished."])
  end
  updateArrow()
  ns.UI.render(plan, current, statuses, L, arrowMethod)
end

local function loadPlan(p, quiet)
  local ok, err = Plan.validate(p)
  if not ok then
    say(L["Plan rejected: %s"]:format(tostring(err)))
    return false
  end
  plan = p
  progress = Plan.ensureProgress(p, cdb.progress)
  cdb.plan, cdb.progress = p, progress
  current, arrowStep = nil, false
  if not quiet then
    say(L["Plan loaded: %s (%d steps)."]:format(p.title or p.id, #p.steps))
  end
  refresh()
  return true
end

local function buildFromQuestLog()
  local quests = Api.questLog()
  for _, q in ipairs(quests) do
    q.target = Api.questTarget(q.questID)
  end
  local mapID, x, y = Api.position()
  local p = ns.Builder.fromQuestLog(quests, { mapID = mapID, x = x, y = y }, L)
  if not p then
    say(L["Your quest log is empty."])
    return
  end
  loadPlan(p)
end

local function clearPlan()
  plan, progress, current, statuses = nil, nil, nil, nil
  cdb.plan, cdb.progress = nil, nil
  arrowStep = nil
  Api.clearArrow()
  refresh()
end

local function takeSnapshot()
  local xp, xpMax = Api.xp()
  local mapID, x, y = Api.position()
  local free, total = Api.bagSpace()
  local snap = ns.State.build({
    class = Api.class(), level = Api.level(), xp = xp, xpMax = xpMax, money = Api.money(),
    mapID = mapID, x = x, y = y, quests = Api.questLog(), items = Api.bagItems(),
    bagsFree = free, bagsTotal = total,
  }, time and time() or nil)
  cdb.snapshot = snap
  return snap
end

local function adviseTrainer()
  local results, spend = ns.Trainer.advise(Api.trainerServices(), {
    class = Api.class(), level = Api.level(), money = Api.money(), prefs = cdb.prefs,
  }, L)
  if #results == 0 then
    say(L["Nothing new to learn here."])
    return
  end
  say(L["Trainer advice"] .. ":")
  for _, r in ipairs(results) do
    print(("  %s%s|r %s (%s) - %s"):format(COLORS[r.verdict] or "", L[r.verdict], r.name,
      ns.formatMoney(r.cost), r.reason))
  end
  say(L["Total to learn now: %s"]:format(ns.formatMoney(spend)))
end

local function adviseVendor()
  local results, value = ns.Bags.advise(Api.bagItems(), { prefs = cdb.prefs }, L)
  local sell, auction = {}, {}
  for _, r in ipairs(results) do
    local label = r.item.link or ("item:" .. r.item.itemID)
    if r.verdict == "sell" then
      sell[#sell + 1] = label
    elseif r.verdict == "auction" then
      auction[#auction + 1] = label
    end
  end
  say(L["Vendor advice"] .. ":")
  if #sell > 0 then
    say(L["Sell for about %s: %s"]:format(ns.formatMoney(value), table.concat(sell, " ")))
  else
    say(L["Nothing to sell."])
  end
  if #auction > 0 then
    say(L["Worth taking to the auction house: %s"]:format(table.concat(auction, " ")))
  end
end

local function checkBags()
  local free = Api.bagSpace()
  if ns.Bags.shouldReturn(free, cdb.prefs) then
    if not warnedFull then
      say(L["Bags almost full (%d free): time to go back to a vendor."]:format(free))
      warnedFull = true
    end
  else
    warnedFull = false
  end
end

local function after(seconds, fn)
  if C_Timer and C_Timer.After then
    C_Timer.After(seconds, fn)
  else
    fn()
  end
end

-- Slash commands ------------------------------------------------------------

local function yes(word)
  word = (word or ""):lower()
  return word == "on" or word == "yes" or word == "si" or word == "sí"
end

local HELP = {
  { "/tm questlog | diario", "Build a plan from your quest log" },
  { "/tm skip | salta", "Skip the current step" },
  { "/tm done | hecho", "Mark the current step as done" },
  { "/tm undo | deshaz", "Undo the last mark" },
  { "/tm trainer | instructor", "Advice at the open trainer" },
  { "/tm vendor | vender", "What to sell, keep or auction" },
  { "/tm status | estado", "Character summary" },
  { "/tm tracking on|off  (rastreos si|no)", "Skip hunter tracking spells" },
  { "/tm reserve | reserva <gold>", "Gold the trainer advice never spends" },
  { "/tm show | hide  (mostrar | ocultar)", "Show or hide the window" },
  { "/tm clear | borrar", "Remove the plan" },
  { "/tm diag", "What this client exposes (for bug reports)" },
}

local COMMANDS = {}
local function alias(names, fn)
  for _, n in ipairs(names) do
    COMMANDS[n] = fn
  end
end

alias({ "questlog", "diario" }, buildFromQuestLog)
alias({ "skip", "salta" }, function()
  local step = plan and Plan.skip(plan, progress, facts())
  if step then
    say(L["Skipped: %s"]:format(step.text))
  end
  refresh()
end)
alias({ "done", "hecho" }, function()
  local step = plan and Plan.markDone(plan, progress, facts())
  if step then
    say(L["Marked as done: %s"]:format(step.text))
  end
  refresh()
end)
alias({ "undo", "deshaz" }, function()
  say((progress and Plan.undo(progress)) and L["Undone."] or L["Nothing to undo."])
  refresh()
end)
alias({ "trainer", "instructor" }, adviseTrainer)
alias({ "vendor", "vender" }, adviseVendor)
alias({ "status", "estado" }, function()
  for _, line in ipairs(ns.State.summary(takeSnapshot(), L)) do
    say(line)
  end
end)
alias({ "tracking", "rastreos" }, function(rest)
  cdb.prefs.skipTracking = not yes(rest)
  say(L["Tracking spells: %s"]:format(cdb.prefs.skipTracking and L["skip"] or L["learn"]))
end)
alias({ "reserve", "reserva" }, function(rest)
  local gold = tonumber(rest) or 0
  cdb.prefs.reserve = math.max(0, math.floor(gold * 10000))
  say(L["Reserve set to %s."]:format(ns.formatMoney(cdb.prefs.reserve)))
end)
alias({ "show", "mostrar" }, function()
  ns.UI.setShown(true)
end)
alias({ "hide", "ocultar" }, function()
  ns.UI.setShown(false)
end)
alias({ "clear", "borrar" }, clearPlan)
alias({ "diag" }, function()
  local lines = Api.diagnose()
  TrailMateDB.diag = lines
  for _, line in ipairs(lines) do
    say(line)
  end
end)

local function version()
  local fn = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
  local ok, v = pcall(fn, addonName, "Version")
  return ok and v or "?"
end

SLASH_TRAILMATE1 = "/tm"
SLASH_TRAILMATE2 = "/trailmate"
SlashCmdList.TRAILMATE = function(msg)
  local cmd, rest = (msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
  local fn = COMMANDS[(cmd or ""):lower()]
  if fn then
    fn(rest)
    return
  end
  say(("%s %s - %s"):format("TrailMate", version(), L["Commands"]))
  for _, h in ipairs(HELP) do
    print(("  %s  - %s"):format(h[1], L[h[2]]))
  end
end

-- Events ----------------------------------------------------------------------

local frame = CreateFrame("Frame")
local handlers = {}

handlers.ADDON_LOADED = function(name)
  if name ~= addonName then
    return
  end
  TrailMateDB = TrailMateDB or {}
  TrailMateCharDB = TrailMateCharDB or {}
  cdb = TrailMateCharDB
  cdb.prefs = cdb.prefs or {}
  cdb.ui = cdb.ui or {}
  ns.setLocale(GetLocale and GetLocale() or "enUS")
  ns.UI.create(cdb.ui)
  if cdb.plan then
    loadPlan(cdb.plan, true)
  else
    refresh()
  end
end

handlers.PLAYER_ENTERING_WORLD = function()
  if cdb then
    arrowStep = false
    questThrottle:mark()
  end
end

local function questChanged()
  questThrottle:mark()
end
handlers.QUEST_LOG_UPDATE = questChanged
handlers.QUEST_ACCEPTED = questChanged
handlers.QUEST_TURNED_IN = questChanged
handlers.QUEST_REMOVED = questChanged
handlers.PLAYER_LEVEL_UP = questChanged
handlers.ZONE_CHANGED_NEW_AREA = questChanged

handlers.TRAINER_SHOW = function()
  after(0.3, adviseTrainer)
end
handlers.MERCHANT_SHOW = function()
  after(0.3, adviseVendor)
end
handlers.BAG_UPDATE_DELAYED = function()
  bagThrottle:mark()
end
handlers.PLAYER_LOGOUT = function()
  if cdb then
    pcall(takeSnapshot)
  end
end

for event in pairs(handlers) do
  pcall(frame.RegisterEvent, frame, event)
end

frame:SetScript("OnEvent", function(_, event, ...)
  handlers[event](...)
end)

frame:SetScript("OnUpdate", function(_, elapsed)
  if not cdb then
    return
  end
  clock = clock + elapsed
  sinceMove = sinceMove + elapsed
  -- While the current step is a place to reach, look at the position every second.
  if sinceMove >= 1 and plan and current and plan.steps[current].type == "goto" then
    sinceMove = 0
    questThrottle:mark()
  end
  if questThrottle:tick(clock) then
    refresh()
  end
  if bagThrottle:tick(clock) then
    checkBags()
  end
end)
