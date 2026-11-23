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
      elseif key == "SetShown" then
        return function(self, on) rawset(self, "visible", on and true or false) end
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
  rawset(_G, "UnitFactionGroup", nil)
  local env = {
    print = function(...)
      local parts = {}
      for i = 1, select("#", ...) do
        parts[#parts + 1] = tostring((select(i, ...)))
      end
      printed[#printed + 1] = table.concat(parts, " ")
    end,
    CreateFrame = function(_, name, parent)
      local f = fakeObject(name)
      rawset(f, "parentFrame", parent)
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

  it("turns the arrow every frame but reads the map only a few times a second", function()
    _G.SlashCmdList.TRAILMATE("diario")
    tick()
    local f = eventFrame()
    f.scripts.OnUpdate(f, 0.3) -- the map work, just done
    local reads, turns = 0, 0
    local readMap, facing = _G.C_Map.GetPlayerMapPosition, _G.GetPlayerFacing
    _G.C_Map.GetPlayerMapPosition = function(...)
      reads = reads + 1
      return readMap(...)
    end
    rawset(_G, "GetPlayerFacing", function()
      turns = turns + 1
      return facing()
    end)
    f.scripts.OnUpdate(f, 0.05)
    f.scripts.OnUpdate(f, 0.05)
    assert.equals(0, reads)
    assert.is_true(turns >= 2)
    -- Past GEO_EVERY, where the player is gets read again.
    f.scripts.OnUpdate(f, 0.15)
    assert.is_true(reads > 0)
    _G.C_Map.GetPlayerMapPosition = readMap
    rawset(_G, "GetPlayerFacing", facing)
  end)

  it("steps aside in a dungeon with nothing to do there, and shows what is (the user's case)", function()
    _G.SlashCmdList.TRAILMATE("diario")
    eventFrame().scripts.OnUpdate(eventFrame(), 0.1)
    local window, arrow = named.TrailMateFrame, named.TrailMateArrow
    assert.equals("Hacer: Lobos", window.step.shown_text)
    assert.is_true(arrow.visible)
    -- Inside the Scarlet Monastery (map 302) with no quest of it in the log.
    rawset(_G, "IsInInstance", function() return true, "party" end)
    rawset(_G, "GetInstanceInfo", function() return "Scarlet Monastery" end)
    finally(function()
      rawset(_G, "IsInInstance", nil)
      rawset(_G, "GetInstanceInfo", nil)
      table.remove(quests, 3)
    end)
    _G.C_Map.GetBestMapForUnit = function() return 302 end
    fire("PLAYER_ENTERING_WORLD", false, false)
    tick()
    assert.is_false(window.visible)
    assert.is_false(arrow.visible)
    -- With one of its quests in the log: the window shows it, still no arrow.
    quests[3] = { questID = 1051, title = "Vorrel's Revenge", isHeader = false }
    fire("QUEST_LOG_UPDATE")
    tick()
    assert.is_true(window.visible)
    assert.equals("Vorrel's Revenge", window.step.shown_text)
    assert.equals("La guía te espera fuera.", window.foot.shown_text)
    assert.is_false(arrow.visible)
    -- The game says nothing of its objectives here: the data's target.
    assert.equals("Nancy Vishas", window.drows[1].label.shown_text)
    assert.equals("Mazmorra 0/1", window.counter.shown_text)
    -- Into The Scarlet Monastery too (the user's case): a heading per quest,
    -- the game's objectives with their count apart, a magnifier per boss.
    local objectivesOf = _G.C_QuestLog.GetQuestObjectives
    local loksey = false
    _G.C_QuestLog.GetQuestObjectives = function(id)
      if id == 1048 then
        return {
          { text = "High Inquisitor Whitemane slain: 0/1", finished = false },
          { text = "Scarlet Commander Mograine slain: 1/1", finished = true },
          { text = "Herod slain: 0/1", finished = false },
          { text = "Houndmaster Loksey slain: " .. (loksey and "1/1" or "0/1"), finished = loksey },
        }
      end
      return objectivesOf(id)
    end
    finally(function()
      _G.C_QuestLog.GetQuestObjectives = objectivesOf
    end)
    quests[4] = { questID = 1048, title = "Into The Scarlet Monastery", isHeader = false }
    fire("QUEST_LOG_UPDATE")
    tick()
    assert.equals("2 misiones aquí", window.step.shown_text)
    assert.equals("Mazmorra 1/5", window.counter.shown_text)
    local rows = {}
    for i = 1, 7 do
      local r = window.drows[i]
      rows[i] = r.label.shown_text .. "|" .. tostring(r.count.shown_text)
    end
    assert.same({ "Vorrel's Revenge|", "Nancy Vishas|", "Into The Scarlet Monastery|",
      "High Inquisitor Whitemane slain|0/1", "Scarlet Commander Mograine slain|1/1", "Herod slain|0/1",
      "Houndmaster Loksey slain|0/1" }, rows)
    -- Herod's magnifier shows Herod; a slain one has nothing to show.
    local herod = window.drows[6]
    herod.lens.scripts.OnEnter(herod.lens)
    local preview = named.TrailMatePreview
    assert.is_true(preview.visible)
    assert.equals("Herod", preview.name.shown_text)
    assert.equals("Mata", preview.verb.shown_text)
    herod.lens.scripts.OnLeave(herod.lens)
    assert.is_false(window.drows[5].step)
    -- Clicking it keeps Herod on show, even as the quest log changes.
    herod.lens.scripts.OnClick(herod.lens)
    assert.is_true(_G.TrailMateCharDB.ui.previewPinned)
    fire("QUEST_LOG_UPDATE")
    tick()
    assert.is_true(preview.visible)
    assert.equals("Herod", preview.name.shown_text)
    _G.SlashCmdList.TRAILMATE("vista no")
    -- Loksey slain, but the event came before the log had it (the user's
    -- case): the dungeon view looks again every two seconds.
    loksey = true
    eventFrame().scripts.OnUpdate(eventFrame(), 2)
    eventFrame().scripts.OnUpdate(eventFrame(), 0.5)
    assert.equals("1/1", window.drows[7].count.shown_text)
    -- A quest finished stays, marked done; all finished: hand them in outside.
    local isComplete = _G.C_QuestLog.IsComplete
    local complete = { [1048] = true }
    _G.C_QuestLog.IsComplete = function(id)
      return complete[id] == true or isComplete(id)
    end
    finally(function()
      _G.C_QuestLog.IsComplete = isComplete
    end)
    fire("QUEST_LOG_UPDATE")
    tick()
    assert.equals("Into The Scarlet Monastery (hecha)", window.drows[3].label.shown_text)
    assert.equals("2 misiones aquí", window.step.shown_text)
    complete[1051] = true
    fire("QUEST_LOG_UPDATE")
    tick()
    assert.is_true(window.visible)
    assert.equals("Todo hecho aquí", window.step.shown_text)
    assert.equals("Entrégalas fuera.", window.foot.shown_text)
    complete[1048], complete[1051] = nil, nil
    table.remove(quests, 4)
    -- Out again: the guide's step and its arrow are back.
    rawset(_G, "IsInInstance", function() return false end)
    _G.C_Map.GetBestMapForUnit = function() return 1429 end
    fire("PLAYER_ENTERING_WORLD", false, false)
    tick()
    eventFrame().scripts.OnUpdate(eventFrame(), 0.1)
    assert.is_true(window.visible)
    assert.equals("Hacer: Lobos", window.step.shown_text)
    assert.is_true(arrow.visible)
  end)

  it("highlights the current quest in the log and on the map, and cleans up after itself", function()
    _G.SlashCmdList.TRAILMATE("diario")
    assert.equals(10, superTracked)
    assert.equals(0, watched[10])
    assert.matches("Marca en el mapa: TrailMate", named.TrailMateFrame.arrow.shown_text)
    _G.SlashCmdList.TRAILMATE("borrar")
    assert.is_nil(watched[10])
  end)

  it("follows a quest the player marks, with a button back to the route (the user's case)", function()
    _G.C_SuperTrack.GetSuperTrackedQuestID = function() return superTracked end
    _G.SlashCmdList.TRAILMATE("diario")
    local window = named.TrailMateFrame
    assert.equals("Hacer: Lobos", window.step.shown_text)
    -- Jabalies shows on the map once the route is made (it stays out of it).
    _G.C_QuestLog.GetQuestsOnMap = function()
      return { { questID = 10, x = 0.3, y = 0.3 }, { questID = 11, x = 0.6, y = 0.6 } }
    end
    -- TrailMate's own choice (Lobos) is not the player's mark.
    fire("SUPER_TRACKING_CHANGED")
    assert.equals("Hacer: Lobos", window.step.shown_text)
    assert.is_false(window.back.visible)
    -- The player clicks Jabalies (done, in this fake): the arrow goes to hand it in.
    superTracked = 11
    fire("SUPER_TRACKING_CHANGED")
    eventFrame().scripts.OnUpdate(eventFrame(), 0.1)
    assert.equals("Tu misión marcada", window.title.shown_text)
    assert.equals("Entregar: Jabalies", window.step.shown_text)
    assert.equals("Siguiente en la guía - Hacer: Lobos", window.why.shown_text)
    assert.equals("Ruta en pausa", window.counter.shown_text)
    assert.equals("Entregar: Jabalies", named.TrailMateArrow.label.shown_text)
    assert.is_true(window.back.visible)
    assert.equals("Volver a la ruta", window.back.shown_text)
    assert.matches("Flecha a la misión que has marcado: Entregar: Jabalies", output())
    -- The button goes back: the guide's quest is followed again.
    window.back.scripts.OnClick(window.back)
    assert.equals("Hacer: Lobos", window.step.shown_text)
    assert.equals(10, superTracked)
    assert.is_false(window.back.visible)
  end)

  it("goes back to the route by itself when the marked quest leaves the log", function()
    _G.C_SuperTrack.GetSuperTrackedQuestID = function() return superTracked end
    _G.SlashCmdList.TRAILMATE("diario")
    superTracked = 11
    fire("SUPER_TRACKING_CHANGED")
    local window = named.TrailMateFrame
    assert.is_true(window.back.visible)
    local jabalies = table.remove(quests, 2)
    finally(function()
      quests[2] = jabalies
    end)
    fire("QUEST_REMOVED", 11)
    tick()
    assert.equals("Hacer: Lobos", window.step.shown_text)
    assert.is_false(window.back.visible)
    assert.matches("ya no está en el diario", output())
  end)

  it("counts a mark of the quest the game followed again at login (the user's case)", function()
    _G.C_SuperTrack.GetSuperTrackedQuestID = function() return superTracked end
    local setTracked = _G.C_SuperTrack.SetSuperTrackedQuestID
    finally(function()
      _G.C_SuperTrack.SetSuperTrackedQuestID = setTracked
      table.remove(quests, 3)
    end)
    -- After a reload the game follows Reclaimed Treasures again, and the
    -- guide's quest cannot be followed (not in the log yet): it stays.
    quests[3] = { questID = 2342, title = "Reclaimed Treasures", isHeader = false }
    superTracked = 2342
    _G.C_SuperTrack.SetSuperTrackedQuestID = function() end
    _G.SlashCmdList.TRAILMATE("diario")
    _G.C_SuperTrack.SetSuperTrackedQuestID = setTracked
    local window = named.TrailMateFrame
    assert.equals("Hacer: Lobos", window.step.shown_text)
    -- The player marks another quest, then Reclaimed Treasures again: both count.
    superTracked = 11
    fire("SUPER_TRACKING_CHANGED")
    eventFrame().scripts.OnUpdate(eventFrame(), 0.1)
    assert.equals("Entregar: Jabalies", window.step.shown_text)
    superTracked = 2342
    fire("SUPER_TRACKING_CHANGED")
    eventFrame().scripts.OnUpdate(eventFrame(), 0.1)
    assert.equals("Hacer: Reclaimed Treasures", window.step.shown_text)
  end)

  it("shows the chest of a marked dungeon quest as its 3D model (the user's case)", function()
    _G.C_SuperTrack.GetSuperTrackedQuestID = function() return superTracked end
    rawset(_G, "GetItemIcon", function(id) return id == 8026 and "icon-8026" or nil end)
    finally(function()
      rawset(_G, "GetItemIcon", nil)
      table.remove(quests, 3)
    end)
    _G.SlashCmdList.TRAILMATE("diario")
    quests[3] = { questID = 2342, title = "Reclaimed Treasures", isHeader = false }
    fire("QUEST_LOG_UPDATE")
    tick()
    superTracked = 2342
    fire("SUPER_TRACKING_CHANGED")
    eventFrame().scripts.OnUpdate(eventFrame(), 0.1)
    local window = named.TrailMateFrame
    assert.equals("Hacer: Reclaimed Treasures", window.step.shown_text)
    -- The quest's object is in Uldaman: its magnifier shows the chest.
    assert.is_true(window.lens.visible)
    window.lens.scripts.OnEnter(window.lens)
    local preview = named.TrailMatePreview
    assert.is_true(preview.visible)
    assert.equals("Garrett Family Chest", preview.name.shown_text)
    assert.equals("Busca en", preview.verb.shown_text)
    -- The game has not said it took the model file: the icon of the item.
    assert.is_false(preview.object.visible)
    assert.is_true(preview.icon.visible)
    window.lens.scripts.OnLeave(window.lens)
    -- It took it (object 124388, appearance 10, model file 196976): the
    -- chest in its own frame, never the creature shown before.
    preview.object.GetModelFileID = function() return 196976 end
    window.lens.scripts.OnEnter(window.lens)
    assert.is_true(preview.object.visible)
    assert.is_false(preview.model.visible)
    assert.is_false(preview.icon.visible)
    window.lens.scripts.OnLeave(window.lens)
    -- A client that cannot draw it: the icon again.
    preview.object.SetModel = function() error("no model") end
    window.lens.scripts.OnEnter(window.lens)
    assert.is_false(preview.object.visible)
    assert.is_true(preview.icon.visible)
    window.lens.scripts.OnLeave(window.lens)
  end)

  it("has its page in Esc > Options > AddOns, and hides the minimap button when asked", function()
    install()
    rawset(_G, "TrailMateDB", nil)
    rawset(_G, "TrailMateCharDB", nil)
    local seen = {}
    rawset(_G, "Settings", {
      RegisterCanvasLayoutCategory = function(frame, name)
        seen.frame, seen.name = frame, name
        return { GetID = function() return 7 end }
      end,
      RegisterAddOnCategory = function(category) seen.category = category end,
      OpenToCategory = function(id) seen.opened = id end,
    })
    rawset(_G, "Minimap", fakeObject("Minimap"))
    finally(function()
      rawset(_G, "Settings", nil)
      rawset(_G, "Minimap", nil)
    end)
    loadAddon()
    fire("ADDON_LOADED", "TrailMate")
    assert.equals("TrailMate", seen.name)
    assert.is_table(seen.category)
    _G.SlashCmdList.TRAILMATE("opciones")
    assert.equals(7, seen.opened)
    _G.SlashCmdList.TRAILMATE("minimapa")
    assert.is_true(_G.TrailMateCharDB.minimap.hidden)
    _G.SlashCmdList.TRAILMATE("minimapa")
    assert.is_false(_G.TrailMateCharDB.minimap.hidden)
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

  it("marks the target on the minimap by itself: a pin near, an arrow on the edge when far", function()
    local zoom = 0
    local map = fakeObject("Minimap")
    rawset(map, "GetWidth", function() return 140 end)
    rawset(map, "GetZoom", function() return zoom end)
    rawset(_G, "Minimap", map)
    finally(function()
      rawset(_G, "Minimap", nil)
    end)
    _G.SlashCmdList.TRAILMATE("diario")
    eventFrame().scripts.OnUpdate(eventFrame(), 0.1)
    local mark = named.TrailMateMinimapPin
    -- 283 yards away: beyond the 233 yards the minimap shows around you.
    assert.is_true(mark.edge.visible)
    assert.is_false(mark.pin.visible)
    -- A nearer quest (70 yards) is a pin inside the minimap, its tip on the
    -- spot: the picture stands above it, so the quest's own mark shows.
    _G.C_QuestLog.GetQuestsOnMap = function() return { { questID = 10, x = 0.45, y = 0.45 } } end
    _G.SlashCmdList.TRAILMATE("diario")
    eventFrame().scripts.OnUpdate(eventFrame(), 2)
    assert.is_true(mark.pin.visible)
    assert.is_false(mark.edge.visible)
    -- Walking, the pin moves every frame with the minimap, not five times a
    -- second (the user saw it jump): the way walked since the map work.
    rawset(mark.pin, "SetPoint", function(self, ...) rawset(self, "point", { ... }) end)
    local north = 0
    rawset(_G, "UnitPosition", function() return 0, north end)
    finally(function()
      rawset(_G, "UnitPosition", nil)
    end)
    eventFrame().scripts.OnUpdate(eventFrame(), 2) -- the map work
    local before = mark.pin.point[5]
    north = 10 -- ten yards north, towards the quest
    eventFrame().scripts.OnUpdate(eventFrame(), 0.05)
    local after = mark.pin.point[5]
    assert.is_true(after < before - 2) -- 10 yards: 3 pixels at this zoom
    -- Purple, not the gold of the game's quest marks.
    assert.same({ 0.61, 0.48, 0.83, 1 }, mark.edge.color)
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
    -- Lost off screen? Back to the middle (and on again), remembered.
    _G.SlashCmdList.TRAILMATE("flecha centro")
    assert.same({ "CENTER", "CENTER", 0, 60 }, { _G.TrailMateCharDB.arrow.point, _G.TrailMateCharDB.arrow.relPoint,
      _G.TrailMateCharDB.arrow.x, _G.TrailMateCharDB.arrow.y })
    assert.is_false(_G.TrailMateCharDB.arrow.disabled)
    assert.matches("Flecha colocada en el centro de la pantalla", output())
    _G.SlashCmdList.TRAILMATE("flecha arriba")
    assert.equals("TOP", _G.TrailMateCharDB.arrow.point)
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
    _G.SlashCmdList.TRAILMATE("guia off") -- this test is about the quest log plan
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
    -- Saved by the world's continent (0, Eastern Kingdoms), not by map id.
    assert.is_true(_G.TrailMateCharDB.learnedFlights[0]["Grom'gol"])
    printed = {}
    _G.SlashCmdList.TRAILMATE("zona " .. index)
    assert.equals("Ve al maestro de vuelo: Hammerfall.", window.step.shown_text)
    assert.matches("Vuela de Hammerfall a Grom'gol%.$", output():match("[^\n]*Vuela[^\n]*"))
    assert.is_nil(output():find("Abre una vez un maestro de vuelo allí", 1, true))
    -- A /reload on the way: the trip goes on (it used to be dropped, and the
    -- guide's step came back as if the trip had been skipped: the user's case).
    local saved = _G.TrailMateCharDB
    assert.equals(1434, saved.trip.zone)
    frames, named = {}, {}
    rawset(_G, "TrailMateCharDB", saved)
    loadAddon()
    fire("ADDON_LOADED", "TrailMate")
    fire("PLAYER_ENTERING_WORLD", false, true)
    window = named.TrailMateFrame
    assert.equals("Viaje", window.counter.shown_text)
    -- A quest marked on the way: back from it, the trip goes on (the review's case).
    _G.C_SuperTrack.GetSuperTrackedQuestID = function() return superTracked end
    superTracked = 11
    fire("SUPER_TRACKING_CHANGED")
    assert.equals("Tu misión marcada", window.title.shown_text)
    window.back.scripts.OnClick(window.back)
    assert.equals("Viaje", window.counter.shown_text)
    assert.equals(1434, _G.TrailMateCharDB.trip.zone)
    assert.equals(0, superTracked) -- the game no longer follows the marked quest
    -- Going back to the plan leaves the trip for good.
    _G.SlashCmdList.TRAILMATE("plan")
    assert.equals("Hacer: Lobos", window.step.shown_text)
    assert.is_nil(_G.TrailMateCharDB.trip)
    rawset(_G, "C_TaxiMap", nil)
    rawset(_G, "CreateVector2D", nil)
  end)

  it("sends the arrow to the flight master when the step is far and flying is quicker (the user's case)",
    function()
    _G.SlashCmdList.TRAILMATE("guia off")
    local function vec(x, y)
      return { x = x, y = y, GetXY = function(self) return self.x, self.y end }
    end
    rawset(_G, "CreateVector2D", vec)
    rawset(_G, "UnitLevel", function() return 33 end)
    -- The player near (500, 500); Hammerfall's flight master next to him,
    -- Grom'gol's far south, by the step's place.
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
        }
      end,
      GetAllTaxiNodes = function()
        return { { name = "Hammerfall", state = 0 }, { name = "Grom'gol", state = 1 } }
      end,
    })
    rawset(_G, "Enum", { FlightPathFaction = { Neutral = 0, Horde = 1, Alliance = 2 },
      FlightPathState = { Current = 0, Reachable = 1, Unreachable = 2 } })
    rawset(_G, "UnitFactionGroup", function() return "Horde" end)
    rawset(_G, "GetTaxiMapID", function() return 1415 end)
    local onMap, waypoint = _G.C_QuestLog.GetQuestsOnMap, _G.C_QuestLog.GetNextWaypoint
    finally(function()
      _G.C_QuestLog.GetQuestsOnMap, _G.C_QuestLog.GetNextWaypoint = onMap, waypoint
      rawset(_G, "C_TaxiMap", nil)
      rawset(_G, "CreateVector2D", nil)
    end)
    _G.SlashCmdList.TRAILMATE("diario")
    fire("TAXIMAP_OPENED") -- this character's flights, learned at a flight master
    local arrow = named.TrailMateArrow
    -- Close by: straight to it, with the step's text.
    eventFrame().scripts.OnUpdate(eventFrame(), 2)
    assert.equals("Hacer: Lobos", arrow.label.shown_text)
    -- The quest's place far south, by Grom'gol: fly there first.
    _G.C_QuestLog.GetQuestsOnMap = function() return {} end
    _G.C_QuestLog.GetNextWaypoint = function(id)
      if id == 10 then
        return 1434, 0.5, 0.5
      end
    end
    eventFrame().scripts.OnUpdate(eventFrame(), 11)
    assert.equals("Vuela de Hammerfall a Grom'gol.", arrow.label.shown_text)
    -- At the flight master, Grom'gol beats on the flight map (the user asked).
    local gromgol = fakeObject("TaxiButton2")
    gromgol:Show()
    rawset(_G, "TaxiButton2", gromgol)
    rawset(_G, "NumTaxiNodes", function() return 2 end)
    rawset(_G, "TaxiNodeName", function(i) return i == 1 and "Hammerfall" or "Grom'gol" end)
    finally(function()
      rawset(_G, "TaxiButton2", nil)
      rawset(_G, "NumTaxiNodes", nil)
      rawset(_G, "TaxiNodeName", nil)
    end)
    fire("TAXIMAP_OPENED")
    local mark = named.TrailMateFlightMark
    assert.is_true(mark.visible)
    -- Seen on the parchment: a ring and the purple pin over the point, and said.
    assert.is_true(mark.top.visible)
    assert.matches("Mapa de vuelos: vuela a Grom'gol", output())
    fire("TAXIMAP_CLOSED")
    assert.is_false(mark.visible)
    assert.is_false(mark.top.visible)
    -- Without that flight (Grom'gol grey on the flight map: not learned, or
    -- not connected), never to the flight master: straight to the step.
    _G.C_TaxiMap.GetAllTaxiNodes = function()
      return { { name = "Hammerfall", state = 0 }, { name = "Grom'gol", state = 2 } }
    end
    fire("TAXIMAP_OPENED")
    -- Learned before, still remembered; but no flight from here goes there.
    assert.is_true(_G.TrailMateCharDB.learnedFlights[0]["Grom'gol"])
    eventFrame().scripts.OnUpdate(eventFrame(), 11)
    assert.equals("Hacer: Lobos", arrow.label.shown_text)
    -- A grey point never learned before is not counted as learned.
    _G.C_TaxiMap.GetAllTaxiNodes = function()
      return { { name = "Hammerfall", state = 0 }, { name = "Grom'gol", state = 1 },
        { name = "Kargath", state = 2 } }
    end
    fire("TAXIMAP_OPENED")
    assert.is_nil(_G.TrailMateCharDB.learnedFlights[0]["Kargath"])
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

  it("shows the talent plan with the talents tab only, not with the spellbook (the user's case)", function()
    -- The modern client: one window with a spellbook tab and a talents tab.
    local window = fakeObject("PlayerSpellsFrame")
    local talents, spellbook = fakeObject("TalentsFrame"), fakeObject("SpellBookFrame")
    rawset(window, "TalentsFrame", talents)
    rawset(window, "SpellBookFrame", spellbook)
    local added = {
      GetNumTalentTabs = function() return 3 end,
      GetTalentTabInfo = function(tab) return tab, "Tree " .. tab, "", "icon" .. tab, 0 end,
      GetNumTalents = function() return 0 end,
      GetTalentInfo = function() end,
      GetUnspentTalentPoints = function() return 0 end,
      PlayerSpellsFrame = window,
    }
    for k, v in pairs(added) do
      rawset(_G, k, v)
    end
    finally(function()
      for k in pairs(added) do
        rawset(_G, k, nil)
      end
    end)
    fire("ADDON_LOADED", "Blizzard_PlayerSpells")
    local panel = named.TrailMateTalents
    assert.is_table(panel)
    -- Inside the talents tab, so it hides with it when the spellbook shows.
    assert.equals(talents, panel.parentFrame)
  end)

  it("docks a talent plan to the talent window and lights up the next talent", function()
    local tree = {
      { "Deadly Aspects", "icon-hawk", 1, 2, 0, 5 },
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
    assert.matches("^> Build de subida", panel.choices[1].shown_text)
    assert.equals("Deadly Aspects", panel.name.shown_text)
    assert.equals("Gasta tu punto aquí (1 por gastar)", panel.heading.shown_text)
    assert.is_true(panel.glow.visible) -- lit in the game's window
    -- Hovering a template shows its picture: the trees with the planned talents.
    panel.choices[1].scripts.OnEnter(panel.choices[1])
    local picture = named.TrailMateTalentPreview
    assert.is_true(picture.visible)
    assert.matches("^Build de subida   %d+/%d+/%d+", picture.title.shown_text)
    panel.choices[1].scripts.OnLeave(panel.choices[1])
    assert.is_false(picture.visible)
    -- One line per talent: the name in its tree's colour, then the ranks.
    assert.matches("^|c%x+Endurance Training|r  rangos 1%-5/5$", panel.rows[1].text.shown_text)
    -- The reminder names the talent.
    fire("CHARACTER_POINTS_CHANGED")
    local found
    for _, c in ipairs(named.TrailMateFrame.chips) do
      found = found or (c.cmd == "talents" and c.label.shown_text)
    end
    assert.equals("Punto de talento: coge Deadly Aspects", found)
    -- Choosing another template is saved per character.
    panel.choices[4].scripts.OnClick()
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

  it("on arrival starts with the place's quests, and learns what quest givers offer (the user's case)", function()
    _G.SlashCmdList.TRAILMATE("diario")
    _G.SlashCmdList.TRAILMATE("estrategia")
    local index = output():match("%[(%d+)%] Elwynn Forest")
    assert.is_not_nil(index)
    -- Choosing the zone the player is in counts as arriving there.
    _G.SlashCmdList.TRAILMATE("zona " .. index)
    local window = named.TrailMateFrame
    assert.equals("Primero coge las misiones de aquí", window.step.shown_text)
    _G.SlashCmdList.TRAILMATE("hecho")
    assert.equals("Hacer: Lobos", window.step.shown_text)
    -- Rebuilding the plan (a quest taken, a reload) does not bring it back.
    _G.SlashCmdList.TRAILMATE("diario")
    assert.equals("Hacer: Lobos", window.step.shown_text)
    -- A quest giver offers a quest the player does not take: it is learned,
    -- and the plan then starts with picking it up.
    npcGUID = "Creature-0-1-0-1-197-0"
    rawset(_G, "C_GossipInfo", {
      GetAvailableQuests = function() return { { questID = 50, title = "Bandidos", questLevel = 8 } } end,
      GetOptions = function() return { { name = "Make this inn your home." } } end,
    })
    finally(function()
      rawset(_G, "C_GossipInfo", nil)
    end)
    fire("GOSSIP_SHOW")
    npcGUID = nil
    assert.equals("Bandidos", _G.TrailMateDB.atlas.quests[50].title)
    _G.SlashCmdList.TRAILMATE("diario")
    assert.equals("Coger: Bandidos", window.step.shown_text)
    -- It was an innkeeper too: remembered as one.
    local roles = {}
    for _, npc in pairs(_G.TrailMateDB.atlas.npcs) do
      for role in pairs(npc.roles or {}) do
        roles[role] = true
      end
    end
    assert.is_true(roles.innkeeper)
  end)

  it("arriving at Grom'gol starts with the hub's quests by name (the user's case)", function()
    rawset(_G, "UnitLevel", function() return 34 end)
    rawset(_G, "UnitFactionGroup", function() return "Horde" end)
    _G.C_Map.GetBestMapForUnit = function() return 1434 end
    local names = { [581] = "Hunt for Yenniku", [596] = "Bloody Bone Necklaces" }
    _G.C_QuestLog.GetTitleForQuestID = function(id) return names[id] end
    _G.C_QuestLog.RequestLoadQuestByID = function() end
    finally(function()
      rawset(_G, "UnitLevel", function() return 8 end)
    end)
    _G.SlashCmdList.TRAILMATE("guia off") -- the hubs serve the quest log plan
    _G.SlashCmdList.TRAILMATE("estrategia")
    local index = output():match("%[(%d+)%] Stranglethorn Vale")
    assert.is_not_nil(index)
    _G.SlashCmdList.TRAILMATE("zona " .. index)
    local window = named.TrailMateFrame
    assert.equals("Coger: Hunt for Yenniku", window.step.shown_text)
    assert.equals("Grom'gol Base Camp", window.why.shown_text)
    assert.equals("- Coger: Bloody Bone Necklaces", window.rows[1].label.shown_text)
    -- A name the game has not loaded yet still gives a step.
    assert.equals("- Coger: Misión 638", window.rows[2].label.shown_text)
  end)

  it("follows the Stranglethorn guide from Grom'gol, with the arrow on each quest giver (the user's case)", function()
    rawset(_G, "UnitLevel", function() return 34 end)
    rawset(_G, "UnitFactionGroup", function() return "Horde" end)
    finally(function()
      rawset(_G, "UnitLevel", function() return 8 end)
    end)
    _G.C_Map.GetBestMapForUnit = function() return 1434 end
    -- Standing at Grom'gol, by the flight master.
    _G.C_Map.GetPlayerMapPosition = function()
      return { GetXY = function() return 0.326, 0.29 end }
    end
    _G.SlashCmdList.TRAILMATE("diario")
    assert.matches("Guía: 33%-34 Stranglethorn Vale", output())
    local window = named.TrailMateFrame
    -- "Take the zeppelin" and "get the flight path" are behind: already here.
    assert.equals("Coger: Hunt for Yenniku", window.step.shown_text)
    assert.equals("Te la da Nimboya", window.why.shown_text)
    assert.equals("- Coger: Bloody Bone Necklaces", window.rows[1].label.shown_text)
    -- The guide list, and back to the quest log plan.
    _G.SlashCmdList.TRAILMATE("guia")
    assert.matches("%[%d+%] 33%-34 Stranglethorn Vale  |cffffd100<%- ahora", output())
    _G.SlashCmdList.TRAILMATE("guia off")
    assert.is_nil(window.step.shown_text:find("Yenniku", 1, true))
  end)

  it("skips a pick-up the quest giver does not offer (Trollbane at Grom'gol, the user's case)", function()
    rawset(_G, "UnitLevel", function() return 34 end)
    rawset(_G, "UnitFactionGroup", function() return "Horde" end)
    finally(function()
      rawset(_G, "UnitLevel", function() return 8 end)
      rawset(_G, "C_GossipInfo", nil)
      npcGUID = nil
    end)
    _G.C_Map.GetBestMapForUnit = function() return 1434 end
    _G.C_Map.GetPlayerMapPosition = function()
      return { GetXY = function() return 0.326, 0.29 end }
    end
    _G.SlashCmdList.TRAILMATE("diario")
    local window = named.TrailMateFrame
    assert.equals("Coger: Hunt for Yenniku", window.step.shown_text)
    -- Talking to Nimboya, who offers something else.
    npcGUID = "Creature-0-1-0-1-2497-0"
    rawset(_G, "UnitName", function(unit) return unit == "npc" and "Nimboya" or nil end)
    rawset(_G, "C_GossipInfo", { GetAvailableQuests = function() return { { questID = 1, title = "Otra" } } end })
    fire("GOSSIP_SHOW")
    assert.matches("Nimboya no ofrece «Hunt for Yenniku» ahora: lo salto", output())
    assert.equals("Coger: Bloody Bone Necklaces", window.step.shown_text)
  end)

  it("says when key bindings sync with Blizzard, and keeps them on the PC only when asked (the user's case)", function()
    local live, cvars, saves = {}, { synchronizeBindings = "1" }, 0
    local added = {
      GetBindingAction = function(key) return live[key] or "" end,
      SetBinding = function(key, action) live[key] = action; return true end,
      GetCurrentBindingSet = function() return 1 end,
      SaveBindings = function() saves = saves + 1 end,
      GetCVar = function(name) return cvars[name] end,
      SetCVar = function(name, value) cvars[name] = value end,
    }
    for k, v in pairs(added) do
      rawset(_G, k, v)
    end
    finally(function()
      for k in pairs(added) do
        rawset(_G, k, nil)
      end
    end)
    _G.SlashCmdList.TRAILMATE("chat hola")
    eventFrame().scripts.OnUpdate(eventFrame(), 0.25)
    assert.matches("se sincronizan con Blizzard", named.TrailMateChat.status.shown_text)
    assert.equals("1", cvars.synchronizeBindings) -- never changed by itself
    _G.SlashCmdList.TRAILMATE("chat local")
    assert.equals("0", cvars.synchronizeBindings)
    eventFrame().scripts.OnUpdate(eventFrame(), 0.25)
    assert.is_nil(named.TrailMateChat.status.shown_text:find("sincronizan", 1, true))
    -- What each key holds, for a bug report.
    _G.SlashCmdList.TRAILMATE("chat diag")
    assert.matches("CTRL%-ALT%-SHIFT%-F1: frame 1", output())
    _G.SlashCmdList.TRAILMATE("chat sync")
    assert.equals("1", cvars.synchronizeBindings)
  end)

  it("starts the chat without math.randomseed, which WoW does not have (the user's case)", function()
    local seed = math.randomseed
    rawset(math, "randomseed", nil)
    finally(function()
      rawset(math, "randomseed", seed)
    end)
    install()
    rawset(_G, "TrailMateDB", nil)
    rawset(_G, "TrailMateCharDB", nil)
    loadAddon()
    fire("ADDON_LOADED", "TrailMate")
    _G.SlashCmdList.TRAILMATE("chat hola")
    local lines = _G.TrailMateCharDB.chat.lines
    assert.same({ who = "me", text = "hola" }, lines[#lines])
    eventFrame().scripts.OnUpdate(eventFrame(), 0.25)
    local status = named.TrailMateChat.status.shown_text
    assert.is_string(status)
    assert.is_nil(status:find("no ha podido arrancar", 1, true))
  end)

  it("chats with the companion through the key bindings and an inbox (the bridge simulated)", function()
    local codec = {}
    assert(loadfile("TrailMate/core/Link.lua"))("TrailMate", codec)
    local live, saved, loaded, all = {}, {}, {}, {}
    local body = ""
    local added = {
      GetBindingAction = function(key) return live[key] or "" end,
      SetBinding = function(key, action) live[key] = action; return true end,
      GetCurrentBindingSet = function() return 1 end,
      SaveBindings = function()
        for k in pairs(saved) do saved[k] = nil end
        for k, v in pairs(live) do saved[k] = v end
      end,
    }
    for k, v in pairs(added) do
      rawset(_G, k, v)
    end
    -- The bridge: reads the saved frames, acknowledges them, answers.
    _G.C_AddOns.LoadAddOn = function(name)
      loaded[#loaded + 1] = name
      local session, ack = nil, 0
      for _, action in pairs(saved) do
        local f = codec.Link.parse(action)
        if f then
          session, all[f.seq] = f.session, f.payload
        end
      end
      while all[ack + 1] do
        ack = ack + 1
      end
      body = table.concat(all, "", 1, ack)
      if session then
        local done = body:find("M¿Qué hago ahora%?$") ~= nil
        _G.TrailMate_Inbox({ protocol = 1, session = session, ack = ack,
          replies = done and { { id = 1, text = "Haz las misiones de Grom'gol." } } or nil })
      end
      return true
    end
    finally(function()
      for k in pairs(added) do
        rawset(_G, k, nil)
      end
      _G.C_AddOns.LoadAddOn = nil
    end)
    _G.SlashCmdList.TRAILMATE("chat ¿Qué hago ahora?")
    for _ = 1, 80 do
      eventFrame().scripts.OnUpdate(eventFrame(), 0.25)
    end
    local lines = _G.TrailMateCharDB.chat.lines
    assert.same({ who = "me", text = "¿Qué hago ahora?" }, lines[#lines - 1])
    assert.same({ who = "companion", text = "Haz las misiones de Grom'gol." }, lines[#lines])
    -- The character's context went first, in its own message.
    assert.matches("^CCharacter: HUNTER level 8", body)
    assert.equals("TrailMate_Inbox_0001", loaded[1])
    -- Done: nothing is left on the keys.
    for _, key in ipairs(codec.Link.KEYS) do
      assert.equals("", _G.GetBindingAction(key))
    end
    assert.matches("Tu compañero te ha contestado", notices[#notices])
  end)

  it("lists the dungeons for level 34 and plans one: quests first, then the entrance", function()
    rawset(_G, "UnitLevel", function() return 34 end)
    rawset(_G, "UnitFactionGroup", function() return "Horde" end)
    finally(function()
      rawset(_G, "UnitLevel", function() return 8 end)
    end)
    _G.SlashCmdList.TRAILMATE("mazmorras")
    local said = output()
    assert.matches("%[1%] Gnomeregan, enemigos 25%-34: 2 misiones para coger antes", said)
    assert.matches("%[4%] Razorfen Downs", said)
    assert.matches("Siguiente mazmorra: Uldaman desde el nivel 35%.", said)
    _G.SlashCmdList.TRAILMATE("mazmorra 1")
    assert.matches("Mazmorra: Gnomeregan%. 2 misiones para coger antes de entrar%.", output())
    assert.equals("dungeon-721", _G.TrailMateCharDB.plan.id)
    local window = named.TrailMateFrame
    assert.equals("Coger: Rig Wars", window.step.shown_text)
    -- The guide on login does not replace a dungeon plan.
    fire("PLAYER_ENTERING_WORLD")
    assert.equals("dungeon-721", _G.TrailMateCharDB.plan.id)
  end)

  it("tells an orc hunter about the pet quest at level 10, once, and takes them there", function()
    rawset(_G, "UnitLevel", function() return 10 end)
    rawset(_G, "UnitFactionGroup", function() return "Horde" end)
    rawset(_G, "UnitRace", function() return "Orco", "Orc", 2 end)
    finally(function()
      rawset(_G, "UnitLevel", function() return 8 end)
      rawset(_G, "UnitRace", nil)
    end)
    fire("PLAYER_LEVEL_UP", 10)
    -- The breadcrumbs from other trainers lead to it: only the quest itself.
    assert.matches("Misiones de clase para ti: Taming the Beast %(Thotar%)%. Escribe /tm clase para ir%.", output())
    printed = {}
    fire("PLAYER_LEVEL_UP", 10)
    assert.is_nil(output():find("Misiones de clase para ti", 1, true))
    _G.SlashCmdList.TRAILMATE("clase")
    local said = output()
    assert.matches("Misiones de clase que puedes coger", said)
    assert.matches("%[1%] Taming the Beast %(Thotar%)", said)
    assert.is_nil(said:find("Hunter's Path", 1, true))
    _G.SlashCmdList.TRAILMATE("clase 1")
    assert.matches("Misión de clase: Taming the Beast%. La flecha te lleva hasta Thotar%.", output())
    assert.equals("class-6062", _G.TrailMateCharDB.plan.id)
    assert.equals("Coger: Taming the Beast", named.TrailMateFrame.step.shown_text)
    -- Hovering the step shows who to look for, next to the window.
    named.TrailMateFrame.hover.scripts.OnEnter()
    local preview = named.TrailMatePreview
    assert.is_true(preview.visible)
    assert.equals("Habla con", preview.verb.shown_text)
    assert.equals("Thotar", preview.name.shown_text)
    named.TrailMateFrame.hover.scripts.OnLeave()
    assert.is_false(preview.visible)
    -- Passing over the step on the way to the buttons shows nothing: it
    -- waits a moment, and the mouse is gone by then.
    local timers = _G.C_Timer
    local waiting
    rawset(_G, "C_Timer", { After = function(_, fn) waiting = fn end })
    named.TrailMateFrame.hover.scripts.OnEnter()
    named.TrailMateFrame.hover.scripts.OnLeave()
    waiting()
    assert.is_false(preview.visible)
    rawset(_G, "C_Timer", timers)
    -- Kept shown: leaving the step does not close it; the magnifier undoes it.
    printed = {}
    _G.SlashCmdList.TRAILMATE("vista")
    assert.matches("Vista previa fija%. Pulsa la lupa", output())
    assert.is_true(_G.TrailMateCharDB.ui.previewPinned)
    assert.is_true(preview.visible)
    named.TrailMateFrame.hover.scripts.OnLeave()
    assert.is_true(preview.visible)
    local lens = named.TrailMateFrame.lens
    lens.scripts.OnEnter(lens)
    lens.scripts.OnLeave(lens)
    assert.is_true(preview.visible)
    printed = {}
    lens.scripts.OnClick(lens)
    assert.matches("Vista previa solo al pasar el ratón%.", output())
    assert.is_nil(_G.TrailMateCharDB.ui.previewPinned)
    assert.is_false(preview.visible)
    _G.SlashCmdList.TRAILMATE("vista si")
    assert.is_true(preview.visible)
    -- A fight hides it; a kept preview comes back after it.
    preview.scripts.OnEvent(preview, "PLAYER_REGEN_DISABLED")
    assert.is_false(preview.visible)
    preview.scripts.OnEvent(preview, "PLAYER_REGEN_ENABLED")
    assert.is_true(preview.visible)
    _G.SlashCmdList.TRAILMATE("vista no")
    assert.is_false(preview.visible)
  end)

  it("measures what each part costs for a minute (/tm perf)", function()
    local ms = 0
    rawset(_G, "debugprofilestop", function()
      ms = ms + 2
      return ms
    end)
    local timers, waiting = _G.C_Timer, nil
    rawset(_G, "C_Timer", { After = function(_, fn) waiting = fn end })
    printed = {}
    _G.SlashCmdList.TRAILMATE("rendimiento")
    assert.matches("Measuring for 60 seconds", output())
    fire("QUEST_LOG_UPDATE")
    eventFrame().scripts.OnUpdate(eventFrame(), 0.5)
    waiting()
    local said = output()
    assert.matches("Performance over %d+ s", said)
    assert.matches("QUEST_LOG_UPDATE: [%d.]+ ms in 1 runs", said)
    assert.matches("arrow draw: [%d.]+ ms in 1 runs", said)
    assert.matches("Memory: [%d.]+ MB at the start", said)
    assert.matches("Data: %d+ trail dots", said)
    rawset(_G, "C_Timer", timers)
    rawset(_G, "debugprofilestop", nil)
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
    assert.is_nil(out:find("TomTom", 1, true)) -- no other addon is looked for
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
    assert.equals(26, checks)
    assert.matches("%[PASS%] dungeons: 19 in data", out)
    assert.matches("%[PASS%] target preview: models true", out)
    assert.matches("%[PASS%] class quests: %d+ in data for HUNTER", out)
    assert.matches("%[PASS%] class quests: handed in: the game answered for %d+ of %d+; handed in: none", out)
    assert.matches("%[PASS%] class quests: level by level: [^\n]*10: [^\n]*Taming the Beast", out)
    assert.matches("%[PASS%] class quests: plan: [^\n]*3 steps", out)
    assert.equals(planBefore, _G.TrailMateCharDB.plan)
    assert.is_nil(_G.TrailMateCharDB.prefs.focusZone)
  end)

  it("learns the way walked and follows it with the arrow and dots on the map", function()
    local function vec(x, y)
      return { x = x, y = y, GetXY = function(self) return self.x, self.y end }
    end
    local px, py = 0.5, 0.5
    local map = fakeObject("WorldMapFrame")
    local child = fakeObject("Canvas")
    rawset(child, "GetWidth", function() return 1000 end)
    rawset(child, "GetHeight", function() return 1000 end)
    rawset(map, "ScrollContainer", { Child = child })
    rawset(map, "GetMapID", function() return 1429 end)
    map:Show()
    local added = {
      CreateVector2D = vec,
      WorldMapFrame = map,
    }
    for k, v in pairs(added) do
      rawset(_G, k, v)
    end
    finally(function()
      for k in pairs(added) do
        rawset(_G, k, nil)
      end
    end)
    -- One map, 1000 yards across: world yards = map position x 1000.
    _G.C_Map.GetPlayerMapPosition = function() return vec(px, py) end
    _G.C_Map.GetWorldPosFromMapPos = function(_, v) return 0, vec(v.x * 1000, v.y * 1000) end
    _G.C_Map.GetMapPosFromWorldPos = function(_, v) return 1429, vec(v.x / 1000, v.y / 1000) end
    local function walkTo(x, y)
      local steps = 20
      local sx, sy = px, py
      for i = 1, steps do
        px, py = sx + (x - sx) * i / steps, sy + (y - sy) * i / steps
        eventFrame().scripts.OnUpdate(eventFrame(), 0.5)
      end
    end
    -- The player walks round a wall: north, then west to the quest at 0.3,0.3.
    walkTo(0.5, 0.3)
    walkTo(0.3, 0.3)
    _G.SlashCmdList.TRAILMATE("rastro")
    assert.matches("Rastros: activados, %d+ puntos", output())
    -- Back at the start (a jump: no line is drawn across it), following the quest.
    px, py = 0.5, 0.5
    _G.SlashCmdList.TRAILMATE("diario")
    eventFrame().scripts.OnUpdate(eventFrame(), 2)
    printed = {}
    _G.SlashCmdList.TRAILMATE("test")
    assert.matches("%[PASS%] trails: on; %d+ dots, %d+ joins; route to the arrow target %d+ dots; "
      .. "world map canvas found, %d+ dots drawn", output())
    local drawn = tonumber(output():match("found, (%d+) dots drawn"))
    assert.is_true(drawn > 10)
    -- Exported to the log in pieces, ready to ship with the addon.
    _G.SlashCmdList.TRAILMATE("rastro exportar")
    assert.matches("puntos a tu alrededor exportados", output())
    local log = table.concat(_G.TrailMateDB.log, "\n")
    assert.matches("TMR1 1/%d+ TMR1#", log)
    -- Switched off, nothing is followed.
    _G.SlashCmdList.TRAILMATE("rastro off")
    eventFrame().scripts.OnUpdate(eventFrame(), 2)
    printed = {}
    _G.SlashCmdList.TRAILMATE("test")
    assert.matches("trails: off; .- route to the arrow target none", output())
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
