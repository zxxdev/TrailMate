-- The log: everything TrailMate tells you, kept in saved variables so long
-- outputs can be read in the panel and copied to report a problem.
-- Pure Lua 5.1. Colour codes and link markup are stripped.

local _, ns = ...

local Log = {}
ns.Log = Log

Log.MAX = 400

--- Plain text for a chat line: no colour codes, links shown as their name.
function Log.plain(line)
  local s = tostring(line or "")
  s = s:gsub("|H.-|h(.-)|h", "%1")
  s = s:gsub("|c%x%x%x%x%x%x%x%x", "")
  s = s:gsub("|r", "")
  return s
end

--- Adds a line, keeping only the newest Log.MAX.
function Log.add(store, line, stamp)
  if type(store) ~= "table" then
    return
  end
  local s = Log.plain(line)
  store[#store + 1] = stamp and (stamp .. " " .. s) or s
  while #store > Log.MAX do
    table.remove(store, 1)
  end
end

--- All lines as one text, oldest first.
function Log.text(store)
  if type(store) ~= "table" then
    return ""
  end
  return table.concat(store, "\n")
end
