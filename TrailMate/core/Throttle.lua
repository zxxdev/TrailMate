-- Coalesces bursts of game events into one evaluation.
-- QUEST_LOG_UPDATE and BAG_UPDATE can fire dozens of times in a row: the
-- adapter calls mark() on each one and tick(now) from a timer, and the work
-- runs at most once per interval. Pure Lua 5.1.

local _, ns = ...

local Throttle = {}
Throttle.__index = Throttle
ns.Throttle = Throttle

function Throttle.new(interval)
  return setmetatable({ interval = interval or 0.25, dirty = false, last = nil }, Throttle)
end

function Throttle:mark()
  self.dirty = true
end

--- Returns true when the pending work should run now.
function Throttle:tick(now)
  if not self.dirty then
    return false
  end
  if self.last ~= nil and now - self.last < self.interval then
    return false
  end
  self.dirty = false
  self.last = now
  return true
end
