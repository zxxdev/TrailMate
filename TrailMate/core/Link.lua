-- The link between TrailMate and trailmate-bridge, the small program on
-- your PC that talks to your AI companion. An addon cannot open files or
-- network connections, so both channels use things the game allows. The
-- idea comes from Witchcraft (MIT, github.com/Geraldlol/witchcraft); the
-- code here is TrailMate's own.
--
-- Game -> PC: the addon puts one frame of a message on an unused key
--   combination (SetBinding) and asks the game to save the key bindings.
--   The game writes bindings-cache.wtf at once and the bridge reads it.
--   A frame carries 32 bytes; four keys carry four frames at a time.
-- PC -> game: the bridge writes its answer into small load-on-demand
--   addons, TrailMate_Inbox_0001 to _1000, made once by
--   "trailmate-bridge init". The addon loads the next one (LoadAddOn) and
--   reads the data it holds. Each loads once per session: after the last
--   one, a /reload starts again.
--
-- Nothing here is code from the PC: an inbox holds one call with a table of
-- plain data, checked before use. The companion has no tools: it answers
-- in text, nothing else.
--
-- This file is the pure part: encoding, frames and the state of the
-- conversation, with the game's functions passed in by game/Chat.lua.

local _, ns = ...

local Link = {}
ns.Link = Link

-- Key combinations nobody uses (Witchcraft takes F9 to F12).
Link.KEYS = { "CTRL-ALT-SHIFT-F5", "CTRL-ALT-SHIFT-F6", "CTRL-ALT-SHIFT-F7", "CTRL-ALT-SHIFT-F8" }
Link.PREFIX = "TrailMateCarrier_"
Link.MAX_PAYLOAD = 32 -- bytes per frame
Link.MAX_PARTS = 64 -- frames per message: 2 KiB
Link.RING = 1000 -- inbox addons
Link.INBOX = "TrailMate_Inbox_%04d"
Link.PROTOCOL = 1
Link.MAX_REPLY = 4000

-- Seconds.
Link.WRITE_GAP = 1 -- between two writes of the key bindings
Link.POLL_ACK = 1 -- while frames wait for the bridge
Link.POLL_REPLY = 2 -- while the companion thinks
Link.POLL_SLOW = 4
Link.NO_BRIDGE = 20 -- no acknowledgement: is the bridge running?
Link.GIVE_UP = 180 -- no answer at all
-- Inboxes the bridge fills ahead of the one the addon announced; the addon
-- announces again before it runs past them.
Link.WINDOW = 64
Link.REANNOUNCE = 40

local ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"

-- Bits without the bit library (Lua 5.1).
local function bxor(a, b)
  local out, bit = 0, 1
  for _ = 1, 32 do
    local x, y = a % 2, b % 2
    if x ~= y then
      out = out + bit
    end
    a, b, bit = (a - x) / 2, (b - y) / 2, bit * 2
  end
  return out
end

local CRC_TABLE = {}
for i = 0, 255 do
  local c = i
  for _ = 1, 8 do
    if c % 2 == 1 then
      c = bxor(math.floor(c / 2), 0xEDB88320)
    else
      c = math.floor(c / 2)
    end
  end
  CRC_TABLE[i] = c
end

