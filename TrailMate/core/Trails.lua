-- Trails: the paths the player has really walked, kept as dots joined into
-- a network, so the arrow and the map can follow streets, gates and bridges
-- instead of a straight line into a wall. Pure Lua 5.1.
--
-- The game does not tell addons where walls or roads are; it only gives
-- positions. So TrailMate learns the way by walking it: every few yards a
-- dot, joined to the previous one. A dot close to an old one reuses it, so
-- crossing an old trail joins the two. The first time through a place there
-- is nothing to follow; after that, there is.
--
-- Saved shape (account-wide, the world is the same for every character):
-- { nodes = { { cont, x, y }, ... }, links = { [i] = { j, ... } } }
-- Positions are world yards, as Api.worldPos gives them.

local _, ns = ...

local Trails = {}
ns.Trails = Trails

Trails.STEP = 12 -- yards between recorded dots
Trails.SNAP = 6 -- a new dot this close to an old one reuses it
Trails.LINK = 40 -- never join two dots further apart than this
Trails.START = 60 -- the trail must pass this close to the player
Trails.MAX = 6000 -- dots kept at most (the saved file stays small)
Trails.AHEAD = 20 -- a dot this close counts as reached
Trails.MIN_ALONG = 40 -- a trail is only followed for at least this many yards
Trails.MIN_GAIN = 30 -- ...and only if it ends this much closer to the goal
-- Walking off the trail in a straight line is risky (walls): that part
-- counts double when choosing how far to follow the trail.
Trails.OFF_TRAIL = 2

local CELL = 25
local grids = setmetatable({}, { __mode = "k" }) -- search index, never saved

local function dist(ax, ay, bx, by)
  local dx, dy = ax - bx, ay - by
  return math.sqrt(dx * dx + dy * dy)
end

local function key(c, cx, cy)
  return c .. ":" .. cx .. ":" .. cy
end

local function cellOf(v)
  return math.floor(v / CELL)
end

local function addToGrid(g, i, n)
  local k = key(n[1], cellOf(n[2]), cellOf(n[3]))
  g[k] = g[k] or {}
  table.insert(g[k], i)
end

--- Rebuilds the search index (after loading the saved trails).
function Trails.index(t)
  local g = {}
  for i, n in ipairs(t.nodes) do
    addToGrid(g, i, n)
  end
  grids[t] = g
  return g
end

--- The trails stored in db.trails, created or repaired if needed.
function Trails.ensure(db)
  local t = db.trails
  if type(t) ~= "table" or type(t.nodes) ~= "table" or type(t.links) ~= "table" then
    t = { nodes = {}, links = {} }
    db.trails = t
  end
  Trails.index(t)
  return t
end

--- The dot nearest to a point within maxDist yards: index, distance; or nil.
--- mapID (optional): only dots recorded on that map. Cities with floors
--- (Undercity under the ruins) share x and y between floors, but not the
--- map: the map keeps the floors apart.
function Trails.nearest(t, c, x, y, maxDist, mapID)
  local g = grids[t] or Trails.index(t)
  local r = math.ceil(maxDist / CELL)
  local cx, cy = cellOf(x), cellOf(y)
  local best, bestDist
  for dx = -r, r do
    for dy = -r, r do
      for _, i in ipairs(g[key(c, cx + dx, cy + dy)] or {}) do
        local n = t.nodes[i]
        local d = dist(x, y, n[2], n[3])
        local sameFloor = mapID == nil or n[4] == nil or n[4] == mapID
        if sameFloor and d <= maxDist and (not bestDist or d < bestDist) then
          best, bestDist = i, d
        end
      end
    end
  end
  return best, bestDist
end

local function join(t, a, b)
  t.links[a] = t.links[a] or {}
  for _, j in ipairs(t.links[a]) do
    if j == b then
      return
    end
  end
  table.insert(t.links[a], b)
end

local function round(v)
  return math.floor(v * 10 + 0.5) / 10
end

