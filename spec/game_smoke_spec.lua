-- Smoke test of the whole addon against a fake game API: loads every file in
-- .toc order, fires events and runs the slash commands. It cannot prove the
-- real client behaves like the fake, but it catches wiring mistakes (typos,
-- nil calls, wrong arguments) before anyone has to find them in-game.

local frames, named, printed
local notices = {} -- big messages in the middle of the screen
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
      elseif key == "SetTexCoord" then
        return function(self, ...) rawset(self, "texCoord", { ... }) end
      elseif key == "SetVertexColor" then
        return function(self, ...) rawset(self, "color", { ... }) end
      elseif key == "Show" then
        return function(self) rawset(self, "visible", true) end
      elseif key == "Hide" then
        return function(self) rawset(self, "visible", false) end
      elseif key == "IsShown" then
        return function(self) return rawget(self, "visible") == true end
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
  notices = {}
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
    RaidWarningFrame = fakeObject("RaidWarningFrame"),
    RaidNotice_AddMessage = function(_, text) notices[#notices + 1] = text end,
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

  it("keeps working when one part fails to build, and shows the error", function()
    -- The user's case: the window appeared, but nothing after it did.
    install()
    rawset(_G, "TrailMateDB", nil)
    rawset(_G, "TrailMateCharDB", nil)
    local create = _G.CreateFrame
    rawset(_G, "Minimap", fakeObject("Minimap"))
    finally(function()
      rawset(_G, "Minimap", nil)
    end)
    rawset(_G, "CreateFrame", function(kind, name, parent, template)
      if template == "SecureActionButtonTemplate" then
        error("blocked by this client")
      end
      return create(kind, name, parent, template)
    end)
    loadAddon()
    fire("ADDON_LOADED", "TrailMate")
    assert.matches("Error|r item button: .*blocked by this client", output())
    assert.is_table(named.TrailMatePanel) -- the panel was still built
    assert.is_table(named.TrailMateMinimapButton)
    _G.SlashCmdList.TRAILMATE("")
    assert.is_true(named.TrailMatePanel.visible)
    -- The route still works.
    _G.SlashCmdList.TRAILMATE("diario")
    tick()
    assert.equals("Hacer: Lobos", named.TrailMateFrame.step.shown_text)
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
    -- Clicking a next step does it first; the other one stays in the plan.
    local row = window.rows[1]
    assert.equals("- Entregar: Lobos", row.label.shown_text)
    row.scripts.OnClick(row)
    assert.equals("Entregar: Lobos", window.step.shown_text)
    assert.equals("- Hacer: Lobos", window.rows[1].label.shown_text)
    window.rows[1].scripts.OnClick(window.rows[1])
    assert.equals("Hacer: Lobos", window.step.shown_text)
    _G.SlashCmdList.TRAILMATE("salta")
    assert.equals("Entregar: Lobos", window.step.shown_text)
    _G.SlashCmdList.TRAILMATE("salta")
    assert.equals("Plan terminado.", window.step.shown_text)
  end)

  it("highlights the current quest in the log and on the map, and cleans up after itself", function()
    _G.SlashCmdList.TRAILMATE("diario")
    assert.equals(10, superTracked)
    assert.equals(0, watched[10])
    assert.matches("Marca en el mapa: quest", named.TrailMateFrame.arrow.shown_text)
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
    -- An eighth of a turn is cell 16 of 128: first column, second row.
    assert.same({ 0, 1 / 16, 1 / 8, 2 / 8 }, arrow.icon.texCoord)
    assert.is_nil(rawget(arrow.icon, "rotation")) -- the picture is never rotated
    -- A quarter of the way from gold (ahead) to purple (behind).
    local c = arrow.icon.color
    assert.is_true(math.abs(c[1] - (1 + (0.61 - 1) * 0.25)) < 1e-9)
    assert.is_true(math.abs(c[3] - 0.83 * 0.25) < 1e-9)
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

  it("plans the trip to a chosen zone by flight and shows it in the step window", function()
    local function vec(x, y)
      return { x = x, y = y, GetXY = function(self) return self.x, self.y end }
    end
    rawset(_G, "CreateVector2D", vec)
    rawset(_G, "UnitLevel", function() return 33 end)
    -- World in yards: the player's zone around (500, 500); Stranglethorn far south.
    _G.C_Map.GetWorldPosFromMapPos = function(mapID, v)
      if mapID == 1415 then
        return 0, vec(v.x * 100000 - 50000, v.y * 100000 - 50000)
      elseif mapID == 1434 then
        return 0, vec(v.x * 1000, v.y * 1000 - 12000)
      elseif mapID == 1420 then -- Tirisfal, far north: its zeppelin is no shortcut here
        return 0, vec(v.x * 1000, v.y * 1000 + 40000)
      elseif mapID == 1411 or mapID == 1413 then -- Kalimdor
        return 1, vec(v.x * 1000, v.y * 1000)
      end
      return 0, vec(v.x * 1000, v.y * 1000)
    end
    rawset(_G, "C_TaxiMap", {
      GetTaxiNodesForMap = function(mapID)
        if mapID ~= 1415 then
          return {}
        end
        return {
          { name = "Hammerfall", position = vec(0.506, 0.505), state = 1, faction = 1 },
          { name = "Grom'gol", position = vec(0.505, 0.386), state = 1, faction = 1 },
          { name = "Alliance only", position = vec(0.505, 0.39), state = 1, faction = 2 },
        }
      end,
      GetAllTaxiNodes = function()
        return {
          { name = "Hammerfall", state = 0 },
          { name = "Grom'gol", state = 1 },
        }
      end,
    })
    rawset(_G, "Enum", { FlightPathFaction = { Neutral = 0, Horde = 1, Alliance = 2 },
      FlightPathState = { Current = 0, Reachable = 1, Unreachable = 2 } })
    rawset(_G, "UnitFactionGroup", function() return "Horde" end)
    rawset(_G, "GetTaxiMapID", function() return 1415 end)
    _G.SlashCmdList.TRAILMATE("diario")
    _G.SlashCmdList.TRAILMATE("estrategia")
    local index = output():match("%[(%d)%] Stranglethorn Vale")
    assert.is_not_nil(index)
    _G.SlashCmdList.TRAILMATE("zona " .. index)
    local window = named.TrailMateFrame
    assert.equals("Viaje", window.counter.shown_text)
    -- Before any flight master is opened, flights are not assumed: it says so.
    assert.is_nil(output():find("Vuela de", 1, true))
    assert.matches("Abre una vez un maestro de vuelo allí", output())
    assert.matches("Viaje a Stranglethorn Vale %(unos %d+ min%)", output())
    assert.is_nil(output():find("Alliance only", 1, true))
    -- Opening a flight master teaches it this character's flight points and open routes.
    fire("TAXIMAP_OPENED")
    assert.is_true(_G.TrailMateCharDB.learnedFlights[1415]["Grom'gol"])
    printed = {}
    _G.SlashCmdList.TRAILMATE("zona " .. index)
    assert.equals("Ve al maestro de vuelo: Hammerfall.", window.step.shown_text)
    assert.matches("Vuela de Hammerfall a Grom'gol%.$", output():match("[^\n]*Vuela[^\n]*"))
    assert.is_nil(output():find("Abre una vez un maestro de vuelo allí", 1, true))
    _G.SlashCmdList.TRAILMATE("plan")
    assert.equals("Hacer: Lobos", window.step.shown_text)
    rawset(_G, "C_TaxiMap", nil)
    rawset(_G, "CreateVector2D", nil)
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

  it("reaching an even level says to visit the trainer and counts talent points (the user's case)", function()
    rawset(_G, "UnitLevel", function() return 34 end)
    rawset(_G, "UnitCharacterPoints", function() return 1 end)
    fire("PLAYER_LEVEL_UP", 34)
    local out = output()
    assert.matches("Nivel 34: seguramente te esperan hechizos nuevos en tu instructor%.", out)
    assert.matches("Visita tu instructor una vez y TrailMate recordará dónde está%.", out)
    assert.matches("Tienes 1 punto%(s%) de talento sin gastar%.", out)
    -- Bars under the window, each with a button that takes the player there,
    -- and a big message in the middle of the screen for each new one.
    local chips = named.TrailMateFrame.chips
    assert.equals("Nivel 34: hechizos nuevos en tu instructor", chips[1].label.shown_text)
    assert.equals("find trainer", chips[1].cmd)
    assert.equals("1 punto(s) de talento por gastar", chips[2].label.shown_text)
    assert.equals("talents", chips[2].cmd)
    assert.is_false(chips[3].visible)
    assert.equals(2, #notices)
    -- Visiting the class trainer clears that reminder.
    fire("TRAINER_SHOW")
    assert.equals("1 punto(s) de talento por gastar", chips[1].label.shown_text)
    assert.is_false(chips[2].visible)
    assert.equals(2, #notices) -- nothing new to announce
    rawset(_G, "UnitCharacterPoints", function() return 0 end)
    fire("CHARACTER_POINTS_CHANGED")
    assert.is_false(chips[1].visible)
    rawset(_G, "UnitLevel", function() return 8 end)
    rawset(_G, "UnitCharacterPoints", nil)
  end)

  it("says when the bags are full, with a button to the vendor", function()
    rawset(_G.C_Container, "GetContainerNumFreeSlots", function() return 0, 0 end)
    fire("BAG_UPDATE_DELAYED")
    tick()
    tick()
    local chips = named.TrailMateFrame.chips
    local bags
    for _, c in ipairs(chips) do
      if c.cmd == "find vendor" and c.visible then
        bags = c
      end
    end
    assert.is_truthy(bags)
    assert.equals("Bolsas llenas (0 libres): ve a vender", bags.label.shown_text)
    assert.matches("ve a vender", notices[#notices])
  end)

  it("docks a talent plan to the talent window and lights up the next talent", function()
    local tree = {
      { "Improved Aspect of the Hawk", "icon-hawk", 1, 2, 0, 5 },
      { "Endurance Training", "icon-et", 1, 3, 0, 5 },
    }
    local names = { "Beast Mastery", "Marksmanship", "Survival" }
    local added = {
      GetNumTalentTabs = function() return 3 end,
      -- The newer answer: id, name, description, icon, points.
      GetTalentTabInfo = function(tab) return tab, names[tab], "", "icon" .. tab, 0 end,
      GetNumTalents = function(tab) return tab == 1 and #tree or 0 end,
      GetTalentInfo = function(_, i) return unpack(tree[i]) end,
      GetUnspentTalentPoints = function() return 1 end,
      PlayerTalentFrame = fakeObject("PlayerTalentFrame"),
      PlayerTalentFrameTalent1 = fakeObject("PlayerTalentFrameTalent1"),
    }
    rawset(added.PlayerTalentFrameTalent1, "GetID", function() return 1 end)
    rawset(added.PlayerTalentFrameTalent1, "IsVisible", function() return true end)
    for k, v in pairs(added) do
      rawset(_G, k, v)
    end
    finally(function()
      for k in pairs(added) do
        rawset(_G, k, nil)
      end
    end)

    fire("ADDON_LOADED", "Blizzard_TalentUI")
    local panel = named.TrailMateTalents
    assert.matches("^> Beast Mastery", panel.choices[1].shown_text)
    assert.equals("Improved Aspect of the Hawk", panel.name.shown_text)
    assert.equals("Gasta tu punto aquí (1 por gastar)", panel.heading.shown_text)
    assert.is_true(panel.glow.visible) -- lit in the game's window
    assert.equals("Endurance Training (rangos 1-5/5)", panel.rows[1].text.shown_text)
    -- The reminder names the talent.
    fire("CHARACTER_POINTS_CHANGED")
    local found
    for _, c in ipairs(named.TrailMateFrame.chips) do
      found = found or (c.cmd == "talents" and c.label.shown_text)
    end
    assert.equals("Punto de talento: coge Improved Aspect of the Hawk", found)
    -- Choosing another template is saved per character.
    panel.choices[3].scripts.OnClick()
    assert.equals("hunter-sv", _G.TrailMateCharDB.talents.template)
    assert.equals("Esta rama está completa.", panel.name.shown_text)
    assert.is_false(panel.glow.visible)
  end)

  it("changes the icon's glow for the AI companion and remembers it", function()
    _G.SlashCmdList.TRAILMATE("compañero claude")
    assert.equals("claude", _G.TrailMateCharDB.prefs.companion)
    assert.matches("Compañero: claude%.", output())
    _G.SlashCmdList.TRAILMATE("companion gpt")
    assert.equals("chatgpt", _G.TrailMateCharDB.prefs.companion)
    _G.SlashCmdList.TRAILMATE("companion none")
    assert.is_nil(_G.TrailMateCharDB.prefs.companion)
    assert.matches("Compañero: ninguno%.", output())
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

  it("shows the help for /tm help and for unknown commands", function()
    _G.SlashCmdList.TRAILMATE("ayuda")
    assert.matches("/tm questlog | diario", output())
    assert.matches("Crea un plan con tu diario de misiones", output())
    printed = {}
    _G.SlashCmdList.TRAILMATE("no-such-command")
    assert.matches("/tm questlog | diario", output())
  end)

  it("opens the panel with /tm, and its buttons run the same actions", function()
    local panel = named.TrailMatePanel
    assert.is_false(panel.visible)
    _G.SlashCmdList.TRAILMATE("")
    assert.is_true(panel.visible)

    -- Route tab: the "New route" button builds the plan and the text shows it.
    panel.pages.Route.text.shown_text = nil
    _G.SlashCmdList.TRAILMATE("diario")
    assert.matches("Hacer: Lobos", panel.pages.Route.text.shown_text)

    -- Trainer tab: rows with Ignore buttons that work.
    fire("TRAINER_SHOW")
    panel.tabs.Trainer.scripts.OnClick()
    local row = panel.pages.Trainer.rows[1]
    assert.is_true(row.visible)
    row.buttons[2].scripts.OnClick()
    assert.is_true(next(_G.TrailMateCharDB.prefs.ignored) ~= nil)

    -- Log tab: everything said is kept and can be copied.
    panel.tabs.Log.scripts.OnClick()
    assert.matches("TrailMate: ", panel.pages.Log.text.shown_text)
    assert.is_nil(panel.pages.Log.text.shown_text:find("|c", 1, true))

    _G.SlashCmdList.TRAILMATE("")
    assert.is_false(panel.visible)
  end)

  it("runs the self-test from the Log tab without changing anything", function()
    _G.SlashCmdList.TRAILMATE("diario")
    local planBefore = _G.TrailMateCharDB.plan
    local panel = named.TrailMatePanel
    panel.pages.Log.test.scripts.OnClick()
    local out = output()
    assert.matches("Autotest en marcha", out)
    assert.matches("%[PASS%] route: ", out)
    assert.matches("%[PASS%] strategy: ", out)
    assert.matches("%[PASS%] panel: all tabs drawn", out)
    assert.matches("Autotest terminado: %d+ bien, %d+ mal%.", out)
    -- Every check reports, pass or fail, and nothing crashed.
    local checks = 0
    for _ in out:gmatch("%[[PF]A[SI][SL]%]") do
      checks = checks + 1
    end
    assert.equals(17, checks)
    assert.equals(planBefore, _G.TrailMateCharDB.plan)
    assert.is_nil(_G.TrailMateCharDB.prefs.focusZone)
  end)

  it("puts the icon and the compartment entry in the .toc", function()
    local toc = io.open("TrailMate/TrailMate.toc"):read("*a")
    -- Our own icon, and the file it names is really there.
    assert.truthy(toc:find("## IconTexture: Interface\\AddOns\\TrailMate\\media\\Icon\n", 1, true))
    assert.truthy(io.open("TrailMate/media/Icon.tga", "rb"))
    assert.matches("## AddonCompartmentFunc: TrailMate_OnAddonCompartmentClick", toc)
    assert.is_function(_G.TrailMate_OnAddonCompartmentClick)
  end)
end)
