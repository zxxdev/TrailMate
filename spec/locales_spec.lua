local helper = require("spec.helper")

-- Every language of the game's client: English is the keys themselves,
-- Spanish (Spain and Mexico) is in core/Locale.lua, the rest in core/locales.
local FILES = { "deDE", "frFR", "itIT", "ptBR", "ruRU", "koKR", "zhCN", "zhTW" }

describe("translations", function()
  local ns

  before_each(function()
    ns = helper.load()
    for _, code in ipairs(FILES) do
      local chunk = loadfile("TrailMate/core/locales/" .. code .. ".lua")
      if chunk then
        chunk("TrailMate", ns)
      end
    end
  end)

  -- The format holes of a text, in order: "%s %d" (a literal %% is not one).
  local function holes(text)
    local out = {}
    for hole in text:gmatch("%%[%%%a]") do
      if hole ~= "%%" then
        out[#out + 1] = hole
      end
    end
    return table.concat(out, " ")
  end

  it("has a file for every language of the game's client", function()
    for _, code in ipairs(FILES) do
      local t = ns.LOCALES[code]
      assert.is_table(t, code)
      -- Most of the texts: a few with place or talent names may stay English.
      local n = 0
      for _ in pairs(t) do
        n = n + 1
      end
      assert.is_true(n > 300, code .. " has only " .. n .. " texts")
    end
  end)

  it("translates only texts that exist, with the same %s and %d in the same order", function()
    local english = ns.LOCALES.esES -- every text has its Spanish
    for code, t in pairs(ns.LOCALES) do
      for key, text in pairs(t) do
        assert.is_not_nil(english[key], code .. ": no such text: " .. key)
        assert.equals(holes(key), holes(text), code .. ": " .. key)
        -- And it really formats with the key's arguments.
        local args = {}
        for hole in holes(key):gmatch("%S+") do
          args[#args + 1] = hole == "%d" and 1 or "x"
        end
        assert.has_no.errors(function()
          text:format(unpack(args))
        end, code .. ": " .. key)
      end
    end
  end)

  it("shows the player's language, and English where a text has no translation", function()
    ns.setLocale("deDE")
    assert.equals("Erledigt", ns.L["Done"])
    assert.equals("No such text", ns.L["No such text"])
    ns.setLocale("esMX")
    assert.equals("Hecho", ns.L["Done"])
    ns.setLocale("enUS")
    assert.equals("Done", ns.L["Done"])
    ns.setLocale("enGB")
    assert.equals("Done", ns.L["Done"])
  end)
end)
