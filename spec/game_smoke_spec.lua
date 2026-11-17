-- Smoke test of the whole addon against a fake game API: loads every file in
-- .toc order, fires events and runs the slash commands. It cannot prove the
-- real client behaves like the fake, but it catches wiring mistakes (typos,
-- nil calls, wrong arguments) before anyone has to find them in-game.

local frames, named, printed

local function fakeObject(name)
  local o = { scripts = {}, events = {}, name = name }
  return setmetatable(o, {
    __index = function(_, key)
      if key == "SetScript" then
        return function(self, script, fn) self.scripts[script] = fn end
      elseif key == "RegisterEvent" then
        return function(self, event) self.events[event] = true end
      elseif key == "CreateFontString" then
        return function() return fakeObject() end
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
    UnitXP = function() return 50 end,
    UnitXPMax = function() return 200 end,
    GetMoney = function() return 12345 end,
    C_QuestLog = {
      GetNumQuestLogEntries = function() return #quests end,
      GetInfo = function(i) return quests[i] end,
      IsComplete = function(id) return id == 11 end,
      IsQuestFlaggedCompleted = function() return false end,
      GetQuestsOnMap = function() return { { questID = 10, x = 0.3, y = 0.3 } } end,
    },
    C_Map = {
      GetBestMapForUnit = function() return 1429 end,
      GetPlayerMapPosition = function()
        return { GetXY = function() return 0.5, 0.5 end }
      end,
      CanSetUserWaypointOnMap = function() return true end,
      SetUserWaypoint = function() end,
      ClearUserWaypoint = function() end,
    },
    UiMapPoint = { CreateFromCoordinates = function(m, x, y) return { m, x, y } end },
    C_SuperTrack = { SetSuperTrackedUserWaypoint = function() end },
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
    assert.equals("Entregar: Jabalies", window.step.shown_text)
    _G.SlashCmdList.TRAILMATE("salta")
    assert.equals("Hacer: Lobos", window.step.shown_text)
    assert.matches("Flecha: map pin", window.arrow.shown_text)
    assert.is_true(_G.TrailMateCharDB.plan.steps[1] ~= nil)
  end)

  it("restores a saved plan after a reload", function()
    _G.SlashCmdList.TRAILMATE("diario")
    local saved = _G.TrailMateCharDB
    install()
    rawset(_G, "TrailMateCharDB", saved)
    loadAddon()
    fire("ADDON_LOADED", "TrailMate")
    assert.equals("Entregar: Jabalies", named.TrailMateFrame.step.shown_text)
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
