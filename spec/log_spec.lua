local helper = require("spec.helper")

describe("Log", function()
  local Log

  before_each(function()
    Log = helper.load().Log
  end)

  it("strips colour codes and shows links by their name", function()
    local line = "|cff9b7bd4TrailMate|r: Sell |cff9d9d9d|Hitem:1::::|h[Junk]|h|r"
    assert.equals("TrailMate: Sell [Junk]", Log.plain(line))
  end)

  it("keeps only the newest lines, with a time stamp", function()
    local store = {}
    for i = 1, Log.MAX + 10 do
      Log.add(store, "line " .. i, "10:00")
    end
    assert.equals(Log.MAX, #store)
    assert.equals("10:00 line 11", store[1])
    assert.matches("line " .. (Log.MAX + 10) .. "$", Log.text(store))
  end)

  it("ignores a missing store", function()
    Log.add(nil, "x")
    assert.equals("", Log.text(nil))
  end)
end)
