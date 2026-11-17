-- Smoke test of the whole addon against a fake game API: loads every file in
-- .toc order, fires events and runs the slash commands. It cannot prove the
-- real client behaves like the fake, but it catches wiring mistakes (typos,
-- nil calls, wrong arguments) before anyone has to find them in-game.

local frames, named, printed
local watched, superTracked = {}, nil
local npcGUID, objectives = nil, {}

local function fakeObject(name)
  local o = { scripts = {}, events = {}, name = name }
  return setmetatable(o, {
    __index = function(_, key)
      if key == "SetScript" then
        return function(self, script, fn) self.scripts[script] = fn end
      elseif key == "RegisterEvent" then
        return function(self, event) self.events[event] = true end
      elseif key == "CreateFontString" or key == "CreateTexture" then
        return function() return fakeObject() end
      elseif key == "SetRotation" then
        return function(self, r) rawset(self, "rotation", r) end
      elseif key == "Show" then
        return function(self) rawset(self, "visible", true) end
      elseif key == "Hide" then
        return function(self) rawset(self, "visible", false) end
      elseif key == "SetText" then
        return function(self, s) rawset(self, "shown_text", s) end
      elseif key == "GetPoint" then
        return function() return "RIGHT", nil, "RIGHT", -40, 120 end
      end
      return function() end
    end,
  })
end

local quests = {
  { questID = 10, title = "Lobos", isHeader = false },
  { questID = 11, title = "Jabalies", isHeader = false },
}