--- CRC-32 (IEEE, as Go's hash/crc32) of a string.
function Link.crc32(s)
  local crc = 0xFFFFFFFF
  for i = 1, #s do
    local index = bxor(crc, s:byte(i)) % 256
    crc = bxor(math.floor(crc / 256), CRC_TABLE[index])
  end
  return bxor(crc, 0xFFFFFFFF)
end

-- Eight hex digits, built from two halves: a 32-bit "%X" is not safe on
-- every Lua build.
local function hex32(v)
  return ("%04X%04X"):format(math.floor(v / 65536), v % 65536)
end

--- Base32 (RFC 4648 alphabet, no padding), as Go's base32 without padding.
function Link.base32(s)
  local out, acc, bits = {}, 0, 0
  for i = 1, #s do
    acc, bits = acc * 256 + s:byte(i), bits + 8
    while bits >= 5 do
      bits = bits - 5
      local d = math.floor(acc / 2 ^ bits)
      out[#out + 1] = ALPHABET:sub(d + 1, d + 1)
      acc = acc % 2 ^ bits
    end
  end
  if bits > 0 then
    local d = acc * 2 ^ (5 - bits)
    out[#out + 1] = ALPHABET:sub(d + 1, d + 1)
  end
  return table.concat(out)
end

--- The bytes of a base32 text, or nil if it is not exactly one.
function Link.unbase32(s)
  if type(s) ~= "string" or s == "" or not s:match("^[A-Z2-7]+$") then
    return nil
  end
  local out, acc, bits = {}, 0, 0
  for i = 1, #s do
    acc, bits = acc * 32 + ALPHABET:find(s:sub(i, i), 1, true) - 1, bits + 5
    if bits >= 8 then
      bits = bits - 8
      out[#out + 1] = string.char(math.floor(acc / 2 ^ bits))
      acc = acc % 2 ^ bits
    end
  end
  local bytes = table.concat(out)
  if Link.base32(bytes) ~= s then
    return nil
  end
  return bytes
end

local function int(v, low, high)
  return type(v) == "number" and v == math.floor(v) and v >= low and v <= high
end

--- The key binding action that carries a frame:
--- CLICK TrailMateCarrier_<session>_<seq>_<slot>_<msg>_<part>_<count>_<data>_<crc>:LeftButton
--- No frame with that name exists, so pressing the key does nothing.
function Link.action(f)
  local core = ("%s%s_%06X_%04X_%06X_%02X_%02X_%s"):format(Link.PREFIX, f.session, f.seq, f.slot, f.msg, f.part,
    f.count, Link.base32(f.payload))
  return ("CLICK %s_%s:LeftButton"):format(core, hex32(Link.crc32(core)))
end

--- The frame in an action, or nil if it is not exactly one of ours.
function Link.parse(action)
  if type(action) ~= "string" then
    return nil
  end
  local core, crc = action:match("^CLICK (" .. Link.PREFIX .. "[%w_]-)_(%x%x%x%x%x%x%x%x):LeftButton$")
  if not core or hex32(Link.crc32(core)) ~= crc then
    return nil
  end
  local session, seq, slot, msg, part, count, data = core:match(
    "^" .. Link.PREFIX .. "(%x%x%x%x%x%x%x%x)_(%x+)_(%x+)_(%x+)_(%x+)_(%x+)_([A-Z2-7]+)$")
  local payload = Link.unbase32(data)
  if not (session and payload and #payload <= Link.MAX_PAYLOAD) then
    return nil
  end
  local f = { session = session, seq = tonumber(seq, 16), slot = tonumber(slot, 16), msg = tonumber(msg, 16),
    part = tonumber(part, 16), count = tonumber(count, 16), payload = payload }
  if Link.action(f) ~= action then
    return nil
  end
  return f
end

--- An inbox addon's name.
function Link.inbox(slot)
  return Link.INBOX:format(slot)
end

--- What an inbox holds, checked: { ack, thinking, error, replies = { { id,
--- text } } }, or nil and why. session: this game session's id.
function Link.envelope(p, session)
  if type(p) ~= "table" or getmetatable(p) ~= nil or p.protocol ~= Link.PROTOCOL then
    return nil, "protocol"
  end
  if p.session ~= session then
    return nil, "other session"
  end
  if not int(p.ack, 0, 16777215) then
    return nil, "ack"
  end
  local replies = {}
  for i, r in ipairs(type(p.replies) == "table" and p.replies or {}) do
    if i > 8 or type(r) ~= "table" or not int(r.id, 1, 16777215) or type(r.text) ~= "string"
      or #r.text > Link.MAX_REPLY then
      return nil, "replies"
    end
    replies[#replies + 1] = { id = r.id, text = r.text }
  end
  if p.error ~= nil and (type(p.error) ~= "string" or #p.error > 300) then
    return nil, "error"
  end
  return { ack = p.ack, thinking = p.thinking == true, error = p.error, replies = replies }
end

-- A conversation ------------------------------------------------------------

local methods = {}
methods.__index = methods

--- A conversation with the bridge. api: { getAction(key), setBinding(key,
--- action or nil) -> ok, save() -> ok, combat() -> bool, loadAddOn(name) ->
--- loaded, reason }. opts: { session (8 hex), onReply(text), ring }.
function Link.new(api, opts)
  return setmetatable({
    api = api, session = opts.session, onReply = opts.onReply, ring = opts.ring or Link.RING,
    seq = 0, msg = 0, slot = 1, queue = {}, keys = {}, seen = {},
    lastWrite = -1000, lastPoll = -1000, status = "idle", announced = 1,
  }, methods)
end

--- A random session id: 8 hex digits.
function Link.newSession(random)
  random = random or math.random
  return ("%04X%04X"):format(random(0, 65535), random(0, 65535))
end

--- Clears frames a previous session left on our keys.
function methods:scrub()
  local changed = false
  for _, key in ipairs(Link.KEYS) do
    local action = self.api.getAction(key)
    if type(action) == "string" and action:find("CLICK " .. Link.PREFIX, 1, true) == 1 then
      self.api.setBinding(key, nil)
      changed = true
    end
  end
  if changed then
    self.api.save()
  end
  return changed
end

--- Queues a message: kind "M" (a question), "C" (the character's context),
--- "N" (start a new conversation) or "P" (where to write: no content).
--- Returns false and why if it cannot go.
function methods:send(kind, text)
  local body = kind .. (text or "")
  local count = math.ceil(#body / Link.MAX_PAYLOAD)
  if count > Link.MAX_PARTS then
    return false, "too long"
  end
  self.msg = self.msg + 1
  for part = 1, count do
    self.seq = self.seq + 1
    self.queue[#self.queue + 1] = { session = self.session, seq = self.seq, msg = self.msg, part = part,
      count = count, payload = body:sub((part - 1) * Link.MAX_PAYLOAD + 1, part * Link.MAX_PAYLOAD) }
  end
  if kind == "M" then
    self.waiting, self.waitSince, self.gaveUp = true, nil, nil
  end
  return true
end

-- Our keys for frames: the ones we hold already, and the ones with nothing
-- on them. A key the player uses is never touched.
function methods:freeKeys()
  local free = {}
  for _, key in ipairs(Link.KEYS) do
    local action = self.api.getAction(key)
    if self.keys[key] or action == nil or action == "" then
      free[#free + 1] = key
    end
  end
  return free
end

-- Puts frames on the keys (up to one per key) and saves the bindings once.
function methods:write(frames, now)
  local free = self:freeKeys()
  self.noKeys = #free == 0
  if self.noKeys then
    return false
  end
  local batch = {}
  for i = 1, math.min(#free, #frames) do
    local f = frames[i]
    f.slot = self.slot
    local action = Link.action(f)
    if not self.api.setBinding(free[i], action) or self.api.getAction(free[i]) ~= action then
      self.noKeys = true
      return false
    end
    self.keys[free[i]] = action
    batch[#batch + 1] = f
  end
  -- Keys we held and no longer need are freed in the same save.
  for i = #batch + 1, #free do
    if self.keys[free[i]] then
      self.api.setBinding(free[i], nil)
      self.keys[free[i]] = nil
    end
  end
  self.api.save()
  self.lastWrite, self.announced = now, self.slot
  self.out = { frames = batch, last = batch[#batch].seq, at = self.out and self.out.at or now }
  return true
end

function methods:clearKeys(now)
  for key in pairs(self.keys) do
    self.api.setBinding(key, nil)
    self.keys[key] = nil
  end
  self.api.save()
  self.lastWrite = now
end

-- Loads the next inbox and takes what it holds.
function methods:poll(now)
  self.lastPoll = now
  self.inboxData = nil
  local loaded, reason = self.api.loadAddOn(Link.inbox(self.slot))
  self.noInbox = not loaded and (reason or "unknown") or nil
  if not loaded then
    return
  end
  -- Loaded, so spent, whatever it held.
  self.slot = self.slot + 1
  local env = self.inboxData and Link.envelope(self.inboxData, self.session)
  if env then
    self:apply(env, now)
  end
end

--- Called by the inbox addon (through TrailMate_Inbox) while it loads.
--- Only kept: poll() checks it once LoadAddOn returns.
function methods:receive(payload)
  self.inboxData = payload
end

function methods:apply(env, now)
  self.bridgeSeen = now
  if self.out and env.ack >= self.out.last then
    for _ = 1, #self.out.frames do
      table.remove(self.queue, 1)
    end
    self.out = nil
  end
  self.thinking, self.error = env.thinking, env.error
  for _, r in ipairs(env.replies) do
    if not self.seen[r.id] then
      self.seen[r.id] = true
      self.waiting = false
      if self.onReply then
        self.onReply(r.text)
      end
    end
  end
end

function methods:step(now)
  if self.out then
    -- Frames on the keys: wait for the bridge to acknowledge them.
    local late = now - self.out.at > Link.NO_BRIDGE
    if now - self.lastPoll >= (late and Link.POLL_SLOW or Link.POLL_ACK) then
      self:poll(now)
    end
    -- Running past the inboxes the bridge fills: same frames, new place.
    if self.out and self.slot - self.announced >= Link.REANNOUNCE and now - self.lastWrite >= Link.WRITE_GAP then
      self:write(self.out.frames, now)
    end
    return
  end
  if #self.queue > 0 then
    if now - self.lastWrite >= Link.WRITE_GAP then
      self:write(self.queue, now)
    end
    return
  end
  if next(self.keys) and now - self.lastWrite >= Link.WRITE_GAP then
    self:clearKeys(now)
  end
  if self.waiting then
    self.waitSince = self.waitSince or now
    local waited = now - self.waitSince
    if waited > Link.GIVE_UP then
      self.waiting, self.gaveUp = false, true
      return
    end
    if now - self.lastPoll >= (waited > 60 and Link.POLL_SLOW or Link.POLL_REPLY) then
      self:poll(now)
    end
    if self.waiting and self.slot - self.announced >= Link.REANNOUNCE then
      self:send("P")
    end
  end
end

--- Moves the conversation on: call it often (every frame is fine). Returns
--- the status: idle, sending, nobridge, thinking, error, noreply, combat,
--- exhausted, noinbox or nokeys.
function methods:tick(now)
  if self.api.combat() then
    self.status = "combat"
    return self.status
  end
  if self.slot > self.ring then
    self.status = "exhausted"
    return self.status
  end
  self:step(now)
  if self.noInbox then
    self.status = "noinbox"
  elseif self.noKeys then
    self.status = "nokeys"
  elseif self.out or #self.queue > 0 then
    self.status = self.out and now - self.out.at > Link.NO_BRIDGE and "nobridge" or "sending"
  elseif self.waiting then
    self.status = "thinking"
  elseif self.error then
    self.status = "error"
  elseif self.gaveUp then
    self.status = "noreply"
  else
    self.status = "idle"
  end
  return self.status
end

--- True while a question waits for its answer or frames wait to go.
function methods:busy()
  return self.waiting == true or #self.queue > 0
end
