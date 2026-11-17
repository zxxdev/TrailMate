-- Travel planner: the quickest way to another zone, by comparing walking,
-- flying, the hearthstone and ships or zeppelins. Pure Lua 5.1.
--
-- Everything is in world coordinates (yards) with a continent id, so places
-- in different zones can be compared. The adapter fills it from the game:
-- the flight points the world map shows (only the player's faction), which
-- ones the player knows, which routes were seen open at a flight master,
-- and where the hearthstone is bound and whether it is ready.
--
-- Times are rough estimates to compare options, not promises.

local _, ns = ...

local Travel = {}
ns.Travel = Travel

Travel.RUN = 7 -- yards per second on foot
Travel.MOUNT = 11.2 -- with a classic 60% mount
Travel.FLY = 30 -- taxi speed
Travel.TAXI_OVERHEAD = 30 -- talking to the flight master, take-off, landing
Travel.HEARTH = 40 -- cast plus loading screen
-- The hearthstone then waits an hour: only worth it if it saves real time.
Travel.HEARTH_VALUE = 300
Travel.SHIP = 300 -- waiting for and riding a ship or zeppelin
Travel.WALK_YARDS = 1500 -- below this, walking is always offered first

-- Zeppelins and ships of the classic world, both ways. Places are map
-- coordinates (uiMapID, x, y) of the docks, from the classic maps and not
-- checked in WoW Forever; the adapter turns them into world positions.
-- faction nil: anyone may take it.
Travel.SHIPS = {
  { kind = "zeppelin", faction = "Horde",
    a = { name = "the zeppelin tower outside Orgrimmar (Durotar)", mapID = 1411, x = 0.506, y = 0.126 },
    b = { name = "Grom'gol (Stranglethorn Vale)", mapID = 1434, x = 0.316, y = 0.291 } },
  { kind = "zeppelin", faction = "Horde",
    a = { name = "the zeppelin tower outside Orgrimmar (Durotar)", mapID = 1411, x = 0.508, y = 0.136 },
    b = { name = "the zeppelin tower outside Undercity (Tirisfal Glades)", mapID = 1420, x = 0.607, y = 0.588 } },
  { kind = "zeppelin", faction = "Horde",
    a = { name = "Grom'gol (Stranglethorn Vale)", mapID = 1434, x = 0.316, y = 0.291 },
    b = { name = "the zeppelin tower outside Undercity (Tirisfal Glades)", mapID = 1420, x = 0.619, y = 0.590 } },
  { kind = "ship",
    a = { name = "the docks of Booty Bay (Stranglethorn Vale)", mapID = 1434, x = 0.259, y = 0.731 },
    b = { name = "the docks of Ratchet (The Barrens)", mapID = 1413, x = 0.636, y = 0.386 } },
  { kind = "ship", faction = "Alliance",
    a = { name = "the docks of Menethil Harbor (Wetlands)", mapID = 1437, x = 0.050, y = 0.634 },
    b = { name = "the docks of Theramore (Dustwallow Marsh)", mapID = 1445, x = 0.716, y = 0.564 } },
  { kind = "ship", faction = "Alliance",
    a = { name = "the docks of Menethil Harbor (Wetlands)", mapID = 1437, x = 0.046, y = 0.571 },
    b = { name = "the docks of Auberdine (Darkshore)", mapID = 1439, x = 0.325, y = 0.438 } },
  { kind = "ship", faction = "Alliance",
    a = { name = "the docks of Auberdine (Darkshore)", mapID = 1439, x = 0.332, y = 0.400 },
    b = { name = "Rut'theran Village (Teldrassil)", mapID = 1438, x = 0.549, y = 0.968 } },
}

local function dist(a, b)
  return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2)
end

local function sameCont(a, b)
  return a and b and a.cont ~= nil and a.cont == b.cont
end

