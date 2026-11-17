-- Wiring: saved variables, game events, slash commands.
-- TrailMate advises and never plays: nothing here presses keys, moves the
-- character, buys, sells or trains. It only reads the game and shows text.
-- It depends on no other addon; TomTom is used only if it is installed.

local addonName, ns = ...
local L = ns.L
local Api, Plan, Builder, Trainer, Atlas = ns.Api, ns.Plan, ns.Builder, ns.Trainer, ns.Atlas

local cdb -- TrailMateCharDB, per character
local atlas -- TrailMateDB.atlas, shared by the account's characters
local plan, progress, current, statuses
local arrowStep, markMethod
local detour -- { target, label }: takes over the arrow for a moment
local lastAdvice = {}
local lastProgress = {}
local lastCounts = {} -- quests worth doing per zone, from the last route
local lastZones = {} -- the numbered list /tm strategy showed
local warnedLevel = {} -- levels already announced as "almost there"
local warnedFull = false
local questThrottle = ns.Throttle.new(0.3)
local bagThrottle = ns.Throttle.new(1)
local clock, sinceMove, sinceTarget, sinceArrow = 0, 0, 0, 0

local COLORS = {
  learn = "|cff40c040", skip = "|cffc04040", later = "|cffd0a020",
}

local lastReportLines, lastVendorLines, travelLines = {}, {}, {}
local hearthing = false -- the hearthstone was just used: learn where it lands

-- Every line TrailMate prints is also kept in the log (panel, Log tab).
local function out(line)
  print(line)
  if TrailMateDB then
    TrailMateDB.log = TrailMateDB.log or {}
    ns.Log.add(TrailMateDB.log, line, date and date("%H:%M") or nil)
  end
end

local function say(msg)
  out("|cff9b7bd4TrailMate|r: " .. msg)
end

local function after(seconds, fn)
  if C_Timer and C_Timer.After then
    C_Timer.After(seconds, fn)
  else
    fn()
  end
end

local function playerPoint()
  local mapID, x, y = Api.position()
  return { mapID = mapID, x = x, y = y, level = Api.level() }
end

local function facts()
  local log = {}
  for _, q in ipairs(Api.questLog()) do
    log[q.questID] = { complete = q.complete }
  end
  local p = playerPoint()
  return { level = p.level, mapID = p.mapID, x = p.x, y = p.y, questLog = log, turnedIn = Api.turnedIn }
end

-- Where to go for a quest: where the game points (objective area, or the
-- turn-in once complete), or else what the atlas learned before.
local function questTarget(questID, complete)
  return Api.questTarget(questID) or (atlas and Atlas.questTarget(atlas, questID, complete, playerPoint()))
end

-- Where the current step wants you: its own point, or its quest's place.
local function stepTarget(step)
  if not step then
    return nil
  end
  if step.mapID then
    return { mapID = step.mapID, x = step.x, y = step.y }
  end
  if step.questID then
    return questTarget(step.questID, step.type == "turnin")
  end
  return nil
end

local function updateTarget(force)
  if detour then
    ns.Arrow.setTarget(detour.target, detour.label)
    return
  end
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

-- Learning ------------------------------------------------------------------

-- Records where quest objectives move forward, so next time (or on an alt)
-- the arrow knows where a quest is done.
local function learnProgress()
  if not atlas then
    return
  end
  local p
  for _, q in ipairs(Api.questLog()) do
    local now = Api.questProgress(q.questID)
    local before = lastProgress[q.questID]
    if now and before and now > before then
      p = p or playerPoint()
      Atlas.recordProgress(atlas, q.questID, p)
    end
    lastProgress[q.questID] = now
  end
end

local function learnNpc(role, class)
  local npc = Api.npc()
  if npc and atlas then
    npc.role, npc.class, npc.faction = role, class, Api.faction()
    Atlas.recordNpc(atlas, npc, playerPoint())
  end
end

local function questInfo(questID)
  for _, q in ipairs(Api.questLog()) do
    if q.questID == questID then
      return q
    end
  end
  return nil
end

-- Plan --------------------------------------------------------------------------

local buildFromQuestLog

-- The step window shows the trip while travelling to a chosen zone.
local function render()
  if detour and detour.zone then
    ns.UI.renderTravel(travelLines, L)
  else
    ns.UI.render(plan, current, statuses, L, markMethod)
  end
