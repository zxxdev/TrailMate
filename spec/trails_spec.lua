local helper = require("spec.helper")

describe("Trails", function()
  local Trails, t

  -- Walks along a list of corners, dropping a dot every STEP yards, like
  -- the recorder does in the game. Returns the last dot.
  local function walk(corners, prev)
    local x, y = corners[1][1], corners[1][2]
    prev = Trails.add(t, 0, x, y, prev)
    for i = 2, #corners do
      local tx, ty = corners[i][1], corners[i][2]
      local len = math.sqrt((tx - x) ^ 2 + (ty - y) ^ 2)
      local steps = math.max(1, math.floor(len / Trails.STEP))
      for s = 1, steps do
        prev = Trails.add(t, 0, x + (tx - x) * s / steps, y + (ty - y) * s / steps, prev)
      end
      x, y = tx, ty
    end
    return prev
  end

  -- Orgrimmar's way out, simplified: a chicane, then the road north to the tower.
  local CHICANE = { { 0, 0 }, { 0, 60 }, { 60, 60 }, { 60, 120 }, { 0, 120 }, { 0, 400 } }

  before_each(function()
    Trails = helper.load().Trails
    t = Trails.ensure({})
  end)

  it("reuses a dot when walking close to it, and joins dots in a row", function()
    local a = Trails.add(t, 0, 0, 0)
    local b = Trails.add(t, 0, 12, 0, a)
    assert.equals(a, Trails.add(t, 0, 2, 1, b)) -- 2 yards away: the same dot
    assert.same({ b }, t.links[a])
    local nodes, links = Trails.counts(t)
    assert.same({ 2, 1 }, { nodes, links })
  end)

  it("does not join dots across a flight or a loading screen", function()
    local a = Trails.add(t, 0, 0, 0)
    local far = Trails.add(t, 0, 500, 0, a)
    assert.is_nil(t.links[far])
    local other = Trails.add(t, 1, 12, 0, a) -- another continent
    assert.is_nil(t.links[other])
  end)

  it("follows the walked chicane instead of the straight line (the user's Orgrimmar case)", function()
    walk(CHICANE)
    local path = Trails.route(t, { cont = 0, x = 0, y = 0 }, { cont = 0, x = 0, y = 420 })
    assert.is_table(path)
    local wentEast = false
    for _, p in ipairs(path) do
      wentEast = wentEast or p.x > 50
    end
    assert.is_true(wentEast) -- through the chicane
    assert.same({ cont = 0, x = 0, y = 420 }, path[#path]) -- ends at the goal
    -- The arrow points at the next dot not yet reached.
    local nextDot = Trails.next(path, { x = 0, y = 0 })
    assert.same({ 0, 24 }, { nextDot.x, nextDot.y })
    -- Halfway through the chicane, it points further along it.
    nextDot = Trails.next(path, { x = 60, y = 90 })
    assert.is_true(nextDot.y > 90)
  end)

  it("gives no route when no trail helps", function()
    walk(CHICANE)
    -- Nothing walked near the player.
    assert.is_nil(Trails.route(t, { cont = 0, x = 500, y = 500 }, { cont = 0, x = 0, y = 420 }))
    -- The trail goes the other way: straight is better.
    assert.is_nil(Trails.route(t, { cont = 0, x = 0, y = 0 }, { cont = 0, x = 0, y = -300 }))
    -- Another continent, or the goal is right here.
    assert.is_nil(Trails.route(t, { cont = 0, x = 0, y = 0 }, { cont = 1, x = 0, y = 420 }))
    assert.is_nil(Trails.route(t, { cont = 0, x = 0, y = 0 }, { cont = 0, x = 0, y = 20 }))
  end)

  it("follows no trail that stops far from the target (the user's case: Orgrimmar to Desolace)", function()
    walk(CHICANE)
    -- The same chicane leads the right way, but the goal is far beyond its end.
    local path, why = Trails.route(t, { cont = 0, x = 0, y = 0 }, { cont = 0, x = 0, y = 3000 })
    assert.is_nil(path)
    assert.matches("end far from the target", why)
  end)

  it("never turns a few dots next to the player into a straight line through the wall (the user's case)", function()
    -- A few steps walked towards the gate, nothing further.
    walk({ { 0, 0 }, { 0, 30 } })
    assert.is_nil(Trails.route(t, { cont = 0, x = 0, y = 0 }, { cont = 0, x = 300, y = 300 }))
  end)

  it("keeps the floors of a city apart (Undercity under the ruins)", function()
    -- Same x and y, different maps: two dots, not one.
    local upper = Trails.add(t, 0, 100, 100, nil, 1420)
    local lower = Trails.add(t, 0, 100, 100, nil, 1458)
    assert.are_not.equal(upper, lower)
    -- The lift: walked from one floor to the other, so the two are joined.
    local lift = Trails.add(t, 0, 101, 100, upper, 1458)
    assert.equals(lower, lift)
    assert.same({ lower }, t.links[upper])
    -- A player on the lower floor never starts from an upper floor dot.
    assert.equals(lower, (Trails.nearest(t, 0, 100, 100, 10, 1458)))
    assert.equals(upper, (Trails.nearest(t, 0, 100, 100, 10, 1420)))
  end)

  it("exports a walked city as text and imports it into a new player's trails", function()
    walk(CHICANE)
    Trails.add(t, 0, 5000, 5000) -- far away: not exported
    local text, count = Trails.export(t, 0, 0, 0, 1000)
    assert.matches("^TMR1#", text)
    local data = Trails.parse(text)
    assert.equals(count, #data.nodes)
    -- A new player with no trails gets the chicane and can follow it.
    local fresh = Trails.ensure({})
    assert.equals(count, Trails.import(fresh, data))
    local path = Trails.route(fresh, { cont = 0, x = 0, y = 0 }, { cont = 0, x = 0, y = 420 })
    assert.is_table(path)
    -- Importing again adds nothing.
    assert.equals(0, Trails.import(fresh, data))
    -- Floors survive the trip.
    local floors = Trails.ensure({})
    Trails.add(floors, 0, 1, 1, nil, 1458)
    assert.equals(1458, Trails.parse((Trails.export(floors, 0, 0, 0, 10))).nodes[1][4])
    assert.is_nil(Trails.parse("hello"))
  end)

  it("explains why there is no route", function()
    walk(CHICANE)
    local _, why = Trails.route(t, { cont = 0, x = 500, y = 500 }, { cont = 0, x = 0, y = 420 })
    assert.matches("no learned dot within", why)
  end)

  it("keeps the saved file small and repairs bad saved data", function()
    local max = Trails.MAX
    Trails.MAX = 2
    finally(function()
      Trails.MAX = max
    end)
    Trails.add(t, 0, 0, 0)
    Trails.add(t, 0, 100, 0)
    assert.is_nil(Trails.add(t, 0, 200, 0))
    local db = { trails = "broken" }
    assert.same({ nodes = {}, links = {} }, Trails.ensure(db))
    -- Saved trails are found again after a reload.
    local saved = { trails = { nodes = { { 0, 5, 5 } }, links = {} } }
    local loaded = Trails.ensure(saved)
    assert.equals(1, (Trails.nearest(loaded, 0, 6, 6, 10)))
  end)
end)