-- Best way from a point to the destination without the hearthstone.
-- Returns cost (seconds), steps; or nil when it needs a ship.
local function overland(from, dest, ctx)
  if not sameCont(from, dest) then
    return nil
  end
  local speed = ctx.speed or Travel.RUN
  local walkCost = dist(from, dest) / speed
  local best, bestSteps = walkCost, { { kind = "walk", to = dest } }
  for _, a in ipairs(ctx.nodes or {}) do
    if a.known and sameCont(a, from) then
      for _, b in ipairs(ctx.nodes) do
        if b ~= a and b.known and sameCont(b, dest) and (ctx.reach == nil or ctx.reach(a, b) ~= false) then
          local cost = dist(from, a) / speed + Travel.TAXI_OVERHEAD + dist(a, b) / Travel.FLY + dist(b, dest) / speed
          if cost < best then
            best = cost
            local confirmed = ctx.reach ~= nil and ctx.reach(a, b) == true
            bestSteps = {
              { kind = "walk", to = a },
              { kind = "fly", from = a, to = b, confirmed = confirmed },
              { kind = "walk", to = dest },
            }
          end
        end
      end
    end
  end
  return best, bestSteps
end

local function append(list, more)
  for _, s in ipairs(more) do
    list[#list + 1] = s
  end
  return list
end

-- Best way through one zeppelin or ship (either way round), or nil.
-- ships = { { kind, a = dock, b = dock } } with docks in world yards.
local function byShip(from, dest, ctx)
  local best, bestSteps
  for _, ship in ipairs(ctx.ships or {}) do
    for _, ends in ipairs({ { ship.a, ship.b }, { ship.b, ship.a } }) do
      local board, land = ends[1], ends[2]
      if sameCont(from, board) and sameCont(land, dest) then
        local before, beforeSteps = overland(from, board, ctx)
        local after, afterSteps = overland(land, dest, ctx)
        if before and after and (not best or before + Travel.SHIP + after < best) then
          best = before + Travel.SHIP + after
          bestSteps = append(append({}, beforeSteps), { { kind = "ship", ship = ship.kind, from = board, to = land } })
          append(bestSteps, afterSteps)
        end
      end
    end
  end
  return best, bestSteps
end

--- Plans the trip. ctx = { here, dest, nodes, reach, hearth, speed, ships } where
--- here and dest are { cont, x, y } in world yards, nodes are flight points
--- { name, cont, x, y, known, mapID, mx, my }, reach(a, b) is true, false or
--- nil (unknown), and hearth is { cont, x, y, name, ready, cooldown } or nil.
--- Returns { mode, cost, steps } with mode "walk", "fly", "hearth" or
--- "ship", or nil if there is nothing to plan.
function Travel.plan(ctx)
  local here, dest = ctx.here, ctx.dest
  if not (here and dest and here.x and dest.x) then
    return nil
  end
  local options = {}
  local cost, steps = overland(here, dest, ctx)
  if cost then
    options[#options + 1] = { cost = cost, steps = steps }
  end
  local shipCost, shipSteps = byShip(here, dest, ctx)
  if shipCost then
    options[#options + 1] = { cost = shipCost, steps = shipSteps }
  end
  local h = ctx.hearth
  if h and h.ready and h.x then
    for _, way in ipairs({ { overland(h, dest, ctx) }, { byShip(h, dest, ctx) } }) do
      local after, afterSteps = way[1], way[2]
      if after then
        options[#options + 1] = {
          cost = Travel.HEARTH + Travel.HEARTH_VALUE + after, real = Travel.HEARTH + after,
          steps = append({ { kind = "hearth", to = h } }, afterSteps),
        }
      end
    end
  end
  if #options == 0 then
    -- Another continent and no hearthstone there: a ship or a zeppelin.
    local nearest
    for _, n in ipairs(ctx.nodes or {}) do
      if n.known and sameCont(n, here) and (nearest == nil or dist(here, n) < dist(here, nearest)) then
        nearest = n
      end
    end
    return { mode = "ship", cost = Travel.SHIP, steps = { { kind = "ship", via = nearest } } }
  end
  table.sort(options, function(a, b)
    return a.cost < b.cost
  end)
  local best = options[1]
  -- Keep it simple when the destination is close: just walk.
  if cost and dist(here, dest) <= Travel.WALK_YARDS then
    best = { cost = cost, steps = { { kind = "walk", to = dest } } }
  end
  local mode = "walk"
  for _, s in ipairs(best.steps) do
    if s.kind == "hearth" then
      mode = "hearth"
      break
    elseif s.kind == "ship" then
      mode = "ship"
    elseif s.kind == "fly" and mode ~= "ship" then
      mode = "fly"
    end
  end
  return { mode = mode, cost = best.real or best.cost, steps = best.steps }
end

--- "4 min" style text for a cost in seconds.
function Travel.minutes(seconds)
  return ("%d min"):format(math.max(1, math.floor(seconds / 60 + 0.5)))
end
