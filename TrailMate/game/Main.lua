-- Wiring: saved variables, game events, slash commands.
-- TrailMate advises and never plays: nothing here presses keys, moves the
-- character, buys, sells or trains. It only reads the game and shows text.

local addonName, ns = ...
local L = ns.L
local Api, Plan, Builder, Trainer = ns.Api, ns.Plan, ns.Builder, ns.Trainer

local cdb -- TrailMateCharDB, per character
local plan, progress, current, statuses
local arrowStep, markMethod
local lastAdvice = {}
local warnedFull = false
local questThrottle = ns.Throttle.new(0.3)
local bagThrottle = ns.Throttle.new(1)
local clock, sinceMove, sinceTarget, sinceArrow = 0, 0, 0, 0

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

-- Where the current step wants you: its own point, or where the game points
-- for its quest right now (objective area, or the turn-in once complete).
local function stepTarget(step)
  if not step then
    return nil
  end
  if step.mapID then
    return { mapID = step.mapID, x = step.x, y = step.y }
  end
  if step.questID then
    return Api.questTarget(step.questID)
  end
  return nil
end

local function updateTarget(force)
  local step = current and plan and plan.steps[current] or nil
  if step == arrowStep and not force then
    return
  end
  local changed = step ~= arrowStep
  arrowStep = step
  local target = stepTarget(step)
  ns.Arrow.setTarget(target, step and step.text)
  if changed then
    local focused = Api.focusQuest(step and step.questID)
    if target then
      markMethod = Api.setArrow(target, step.text, focused)
    else
      Api.clearArrow()
      markMethod = focused and "quest" or nil
    end
  end
end

local buildFromQuestLog

local function refresh()
  if not plan then
    ns.UI.render(nil, nil, nil, L)
    ns.Arrow.setTarget(nil)
    return
  end
  local ok, cur, st = pcall(Plan.evaluate, plan, progress, facts())
  if not ok then
    return
  end
  local finishedNow = current ~= nil and cur == nil
  current, statuses = cur, st
  if finishedNow then
    if Builder.isAuto(plan) and cdb.prefs.autoPlan ~= false then
      buildFromQuestLog(true)
      return
    end
    say(L["Plan finished."])
  end
  updateTarget()
  ns.UI.render(plan, current, statuses, L, markMethod)
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