local function install()
  frames, named, printed = {}, {}, {}
  watched, superTracked = {}, nil
  npcGUID, objectives = nil, {}
  -- Tests that add API pieces of their own must not leak them into the next.
  rawset(_G, "C_QuestLine", nil)
  local env = {
    print = function(...)
      local parts = {}
      for i = 1, select("#", ...) do
        parts[#parts + 1] = tostring((select(i, ...)))
      end
      printed[#printed + 1] = table.concat(parts, " ")
    end,
    CreateFrame = function(_, name)
      local f = fakeObject(name)
      frames[#frames + 1] = f
      if name then
        named[name] = f
      end
      return f
    end,
    UIParent = fakeObject("UIParent"),
    BackdropTemplateMixin = {},
    SlashCmdList = {},
    GetLocale = function() return "esES" end,
    GetBuildInfo = function() return "1.60.1", "70959", "Nov 2026", 16001 end,
    C_AddOns = { GetAddOnMetadata = function() return "0.1.0-dev" end },
    C_Timer = { After = function(_, fn) fn() end },
    time = os.time,
    UnitClass = function() return "Cazador", "HUNTER" end,
    UnitLevel = function() return 8 end,
    GetPlayerFacing = function() return 0 end,
    UnitGUID = function(unit) return unit == "npc" and npcGUID or nil end,
    UnitName = function(unit) return unit == "npc" and npcGUID and "Captain Nials" or nil end,
    UnitXP = function() return 50 end,
    UnitXPMax = function() return 200 end,
    GetMoney = function() return 12345 end,
    C_QuestLog = {
      GetNumQuestLogEntries = function() return #quests end,
      GetInfo = function(i) return quests[i] end,
      IsComplete = function(id) return id == 11 end,
      IsQuestFlaggedCompleted = function() return false end,
      GetQuestsOnMap = function() return { { questID = 10, x = 0.3, y = 0.3 } } end,
      GetLogIndexForQuestID = function(id)
        for i, q in ipairs(quests) do
          if q.questID == id then
            return i
          end
        end
      end,
      GetQuestWatchType = function(id) return watched[id] end,
      AddQuestWatch = function(id) watched[id] = 0 end,
      RemoveQuestWatch = function(id) watched[id] = nil end,
      SetSelectedQuest = function() end,
      GetQuestObjectives = function(id)
        return { { numFulfilled = objectives[id] or 0, finished = false } }
      end,
    },
    C_Map = {
      GetBestMapForUnit = function() return 1429 end,
      GetPlayerMapPosition = function()
        return { GetXY = function() return 0.5, 0.5 end }
      end,
      GetMapWorldSize = function() return 1000, 1000 end,
      CanSetUserWaypointOnMap = function() return true end,
      SetUserWaypoint = function() end,
      ClearUserWaypoint = function() end,
    },
    UiMapPoint = { CreateFromCoordinates = function(m, x, y) return { m, x, y } end },
    C_SuperTrack = {
      SetSuperTrackedUserWaypoint = function() end,
      SetSuperTrackedQuestID = function(id) superTracked = id end,
    },
    C_Container = {
      GetContainerNumSlots = function(bag) return bag == 0 and 2 or 0 end,
      GetContainerItemInfo = function(_, slot)
        if slot == 1 then
          return { itemID = 1, stackCount = 3, quality = 0, isBound = false, hyperlink = "[Junk]" }
        end
      end,
      GetContainerItemQuestInfo = function() return { isQuestItem = false } end,
      GetContainerNumFreeSlots = function(bag) return bag == 0 and 1 or 0, 0 end,
    },
    GetItemInfo = function()
      return "Junk", "[Junk]", 0, 1, 1, "Junk", "Junk", 20, "", 0, 5, 15
    end,
    GetInventoryItemID = function() return nil end,
    GetNumTrainerServices = function() return 2 end,
    GetTrainerServiceInfo = function(i)
      if i == 1 then
        return "Track Beasts", "", "available"
      end
      return "Raptor Strike", "Rank 2", "available"
    end,
    GetTrainerServiceCost = function() return 100 end,
    GetTrainerServiceLevelReq = function() return 4 end,
  }
  for k, v in pairs(env) do
    rawset(_G, k, v)
  end
end

local function loadAddon()
  local ns = {}
  for line in io.lines("TrailMate/TrailMate.toc") do
    if line ~= "" and not line:find("^##") then
      local chunk = assert(loadfile("TrailMate/" .. line:gsub("\\", "/")))
      chunk("TrailMate", ns)
    end
  end
  return ns
end

local function eventFrame()
  for _, f in ipairs(frames) do
    if f.scripts.OnEvent then
      return f
    end
  end
end

local function fire(event, ...)
  local f = eventFrame()
  f.scripts.OnEvent(f, event, ...)
end

local function tick()
  local f = eventFrame()
  f.scripts.OnUpdate(f, 1)
end

local function output()
  return table.concat(printed, "\n")
end

describe("addon smoke test", function()
  before_each(function()
    install()
    rawset(_G, "TrailMateDB", nil)
    rawset(_G, "TrailMateCharDB", nil)
    loadAddon()
    fire("ADDON_LOADED", "TrailMate")
  end)

  it("registers its events and slash command", function()
    assert.is_true(eventFrame().events.QUEST_LOG_UPDATE)
    assert.is_function(_G.SlashCmdList.TRAILMATE)
    assert.equals("/tm", _G.SLASH_TRAILMATE1)
  end)

  it("builds a plan from the quest log and follows it", function()
    _G.SlashCmdList.TRAILMATE("diario")
    tick()
    local window = named.TrailMateFrame
    -- "Lobos" has a place in this zone, "Jabalies" has none: the route stays
    -- in this zone and Jabalies is reported for later.
    assert.equals("Hacer: Lobos", window.step.shown_text)
    assert.matches("Ruta: map 1429, 2 pasos%.", output())
    assert.matches("Después: Lugar desconocido %(1%)", output())
    _G.SlashCmdList.TRAILMATE("salta")
    assert.equals("Entregar: Lobos", window.step.shown_text)
    _G.SlashCmdList.TRAILMATE("salta")
    assert.equals("Plan terminado.", window.step.shown_text)
  end)

  it("highlights the current quest in the log and on the map, and cleans up after itself", function()
    _G.SlashCmdList.TRAILMATE("diario")
    assert.equals(10, superTracked)
    assert.equals(0, watched[10])
    assert.matches("Flecha: quest", named.TrailMateFrame.arrow.shown_text)
    _G.SlashCmdList.TRAILMATE("borrar")
    assert.is_nil(watched[10])
  end)

  it("rebuilds an automatic plan on login and explains the route", function()
    _G.SlashCmdList.TRAILMATE("diario")
    local saved = _G.TrailMateCharDB
    saved.plan.id = "questlog-old"
    saved.progress.planId = "questlog-old"
    install()
    rawset(_G, "TrailMateCharDB", saved)
    loadAddon()
    fire("ADDON_LOADED", "TrailMate")
    fire("PLAYER_ENTERING_WORLD", false, true)
    fire("QUEST_LOG_UPDATE")
    assert.are_not.equal("questlog-old", _G.TrailMateCharDB.plan.id)
    assert.matches("Ruta: map 1429", output())
  end)

  it("does not remove a quest the player was already watching", function()
    watched[10] = 0
    _G.SlashCmdList.TRAILMATE("diario")
    _G.SlashCmdList.TRAILMATE("salta")
    _G.SlashCmdList.TRAILMATE("salta")
    assert.equals(0, watched[10])
  end)

  it("points its own arrow at the current quest with distance and direction", function()
    _G.SlashCmdList.TRAILMATE("diario")
    eventFrame().scripts.OnUpdate(eventFrame(), 0.1)
    local arrow = named.TrailMateArrow
    -- Player at 0.5,0.5 and the quest at 0.3,0.3 on a 1000-yard map:
    -- 283 yards (259 m) to the north-west, a quarter of a right angle to the left.
    assert.equals("259 m", arrow.distance.shown_text)
    assert.is_true(math.abs(arrow.icon.rotation - math.pi / 4) < 1e-9)
    assert.equals("Hacer: Lobos", arrow.label.shown_text)
    _G.SlashCmdList.TRAILMATE("flecha no")
    assert.is_false(arrow.visible)
  end)

  it("adds quest givers shown on the map and rebuilds when a new quest is accepted", function()
    rawset(_G, "C_QuestLine", {
      GetAvailableQuestLines = function()
        return { { questID = 30, questName = "Cartas", x = 0.45, y = 0.5 } }
      end,
    })
    _G.SlashCmdList.TRAILMATE("diario")
    local plan = _G.TrailMateCharDB.plan
    assert.equals("accept-30", plan.steps[1].id)
    -- Picking up a quest that is not in the plan rebuilds it.
    quests[3] = { questID = 31, title = "Nueva", isHeader = false }
    _G.C_QuestLog.GetQuestsOnMap = function()
      return { { questID = 10, x = 0.3, y = 0.3 }, { questID = 31, x = 0.6, y = 0.6 } }
    end
    fire("QUEST_ACCEPTED", 31)
    assert.are_not.equal(plan.id, _G.TrailMateCharDB.plan.id)
    quests[3] = nil
  end)

  it("learns places while you play and uses them later, with no other addon", function()
    npcGUID = "Creature-0-1465-0-12345-2700-0000ABCDEF"
    local atlas = _G.TrailMateDB.atlas

    -- Picking up a quest: who gave it and where.
    quests[3] = { questID = 31, title = "Nueva", isHeader = false }
    fire("QUEST_ACCEPTED", 31)
    assert.equals(2700, atlas.quests[31].startNpc)
    assert.equals("Nueva", atlas.quests[31].title)
    quests[3] = nil

    -- Objectives moving forward: where the quest is done.
    fire("QUEST_LOG_UPDATE")
    tick()
    objectives[10] = 1
    fire("QUEST_LOG_UPDATE")
    tick()
    assert.equals(1, #atlas.quests[10].areas)

    -- Turning in: where it goes back. Then the route knows "Jabalies".
    fire("QUEST_TURNED_IN", 11)
    assert.same({ mapID = 1429, x = 0.5, y = 0.5 }, atlas.quests[11].finish)
    _G.SlashCmdList.TRAILMATE("diario")
    assert.is_nil(output():find("Lugar desconocido", 1, true))

    -- A trainer seen once can be found again.
    fire("TRAINER_SHOW")
    local arrow = named.TrailMateArrow
    _G.SlashCmdList.TRAILMATE("buscar instructor")
    assert.equals("Instructor: Captain Nials", arrow.label.shown_text)
    _G.SlashCmdList.TRAILMATE("plan")
    assert.are_not.equal("Instructor: Captain Nials", arrow.label.shown_text)

    _G.SlashCmdList.TRAILMATE("buscar vuelo")
    assert.matches("aún no ha visto ninguno", output())
  end)

  it("explains the strategy and lets the player pick another zone", function()
    _G.SlashCmdList.TRAILMATE("diario")
    _G.SlashCmdList.TRAILMATE("estrategia")
    assert.matches("Estrategia para nivel 8:", output())
    assert.matches("%[1%] .+ %(%d+%-%d+%) %- ", output())
    assert.matches("sin confirmar en Forever", output())
    _G.SlashCmdList.TRAILMATE("zona 1")
    assert.is_number(_G.TrailMateCharDB.prefs.focusZone)
    _G.SlashCmdList.TRAILMATE("zona auto")
    assert.is_nil(_G.TrailMateCharDB.prefs.focusZone)
    _G.SlashCmdList.TRAILMATE("zona 99")
    assert.matches("Escribe antes /tm estrategia", output())
  end)

  it("lets the player ignore a spell and announces only new ones at level up", function()
    rawset(_G, "GetNumTrainerServices", function() return 3 end)
    rawset(_G, "GetTrainerServiceInfo", function(i)
      if i == 1 then
        return "Aspect of the Monkey", "", "available"
      elseif i == 2 then
        return "Aspect of the Hawk", "", "unavailable"
      end
      return "Serpent Sting", "Rank 2", "unavailable"
    end)
    rawset(_G, "GetTrainerServiceLevelReq", function(i) return i == 1 and 4 or 10 end)
    fire("TRAINER_SHOW")
    assert.matches("%[2%] .*Aspect of the Hawk", output())
    _G.SlashCmdList.TRAILMATE("ignorar 2")
    assert.is_true(_G.TrailMateCharDB.prefs.ignored["Aspect of the Hawk"])
    fire("PLAYER_LEVEL_UP", 10)
    assert.matches("Nivel 10: tu instructor ya tiene Serpent Sting %(Rank 2%)%.", output())
    assert.is_nil(output():find("ya tiene Aspect", 1, true))
    _G.SlashCmdList.TRAILMATE("recuperar Aspect of the Hawk")
    assert.is_nil(_G.TrailMateCharDB.prefs.ignored["Aspect of the Hawk"])
  end)

  it("restores a saved plan after a reload", function()
    _G.SlashCmdList.TRAILMATE("diario")
    local saved = _G.TrailMateCharDB
    install()
    rawset(_G, "TrailMateCharDB", saved)
    loadAddon()
    fire("ADDON_LOADED", "TrailMate")
    assert.equals("Hacer: Lobos", named.TrailMateFrame.step.shown_text)
  end)

  it("advises at the trainer and respects the tracking preference", function()
    fire("TRAINER_SHOW")
    assert.matches("aprende|r Track Beasts", output())
    _G.SlashCmdList.TRAILMATE("rastreos no")
    fire("TRAINER_SHOW")
    assert.matches("sáltalo|r Track Beasts", output())
    assert.matches("Raptor Strike %(Rank 2%)", output())
  end)

  it("advises at the vendor and warns about full bags", function()
    fire("MERCHANT_SHOW")
    assert.matches("Vende por unos 15c: %[Junk%]", output())
    fire("BAG_UPDATE_DELAYED")
    tick()
    assert.matches("Bolsas casi llenas %(1 libres%)", output())
  end)

  it("prints status and diagnostics without personal data", function()
    _G.SlashCmdList.TRAILMATE("estado")
    _G.SlashCmdList.TRAILMATE("diag")
    local out = output()
    assert.matches("Clase HUNTER, nivel 8", out)
    assert.matches("interface 16001", out)
    assert.matches("missing: .*TomTom.AddWaypoint", out)
    assert.is_nil(out:find("Cazador", 1, true))
  end)

  it("saves a valid snapshot on logout", function()
    fire("PLAYER_LOGOUT")
    local snap = _G.TrailMateCharDB.snapshot
    assert.equals(1, snap.schema)
    assert.equals(2, #snap.quests)
  end)

  it("shows the help for unknown commands", function()
    _G.SlashCmdList.TRAILMATE("")
    assert.matches("/tm questlog | diario", output())
    assert.matches("Crea un plan con tu diario de misiones", output())
  end)
end)