--- Adds a dot where the player is, joined to the previous dot (prev).
--- mapID: the map the player is on (keeps floors apart; the step from one
--- map to the next, like a lift, is still joined because it was walked).
--- Returns the dot's index (an old one if close enough), or nil when full.
function Trails.add(t, c, x, y, prev, mapID)
  local i = Trails.nearest(t, c, x, y, Trails.SNAP, mapID)
  if not i then
    if #t.nodes >= Trails.MAX then
      return nil
    end
    t.nodes[#t.nodes + 1] = { c, round(x), round(y), mapID }
    i = #t.nodes
    addToGrid(grids[t] or Trails.index(t), i, t.nodes[i])
  end
  local p = prev and t.nodes[prev]
  if p and prev ~= i and p[1] == c and dist(p[2], p[3], t.nodes[i][2], t.nodes[i][3]) <= Trails.LINK then
    join(t, prev, i)
    join(t, i, prev)
  end
  return i
end

-- A small binary heap of { cost, index }, cheapest first.
local function push(heap, cost, i)
  heap[#heap + 1] = { cost, i }
  local k = #heap
  while k > 1 do
    local parent = math.floor(k / 2)
    if heap[parent][1] <= heap[k][1] then
      break
    end
    heap[parent], heap[k] = heap[k], heap[parent]
    k = parent
  end
end

local function pop(heap)
  local top = heap[1]
  local last = table.remove(heap)
  if #heap > 0 then
    heap[1] = last
    local k = 1
    while true do
      local l, r, small = 2 * k, 2 * k + 1, k
      if heap[l] and heap[l][1] < heap[small][1] then
        small = l
      end
      if heap[r] and heap[r][1] < heap[small][1] then
        small = r
      end
      if small == k then
        break
      end
      heap[small], heap[k] = heap[k], heap[small]
      k = small
    end
  end
  return top
end

--- The way from here to goal along walked trails, as dots { cont, x, y }
--- ending with the goal; or nil when no trail helps (none near the player,
--- or going straight is as good). here and goal are { cont, x, y }.
---
--- It follows the trail as far as it pays: each dot is scored by the walk
--- along the trail to it plus the straight line left to the goal (counted
--- double, it may cross walls), and the best dot ends the trail part.
--- When there is no route, the second value says why (for the self-test).
function Trails.route(t, here, goal)
  if not (here and goal) or here.cont ~= goal.cont then
    return nil, "target on another continent or unknown"
  end
  local straight = dist(here.x, here.y, goal.x, goal.y)
  if straight < Trails.AHEAD * 2 then
    return nil, "target close by"
  end
  -- Start from a dot on the player's own floor (here.mapID, if known).
  local start, d0 = Trails.nearest(t, here.cont, here.x, here.y, Trails.START, here.mapID)
  if not start then
    return nil, ("no learned dot within %d yards of you"):format(Trails.START)
  end
  local walked, from = { [start] = d0 }, {}
  local heap = {}
  push(heap, d0, start)
  local best, bestCost = nil, Trails.OFF_TRAIL * straight
  while #heap > 0 do
    local item = pop(heap)
    local d, i = item[1], item[2]
    if d > bestCost then
      break -- nothing further on can beat the best found
    end
    if d <= walked[i] then
      local n = t.nodes[i]
      local cost = d + Trails.OFF_TRAIL * dist(n[2], n[3], goal.x, goal.y)
      if cost < bestCost then
        best, bestCost = i, cost
      end
      for _, j in ipairs(t.links[i] or {}) do
        local m = t.nodes[j]
        local nd = d + dist(n[2], n[3], m[2], m[3])
        if not walked[j] or nd < walked[j] then
          walked[j], from[j] = nd, i
          push(heap, nd, j)
        end
      end
    end
  end
  if not best or best == start then
    return nil, ("the trails near you do not lead towards the target (straight %.0f yards)"):format(straight)
  end
  -- Only a trail that really leads somewhere: a real stretch walked that
  -- ends clearly closer to the goal. A couple of dots next to the player
  -- would only add a straight line through the wall.
  local last = t.nodes[best]
  local along = walked[best] - d0
  local left = dist(last[2], last[3], goal.x, goal.y)
  if along < Trails.MIN_ALONG or left > straight - Trails.MIN_GAIN then
    return nil, ("the best trail is too short (%.0f yards along, %.0f of %.0f yards left)"):format(along, left,
      straight)
  end
  local path, i = {}, best
  while i do
    local n = t.nodes[i]
    table.insert(path, 1, { cont = n[1], x = n[2], y = n[3] })
    i = from[i]
  end
  path[#path + 1] = { cont = goal.cont, x = goal.x, y = goal.y }
  return path
end

--- The dot the arrow should point at now: the one after the furthest dot
--- already reached, or the first dot if none is.
function Trails.next(path, here)
  local reached = 0
  for i, p in ipairs(path) do
    if dist(p.x, p.y, here.x, here.y) <= Trails.AHEAD then
      reached = i
    end
  end
  return path[reached + 1]
end

--- The learned dots around a point (to check what was recorded), as
--- { cont, x, y }, the nearest first, at most max.
function Trails.around(t, c, x, y, radius, max)
  local found = {}
  for _, n in ipairs(t.nodes) do
    if n[1] == c then
      local d = dist(n[2], n[3], x, y)
      if d <= radius then
        found[#found + 1] = { d = d, cont = n[1], x = n[2], y = n[3] }
      end
    end
  end
  table.sort(found, function(a, b)
    return a.d < b.d
  end)
  local out = {}
  for i = 1, math.min(max, #found) do
    out[i] = { cont = found[i].cont, x = found[i].x, y = found[i].y }
  end
  return out
end

-- Sharing trails ---------------------------------------------------------------
--
-- The capitals' ways (Orgrimmar's zigzag gate, Undercity's floors and lifts)
-- ship with the addon so a new player can follow them from day one. They
-- are walked once with TrailMate, exported as text (/tm trail export), and
-- turned into TrailMate/data/Routes.lua by tools/import_routes.lua.
--
-- Text: "TMR1#c,x,y,map;c,x,y,map;...#a,b;a,b;..." (dots, then joins
-- between dot numbers, counted from 1).

--- The dots within radius yards of a point, with their joins, as text.
--- Returns the text and how many dots it holds.
function Trails.export(t, c, x, y, radius)
  local pick, index = {}, {}
  for i, n in ipairs(t.nodes) do
    if n[1] == c and dist(n[2], n[3], x, y) <= radius then
      pick[#pick + 1] = i
      index[i] = #pick
    end
  end
  local dots, joins = {}, {}
  for k, i in ipairs(pick) do
    local n = t.nodes[i]
    dots[k] = ("%d,%.1f,%.1f,%s"):format(n[1], n[2], n[3], n[4] and tostring(n[4]) or "")
    for _, j in ipairs(t.links[i] or {}) do
      if index[j] and k < index[j] then
        joins[#joins + 1] = k .. "," .. index[j]
      end
    end
  end
  return "TMR1#" .. table.concat(dots, ";") .. "#" .. table.concat(joins, ";"), #pick
end

--- Reads exported text back: { nodes = { { c, x, y, map } }, links = { { a, b } } },
--- or nil if it is not trail text.
function Trails.parse(text)
  local dots, joins = tostring(text or ""):match("^%s*TMR1#([^#]*)#([^#]*)%s*$")
  if not dots then
    return nil
  end
  local data = { nodes = {}, links = {} }
  for c, x, y, m in dots:gmatch("(%-?%d+),(%-?[%d%.]+),(%-?[%d%.]+),(%d*)") do
    data.nodes[#data.nodes + 1] = { tonumber(c), tonumber(x), tonumber(y), tonumber(m) }
  end
  for a, b in joins:gmatch("(%d+),(%d+)") do
    data.links[#data.links + 1] = { tonumber(a), tonumber(b) }
  end
  return data
end

--- Adds shared trails to the player's own: dots close to known ones are
--- merged, so importing twice changes nothing. Returns the dots it added.
function Trails.import(t, data)
  local before = #t.nodes
  local placed = {}
  local function place(k, prev)
    local n = data.nodes[k]
    if not n then
      return nil
    end
    local i = Trails.add(t, n[1], n[2], n[3], prev, n[4])
    placed[k] = placed[k] or i
    return i
  end
  for _, link in ipairs(data.links) do
    local a = placed[link[1]] or place(link[1])
    if a then
      place(link[2], a)
    end
  end
  for k in ipairs(data.nodes) do
    if not placed[k] then
      place(k)
    end
  end
  return #t.nodes - before
end

--- How many dots and joins are stored, for the self-test.
function Trails.counts(t)
  local links = 0
  for _, list in pairs(t.links) do
    links = links + #list
  end
  return #t.nodes, links / 2
end