local function names(list, limit)
  local out = {}
  for i, e in ipairs(list) do
    if i > limit then
      out[#out + 1] = "..."
      break
    end
    out[#out + 1] = e.title and ("%s (%s)"):format(e.title, e.reason) or ("%s (%d)"):format(e.zone, e.count)
  end
  return table.concat(out, ", ")
end

-- Tells the player what the route decided and what it left out.
local function sayReport(report)
  if report.zone then
    say(L["Route: %s, %d steps."]:format(report.zone, plan and #plan.steps or 0))
  end
  if #report.notNow > 0 then
    say(L["Not now: %s"]:format(names(report.notNow, 6)))
  end
  if #report.abandon > 0 then
    say(L["Consider abandoning: %s"]:format(names(report.abandon, 6)))
  end
  if #report.later > 0 then
    say(L["Later: %s"]:format(names(report.later, 5)))
  end
end

function buildFromQuestLog(quiet)
  local quests = Api.questLog()
  local zoneNames = {}
  for _, q in ipairs(quests) do
    q.target = Api.questTarget(q.questID)
    local m = q.target and q.target.mapID
    if m then
      zoneNames[m] = zoneNames[m] or Api.mapName(m) or ("map " .. m)
      q.zone = zoneNames[m]
    end
  end
  local mapID, x, y = Api.position()
  local p, report = Builder.fromQuestLog(quests, { mapID = mapID, x = x, y = y, level = Api.level() }, L,
    Api.availableQuests(mapID))
  if p and (not quiet or (report.zone and report.zone ~= cdb.lastZone)) then
    quiet = false
  end
  if not p then
    plan, progress, current = nil, nil, nil
    cdb.plan, cdb.progress = nil, nil
    arrowStep = nil
    Api.clearArrow()
    refresh()
    if not quiet then
      say(L["Nothing worth doing in your quest log right now."])
      sayReport(report)
    end
    return
  end
  loadPlan(p, true)
  if not quiet then
    sayReport(report)
  end
  cdb.lastZone = report.zone
end

local function planHasQuest(questID)
  for _, step in ipairs(plan and plan.steps or {}) do
    if step.questID == questID then
      return true
    end
  end
  return false
end

local function clearPlan()
  plan, progress, current, statuses = nil, nil, nil, nil
  cdb.plan, cdb.progress = nil, nil
  arrowStep = nil
  Api.clearArrow()
  Api.unfocusQuest()
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

-- Trainer ---------------------------------------------------------------------

local function adviseTrainer()
  local services = Api.trainerServices()
  Trainer.remember(cdb.trainerMemory, services)
  local results, spend = Trainer.advise(services, {
    class = Api.class(), level = Api.level(), money = Api.money(), prefs = cdb.prefs,
  }, L)
  lastAdvice = results
  if #results == 0 then
    say(L["Nothing new to learn here."])
    return
  end
  say(L["Trainer advice"] .. ":")
  for i, r in ipairs(results) do
    print(("  [%d] %s%s|r %s (%s) - %s"):format(i, COLORS[r.verdict] or "", L[r.verdict], r.name,
      ns.formatMoney(r.cost), r.reason))
  end
  say(L["Total to learn now: %s"]:format(ns.formatMoney(spend)))
  say(L["Not interested in one? /tm ignore <number>. Already learned? /tm learned <number>."])
end

-- "3" means entry 3 of the last trainer list; anything else is a spell name.
local function pickSpell(rest)
  local n = tonumber(rest)
  if n then
    local r = lastAdvice[n]
    return r and r.key, r and r.name
  end
  if rest and rest ~= "" then
    return rest, rest
  end
  return nil
end

local function remindAtLevel(level)
  local names = Trainer.newAtLevel(cdb.trainerMemory, level, cdb.prefs.ignored)
  if #names > 0 then
    say(L["Level %d: your trainer now has %s."]:format(level, table.concat(names, ", ")))
  end
end

-- Vendor ----------------------------------------------------------------------

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
  { "/tm ignore | ignorar <n|name>", "Never recommend that spell again (all ranks)" },
  { "/tm learned | aprendido <n|name>", "Stop reminding a spell you already have" },
  { "/tm unignore | recuperar <name>", "Recommend an ignored spell again" },
  { "/tm ignored | ignorados", "List ignored spells" },
  { "/tm vendor | vender", "What to sell, keep or auction" },
  { "/tm status | estado", "Character summary" },
  { "/tm tracking on|off  (rastreos si|no)", "Skip hunter tracking spells" },
  { "/tm reserve | reserva <gold>", "Gold the trainer advice never spends" },
  { "/tm arrow | flecha on|off", "Show or hide the arrow" },
  { "/tm auto on|off", "Rebuild the plan by itself when it ends" },
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

alias({ "questlog", "diario" }, function()
  buildFromQuestLog(false)
end)
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
alias({ "ignore", "ignorar" }, function(rest)
  local key, name = pickSpell(rest)
  if not key then
    say(L["Which one? Use the number from the trainer list or the spell name."])
    return
  end
  cdb.prefs.ignored[key] = true
  say(L["Ignored: %s. It will not be recommended again."]:format(name))
end)
alias({ "unignore", "recuperar" }, function(rest)
  local key, name = pickSpell(rest)
  if key and cdb.prefs.ignored[key] then
    cdb.prefs.ignored[key] = nil
    say(L["%s will be recommended again."]:format(name))
  else
    say(L["Not in your ignored list."])
  end
end)
alias({ "ignored", "ignorados" }, function()
  local names = {}
  for key in pairs(cdb.prefs.ignored) do
    names[#names + 1] = key
  end
  table.sort(names)
  say(#names > 0 and table.concat(names, ", ") or L["Not in your ignored list."])
end)
alias({ "learned", "aprendido" }, function(rest)
  local n = tonumber(rest)
  local name = n and lastAdvice[n] and lastAdvice[n].name or rest
  if name and cdb.trainerMemory[name] then
    cdb.trainerMemory[name] = nil
    say(L["Marked as learned: %s"]:format(name))
  else
    say(L["Which one? Use the number from the trainer list or the spell name."])
  end
end)
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
alias({ "arrow", "flecha" }, function(rest)
  cdb.arrow.disabled = not yes(rest)
  ns.Arrow.update()
end)
alias({ "auto" }, function(rest)
  cdb.prefs.autoPlan = yes(rest)
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
  cdb.prefs.ignored = cdb.prefs.ignored or {}
  cdb.trainerMemory = cdb.trainerMemory or {}
  cdb.ui = cdb.ui or {}
  cdb.arrow = cdb.arrow or {}
  ns.setLocale(GetLocale and GetLocale() or "enUS")
  ns.UI.create(cdb.ui)
  ns.Arrow.create(cdb.arrow, L)
  if cdb.plan then
    loadPlan(cdb.plan, true)
  else
    refresh()
  end
end

-- On login and /reload, an automatic plan is rebuilt from the current quest
-- log (once the log has loaded), so an old plan never lingers.
local rebuildPending = false

handlers.PLAYER_ENTERING_WORLD = function(isLogin, isReload)
  if cdb then
    arrowStep = false
    if (isLogin or isReload or isLogin == nil) and plan and Builder.isAuto(plan) and cdb.prefs.autoPlan ~= false then
      rebuildPending = true
    end
    questThrottle:mark()
  end
end

local function questChangedAfterLogin()
  if rebuildPending then
    rebuildPending = false
    after(1, function()
      cdb.lastZone = nil
      buildFromQuestLog(true)
    end)
  end
end

local function questChanged()
  questThrottle:mark()
end
handlers.QUEST_LOG_UPDATE = function()
  questChangedAfterLogin()
  questChanged()
end
handlers.QUEST_TURNED_IN = questChanged
handlers.QUEST_REMOVED = questChanged
handlers.ZONE_CHANGED_NEW_AREA = questChanged

-- A quest picked up outside the plan: rebuild an automatic plan so it joins.
handlers.QUEST_ACCEPTED = function(a, b)
  local questID = b or a
  if plan and Builder.isAuto(plan) and cdb.prefs.autoPlan ~= false and not planHasQuest(questID) then
    after(0.5, function()
      buildFromQuestLog(true)
    end)
  end
  questThrottle:mark()
end

handlers.PLAYER_LEVEL_UP = function(level)
  questThrottle:mark()
  if type(level) == "number" and cdb then
    remindAtLevel(level)
  end
end

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
  sinceTarget = sinceTarget + elapsed
  sinceArrow = sinceArrow + elapsed
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
  -- Quest objectives move (next area, turn-in): look again every two seconds.
  if sinceTarget >= 2 then
    sinceTarget = 0
    if plan and current then
      updateTarget(true)
    end
  end
  if sinceArrow >= 0.05 then
    sinceArrow = 0
    ns.Arrow.update()
  end
end)