end

local function refresh()
  if not plan then
    render()
    if not detour then
      ns.Arrow.setTarget(nil)
    end
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
  render()
  ns.Panel.refresh()
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

local function joinNames(list, limit)
  local parts = {}
  for i, e in ipairs(list) do
    if i > limit then
      parts[#parts + 1] = "..."
      break
    end
    parts[#parts + 1] = e.title and ("%s (%s)"):format(e.title, e.reason) or ("%s (%d)"):format(e.zone, e.count)
  end
  return table.concat(parts, ", ")
end

-- Tells the player what the route decided and what it left out.
local function sayReport(report)
  local lines = {}
  if report.zone then
    lines[#lines + 1] = L["Route: %s, %d steps."]:format(report.zone, plan and #plan.steps or 0)
  end
  if #report.notNow > 0 then
    lines[#lines + 1] = L["Not now: %s"]:format(joinNames(report.notNow, 6))
  end
  if #report.abandon > 0 then
    lines[#lines + 1] = L["Consider abandoning: %s"]:format(joinNames(report.abandon, 6))
  end
  if #report.later > 0 then
    lines[#lines + 1] = L["Later: %s"]:format(joinNames(report.later, 5))
  end
  lastReportLines = lines
  for _, line in ipairs(lines) do
    say(line)
  end
end

local function zoneName(names, mapID)
  names[mapID] = names[mapID] or Api.mapName(mapID) or ("map " .. mapID)
  return names[mapID]
end

-- Quests to pick up nearby: the ones the game shows, plus the ones the atlas
-- saw before (on this character or an alt) that fit the player now.
local function offersHere(player, quests, names)
  local inLog = {}
  for _, q in ipairs(quests) do
    inLog[q.questID] = true
  end
  local offers, seen = {}, {}
  local function addAll(list)
    for _, o in ipairs(list) do
      if not seen[o.questID] then
        seen[o.questID] = true
        o.zone = o.target and zoneName(names, o.target.mapID)
        offers[#offers + 1] = o
      end
    end
  end
  addAll(Api.availableQuests(player.mapID))
  if atlas then
    addAll(Atlas.offers(atlas, {
      level = player.level or 1,
      faction = Api.faction(),
      isDone = function(id)
        return Api.turnedIn(id) == true
      end,
      inLog = function(id)
        return inLog[id] == true
      end,
    }, player))
  end
  return offers
end

function buildFromQuestLog(quiet)
  local quests = Api.questLog()
  local names = {}
  local player = playerPoint()
  for _, q in ipairs(quests) do
    q.target = questTarget(q.questID, q.complete)
    if q.target then
      q.zone = zoneName(names, q.target.mapID)
    end
  end
  local p, report = Builder.fromQuestLog(quests, player, L, offersHere(player, quests, names), {
    zoneBonus = ns.Strategy.zoneBonus(player.level),
    focus = cdb.prefs.focusZone,
  })
  lastCounts = report.counts or {}
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

-- Finding NPCs the atlas knows ---------------------------------------------------

local FIND = {
  trainer = { role = "trainer", ownClass = true, label = "Trainer: %s" },
  instructor = { role = "trainer", ownClass = true, label = "Trainer: %s" },
  vendor = { role = "vendor", label = "Vendor: %s" },
  vendedor = { role = "vendor", label = "Vendor: %s" },
  repair = { role = "repair", label = "Repairs: %s" },
  reparar = { role = "repair", label = "Repairs: %s" },
  flight = { role = "flight", label = "Flight master: %s" },
  vuelo = { role = "flight", label = "Flight master: %s" },
}

local function backToPlan()
  if detour then
    detour = nil
    arrowStep = false
    refresh()
  end
end

local function findNpc(rest)
  local what = FIND[(rest or ""):lower()] or FIND.trainer
  local point, name = Atlas.findNpc(atlas, what.role, what.ownClass and Api.class() or nil, Api.faction(),
    playerPoint())
  if not point then
    say(L["TrailMate has not seen one yet. Visit one and it will remember it."])
    return
  end
  local label = L[what.label]:format(name or "?")
  detour = { target = point, label = label }
  Api.setArrow(point, label, false)
  ns.Arrow.setTarget(point, label)
  say(("%s - %s"):format(label, Api.mapName(point.mapID) or ""))
end

-- Strategy ----------------------------------------------------------------------

local function zoneLine(i, z)
  local quests = z.quests > 0 and (", " .. L["%d quests in your log"]:format(z.quests)) or ""
  return ("[%d] %s (%d-%d) - %s%s"):format(i, Api.mapName(z.mapID) or z.name, z.min, z.max, L[z.difficulty], quests)
end

-- Works out the zone list (numbered for /tm zone) and the "coming up" text.
local function strategyList()
  local level = Api.level()
  if type(level) ~= "number" then
    return {}, "", false
  end
  local advice = ns.Strategy.advise(level, Api.faction(), playerPoint().mapID, lastCounts)
  lastZones = {}
  if advice.best then
    lastZones[1] = advice.best
  end
  for i = 1, math.min(#advice.options, 5) do
    lastZones[#lastZones + 1] = advice.options[i]
  end
  for _, z in ipairs(lastZones) do
    z.label = Api.mapName(z.mapID) or z.name
  end
  local soon = {}
  for _, z in ipairs(advice.upcoming) do
    soon[#soon + 1] = ("%s (%d)"):format(Api.mapName(z.mapID) or z.name, z.min)
  end
  local upcoming = #soon > 0 and L["Coming up: %s"]:format(table.concat(soon, ", ")) or ""
  return lastZones, upcoming, advice.leaveHere
end

local function sayStrategy()
  local level = Api.level()
  if type(level) ~= "number" then
    return
  end
  local zones, upcoming, leaveHere = strategyList()
  say(L["Strategy for level %d:"]:format(level))
  for i, z in ipairs(zones) do
    out("  " .. zoneLine(i, z))
  end
  if leaveHere then
    say(L["This zone is too easy for you now: time to move on."])
  end
  if upcoming ~= "" then
    say(upcoming)
  end
  say(L["Want another zone? /tm zone <number>. Back to automatic: /tm zone auto."])
  if not ns.Zones.VERIFIED_IN_FOREVER then
    say(L["Zone levels are the classic ones, not yet confirmed in Forever."])
  end
end

-- Travel ---------------------------------------------------------------------

local function nodeTarget(n)
  return { mapID = n.mapID, x = n.mx, y = n.my }
end

-- Where the hearthstone lands: a flight point with the bind's name, or the
-- place the atlas saw it land before.
local function hearthPlace(hearth, nodes)
  for _, n in ipairs(nodes) do
    if n.name:find(hearth.name, 1, true) == 1 then
      hearth.cont, hearth.x, hearth.y = n.cont, n.x, n.y
      return
    end
  end
  local b = Atlas.bind(atlas, hearth.name)
  local w = b and Api.worldPos(b.mapID, b.x, b.y)
  if w then
    hearth.cont, hearth.x, hearth.y = w.cont, w.x, w.y
  end
end

local function describeStep(s, name, hearth)
  if s.kind == "hearth" then
    return L["Use your hearthstone (%s)."]:format(hearth.name)
  elseif s.kind == "fly" then
    return L["Fly from %s to %s."]:format(s.from.name, s.to.name)
      .. (s.confirmed and "" or (" " .. L["(route not confirmed yet)"]))
  elseif s.kind == "ship" then
    return L["%s is on another continent: take a zeppelin or a ship from a capital or port."]:format(name)
      .. (s.via and (" " .. L["Nearest flight master you know: %s."]:format(s.via.name)) or "")
  elseif s.to and s.to.name then
    return L["Go to the flight master: %s."]:format(s.to.name)
  end
  return L["Walk to %s."]:format(name)
end

-- Plans the quickest way to a zone with what the game says (flight points
-- learned and seen connected, hearthstone, continent), tells the player the
-- steps and points the arrow at the first place to go.
local function travelTo(mapID, name)
  local p = playerPoint()
  local nodes = Api.flightNodes()
  local hearth = Api.hearth()
  if hearth then
    hearthPlace(hearth, nodes)
  end
  local trip = ns.Travel.plan({
    here = p.mapID and p.x and Api.worldPos(p.mapID, p.x, p.y),
    dest = Api.worldPos(mapID, 0.5, 0.5),
    nodes = nodes,
    hearth = hearth,
    reach = function(a, b)
      return Atlas.reach(atlas, a.name, b.name)
    end,
    speed = (p.level or 1) >= 40 and ns.Travel.MOUNT or ns.Travel.RUN,
  })
  local lines, target = {}, nil
  if trip then
    lines[1] = L["Route to %s (about %s):"]:format(name, ns.Travel.minutes(trip.cost))
    for _, s in ipairs(trip.steps) do
      lines[#lines + 1] = "- " .. describeStep(s, name, hearth)
      if not target then
        if s.kind == "walk" then
          target = s.to.name and nodeTarget(s.to) or { mapID = mapID, x = 0.5, y = 0.5 }
        elseif s.kind == "ship" and s.via then
          target = nodeTarget(s.via)
        end
      end
    end
  else
    lines[1] = L["Travel to %s"]:format(name)
  end
  travelLines = lines
  detour = {
    target = target or { mapID = mapID, x = 0.5, y = 0.5 },
    label = lines[2] and lines[2]:sub(3) or lines[1],
    zone = mapID,
    zoneName = name,
  }
  ns.Arrow.setTarget(detour.target, detour.label)
  for _, line in ipairs(lines) do
    say(line)
  end
  render()
  ns.Panel.refresh()
end

-- The player picks a zone: the route works there, and the travel planner
-- shows the quickest way to get there.
local function chooseZone(rest)
  if (rest or ""):lower() == "auto" then
    cdb.prefs.focusZone = nil
    say(L["Zone choice back to automatic."])
    buildFromQuestLog(false)
    return
  end
  local z = lastZones[tonumber(rest) or 0]
  if not z then
    say(L["Type /tm strategy first, then /tm zone <number>."])
    return
  end
  cdb.prefs.focusZone = z.mapID
  local name = Api.mapName(z.mapID) or z.name
  say(L["Next zone: %s."]:format(name))
  if (lastCounts[z.mapID] or 0) == 0 then
    say(L["No quests of yours there yet: pick some up when you arrive."])
  else
    buildFromQuestLog(true)
  end
  if Api.position() ~= z.mapID then
    travelTo(z.mapID, name)
  end
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
    out(("  [%d] %s%s|r %s (%s) - %s"):format(i, COLORS[r.verdict] or "", L[r.verdict], r.name,
      ns.formatMoney(r.cost), r.reason))
  end
  say(L["Total to learn now: %s"]:format(ns.formatMoney(spend)))
  say(L["Not interested in one? /tm ignore <number>. Already learned? /tm learned <number>."])
  ns.Panel.refresh()
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

-- Near the end of a level: say what the trainer will have, once per level.
local function remindBeforeLevel()
  local level = Api.level()
  local xp, xpMax = Api.xp()
  if type(level) ~= "number" or warnedLevel[level] or not (xp and xpMax and xpMax > 0) or xp / xpMax < 0.9 then
    return
  end
  warnedLevel[level] = true
  local names = Trainer.newAtLevel(cdb.trainerMemory, level + 1, cdb.prefs.ignored)
  if #names > 0 then
    say(L["Almost level %d: your trainer will have %s."]:format(level + 1, table.concat(names, ", ")))
  end
end

local function remindAtLevel(level)
  local names = Trainer.newAtLevel(cdb.trainerMemory, level, cdb.prefs.ignored)
  if #names > 0 then
    say(L["Level %d: your trainer now has %s."]:format(level, table.concat(names, ", ")))
    if Atlas.findNpc(atlas, "trainer", Api.class(), Api.faction(), playerPoint()) then
      say(L["Type /tm find trainer and the arrow takes you there."])
    end
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
  local lines = { L["Vendor advice"] .. ":" }
  if #sell > 0 then
    lines[#lines + 1] = L["Sell for about %s: %s"]:format(ns.formatMoney(value), table.concat(sell, " "))
  else
    lines[#lines + 1] = L["Nothing to sell."]
  end
  if #auction > 0 then
    lines[#lines + 1] = L["Worth taking to the auction house: %s"]:format(table.concat(auction, " "))
  end
  for _, line in ipairs(lines) do
    say(line)
  end
  for i, line in ipairs(lines) do
    lines[i] = ns.Log.plain(line)
  end
  lastVendorLines = lines
  ns.Panel.refresh()
end

local function checkBags()
  local free = Api.bagSpace()
  if ns.Bags.shouldReturn(free, cdb.prefs) then
    if not warnedFull then
      say(L["Bags almost full (%d free): time to go back to a vendor."]:format(free))
      local _, name = Atlas.findNpc(atlas, "vendor", nil, Api.faction(), playerPoint())
      if name then
        say(L["Nearest vendor you know: %s. Type /tm find vendor."]:format(name))
      end
      warnedFull = true
    end
  else
    warnedFull = false
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
  { "/tm find trainer|vendor|repair|flight", "Arrow to the nearest one TrailMate has seen" },
  { "/tm plan", "Arrow back to the plan" },
  { "/tm strategy | estrategia", "Best zones for your level, with difficulty" },
  { "/tm zone <n>|auto  (zona)", "Choose the zone to level in, or let TrailMate choose" },
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
alias({ "find", "buscar" }, findNpc)
alias({ "plan" }, backToPlan)
alias({ "strategy", "estrategia" }, sayStrategy)
alias({ "zone", "zona" }, chooseZone)
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

alias({ "help", "ayuda" }, function()
  say(("%s %s - %s"):format("TrailMate", version(), L["Commands"]))
  for _, h in ipairs(HELP) do
    out(("  %s  - %s"):format(h[1], L[h[2]]))
  end
end)
alias({ "panel" }, function()
  ns.Panel.toggle()
end)

SLASH_TRAILMATE1 = "/tm"
SLASH_TRAILMATE2 = "/trailmate"
SlashCmdList.TRAILMATE = function(msg)
  local cmd, rest = (msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
  cmd = (cmd or ""):lower()
  if cmd == "" then
    ns.Panel.toggle()
    return
  end
  local fn = COMMANDS[cmd] or COMMANDS.help
  fn(rest)
end

-- What the panel reads. It never changes state itself: its buttons run commands.
local function routeLines()
  local lines = {}
  if not plan then
    lines[1] = L["No plan loaded. Type /tm questlog to build one from your quest log."]
  elseif not current then
    lines[1] = L["Plan finished."]
  else
    local step = plan.steps[current]
    lines[#lines + 1] = L["Step %d of %d"]:format(current, #plan.steps) .. ": " .. step.text
    if step.why then
      lines[#lines + 1] = "   " .. step.why
    end
    local shown = 0
    for i = current + 1, #plan.steps do
      if statuses and statuses[i] == "pending" and shown < 6 then
        lines[#lines + 1] = "- " .. plan.steps[i].text
        shown = shown + 1
      end
    end
  end
  if detour then
    lines[#lines + 1] = ""
    for _, line in ipairs(detour.zone and travelLines or { L["Arrow: %s"]:format(detour.label) }) do
      lines[#lines + 1] = line
    end
  end
  lines[#lines + 1] = ""
  for _, line in ipairs(lastReportLines) do
    lines[#lines + 1] = line
  end
  return lines
end

ns.Main = {
  routeLines = routeLines,
  strategy = function()
    local zones, upcoming = strategyList()
    return zones, upcoming
  end,
  trainerAdvice = function()
    return lastAdvice
  end,
  prefs = function()
    return cdb and cdb.prefs or {}
  end,
  vendorLines = function()
    return lastVendorLines
  end,
  logText = function()
    return ns.Log.text(TrailMateDB and TrailMateDB.log)
  end,
  clearLog = function()
    if TrailMateDB then
      TrailMateDB.log = {}
    end
  end,
}

-- Click on TrailMate in the game's addon compartment (the minimap addons list).
function TrailMate_OnAddonCompartmentClick()
  ns.Panel.toggle()
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
  atlas = Atlas.ensure(TrailMateDB)
  cdb.prefs = cdb.prefs or {}
  cdb.prefs.ignored = cdb.prefs.ignored or {}
  cdb.trainerMemory = cdb.trainerMemory or {}
  cdb.ui = cdb.ui or {}
  cdb.arrow = cdb.arrow or {}
  cdb.panel = cdb.panel or {}
  cdb.minimap = cdb.minimap or {}
  TrailMateDB.log = TrailMateDB.log or {}
  ns.setLocale(GetLocale and GetLocale() or "enUS")
  ns.UI.create(cdb.ui)
  ns.Arrow.create(cdb.arrow, L)
  ns.Panel.create(cdb.panel, L)
  ns.MinimapButton.create(cdb.minimap, L, ns.Panel.toggle, function()
    ns.UI.setShown(cdb.ui.hidden == true)
  end)
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

local function questChanged()
  questThrottle:mark()
end

handlers.QUEST_LOG_UPDATE = function()
  if rebuildPending then
    rebuildPending = false
    after(1, function()
      cdb.lastZone = nil
      buildFromQuestLog(true)
    end)
  end
  questChanged()
end
handlers.QUEST_REMOVED = questChanged

handlers.ZONE_CHANGED_NEW_AREA = function()
  -- Just used the hearthstone: learn where it lands.
  if hearthing then
    hearthing = false
    after(2, function()
      local h = Api.hearth()
      if h then
        Atlas.recordBind(atlas, h.name, playerPoint())
      end
    end)
  end
  -- On the way to a chosen zone: plan again from here (after a flight or the hearthstone).
  if detour and detour.zone and Api.position() ~= detour.zone then
    after(2, function()
      if detour and detour.zone then
        travelTo(detour.zone, detour.zoneName or "?")
      end
    end)
  end
  questChanged()
end

handlers.UNIT_SPELLCAST_SUCCEEDED = function(unit, _, spellID)
  if unit == "player" and spellID == 8690 then -- Hearthstone
    hearthing = true
  end
end

handlers.QUEST_ACCEPTED = function(a, b)
  local questID = b or a
  -- Learn who gave it and where.
  local q = questInfo(questID)
  local npc = Api.npc()
  Atlas.recordStart(atlas, questID, {
    title = q and q.title, level = q and q.level, npcID = npc and npc.id, faction = Api.faction(),
  }, playerPoint())
  if npc then
    learnNpc("quest")
  end
  -- A quest picked up outside the plan: rebuild an automatic plan so it joins.
  if plan and Builder.isAuto(plan) and cdb.prefs.autoPlan ~= false and not planHasQuest(questID) then
    after(0.5, function()
      buildFromQuestLog(true)
    end)
  end
  questChanged()
end

handlers.QUEST_TURNED_IN = function(questID)
  local npc = Api.npc()
  Atlas.recordFinish(atlas, questID, { npcID = npc and npc.id }, playerPoint())
  if npc then
    learnNpc("quest")
  end
  lastProgress[questID] = nil
  questChanged()
end

handlers.PLAYER_LEVEL_UP = function(level)
  questChanged()
  if type(level) == "number" and cdb then
    remindAtLevel(level)
  end
end

handlers.TRAINER_SHOW = function()
  backToPlan()
  if Api.isProfessionTrainer() then
    learnNpc("profession")
  else
    learnNpc("trainer", Api.class())
  end
  after(0.3, adviseTrainer)
end
handlers.MERCHANT_SHOW = function()
  learnNpc("vendor")
  if Api.vendorRepairs() then
    learnNpc("repair")
  end
  after(0.3, adviseVendor)
end
handlers.PLAYER_XP_UPDATE = function()
  if cdb then
    remindBeforeLevel()
  end
end
handlers.TAXIMAP_OPENED = function()
  learnNpc("flight")
  -- Learn which flights are open from here, for the travel planner.
  local node, reachable = Api.taxiReach()
  if node then
    Atlas.recordFlights(atlas, node, reachable)
  end
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
    pcall(learnProgress)
    refresh()
  end
  if bagThrottle:tick(clock) then
    checkBags()
  end
  -- Quest objectives move (next area, turn-in): look again every two seconds.
  if sinceTarget >= 2 then
    sinceTarget = 0
    -- Arrived in the zone the player chose: drop the detour and route it.
    if detour and detour.zone and Api.position() == detour.zone then
      detour, arrowStep = nil, false
      buildFromQuestLog(false)
    end
    if detour or (plan and current) then
      updateTarget(true)
    end
  end
  if sinceArrow >= 0.05 then
    sinceArrow = 0
    ns.Arrow.update()
  end
end)
