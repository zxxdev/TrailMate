local helper = require("spec.helper")

describe("Link (the chat with the companion)", function()
  local Link

  before_each(function()
    Link = helper.load().Link
  end)

  it("encodes like Go: CRC-32 (IEEE) and base32 without padding", function()
    assert.equals(0xCBF43926, Link.crc32("123456789"))
    assert.equals(0, Link.crc32(""))
    assert.equals("MZXW6YTBOI", Link.base32("foobar"))
    assert.equals("foobar", Link.unbase32("MZXW6YTBOI"))
    assert.is_nil(Link.unbase32("MZXW6YTBO1")) -- not base32
    assert.is_nil(Link.unbase32("MZXW6YTBOJ")) -- leftover bits
    local bytes = "\0\1\2\250\255 ñ"
    assert.equals(bytes, Link.unbase32(Link.base32(bytes)))
  end)

  it("puts a frame on a key binding action and reads it back, nothing else", function()
    local f = { session = "1A2B3C4D", seq = 7, slot = 12, msg = 3, part = 2, count = 4, payload = "¿qué hago ahora?" }
    local action = Link.action(f)
    assert.matches("^CLICK TrailMateCarrier_1A2B3C4D_000007_000C_000003_02_04_[A-Z2-7]+_%x+:LeftButton$", action)
    assert.is_true(#action < 160)
    assert.same(f, Link.parse(action))
    -- One changed letter, or someone else's binding, is not a frame.
    assert.is_nil(Link.parse(action:gsub("_02_04_", "_02_05_")))
    assert.is_nil(Link.parse("CLICK WitchcraftCarrier_V1_x:LeftButton"))
    assert.is_nil(Link.parse("ACTIONBUTTON1"))
  end)

  it("matches the frames the bridge's tests read (bridge/internal/link/testdata)", function()
    local vectors = dofile("tools/link_vectors.lua")
    local file = assert(io.open("bridge/internal/link/testdata/vectors.txt", "rb"))
    local saved = file:read("*a")
    file:close()
    assert.equals(vectors.text(Link), saved)
  end)

  it("reads the inbox file the bridge writes (bridge/internal/inbox/testdata/example.lua)", function()
    local got
    rawset(_G, "TrailMate_Inbox", function(p) got = p end)
    finally(function()
      rawset(_G, "TrailMate_Inbox", nil)
    end)
    dofile("bridge/internal/inbox/testdata/example.lua")
    local env = Link.envelope(got, "1A2B3C4D")
    assert.same({ ack = 7, thinking = true, replies = {
      { id = 1, text = "Haz primero las misiones de Grom'gol: \"Hunt for Yenniku\" y los collares." },
      { id = 2, text = "Línea 1\nLínea 2" },
    } }, env)
  end)

  it("checks what an inbox holds before using it", function()
    local ok = Link.envelope({ protocol = 1, session = "1A2B3C4D", ack = 3, thinking = true,
      replies = { { id = 1, text = "Ve a Grom'gol." } } }, "1A2B3C4D")
    assert.same({ ack = 3, thinking = true, replies = { { id = 1, text = "Ve a Grom'gol." } } }, ok)
    assert.is_nil(Link.envelope({ protocol = 1, session = "FFFFFFFF", ack = 0 }, "1A2B3C4D"))
    assert.is_nil(Link.envelope({ protocol = 2, session = "1A2B3C4D", ack = 0 }, "1A2B3C4D"))
    assert.is_nil(Link.envelope({ protocol = 1, session = "1A2B3C4D", ack = 0, replies = { { id = 1 } } },
      "1A2B3C4D"))
    assert.is_nil(Link.envelope(setmetatable({}, {}), "1A2B3C4D"))
  end)

  -- The game's key bindings and a bridge that reads them when they are
  -- saved and answers through the inbox addons.
  local function world()
    local w = { live = {}, file = {}, combat = false, inboxes = {}, loads = 0, saves = 0 }
    w.live["CTRL-ALT-SHIFT-F6"] = "TOGGLEWORLDMAP" -- the player's own: never touched
    w.api = {
      getAction = function(key) return w.live[key] or "" end,
      setBinding = function(key, action) w.live[key] = action; return true end,
      save = function()
        w.saves = w.saves + 1
        for k, v in pairs(w.live) do
          w.file[k] = v
        end
        for k in pairs(w.file) do
          w.file[k] = w.live[k]
        end
        if w.bridge then
          w.bridge()
        end
        return true
      end,
      combat = function() return w.combat end,
      loadAddOn = function(name)
        if w.missing then
          return false, "MISSING"
        end
        w.loads = w.loads + 1
        local data = w.inboxes[name]
        if data then
          w.link:receive(data)
        end
        return true
      end,
    }
    return w
  end

  local function fakeBridge(w, answer)
    local got, ack, text, replies = {}, 0, {}, {}
    w.bridge = function()
      local slot
      for _, action in pairs(w.file) do
        local f = Link.parse(action)
        if f and not got[f.seq] then
          got[f.seq] = f
          slot = f.slot
        end
      end
      while got[ack + 1] do
        ack = ack + 1
        local f = got[ack]
        text[f.msg] = (text[f.msg] or "") .. f.payload
        if f.part == f.count and text[f.msg]:sub(1, 1) == "M" then
          replies[#replies + 1] = { id = #replies + 1, text = answer(text[f.msg]:sub(2)) }
        end
      end
      if slot then
        for s = slot, slot + Link.WINDOW - 1 do
          w.inboxes[Link.inbox(s)] = { protocol = 1, session = "1A2B3C4D", ack = ack, replies = replies }
        end
      end
    end
  end

  it("sends a question in frames, gets the answer and frees its keys", function()
    local w = world()
    local answers = {}
    w.link = Link.new(w.api, { session = "1A2B3C4D", onReply = function(t) answers[#answers + 1] = t end })
    fakeBridge(w, function(q) return "Sobre «" .. q .. "»: haz las misiones de Grom'gol." end)
    local question = ("¿Qué hago ahora en la Vega de Tuercespina? "):rep(4) -- 7 frames
    assert.is_true(w.link:send("M", question))
    local now = 0
    for _ = 1, 40 do
      now = now + 0.5
      w.link:tick(now)
    end
    assert.same({ "Sobre «" .. question .. "»: haz las misiones de Grom'gol." }, answers)
    assert.equals("idle", w.link.status)
    -- Three keys carried the frames, four at most at once; none is left.
    for _, key in ipairs({ "CTRL-ALT-SHIFT-F5", "CTRL-ALT-SHIFT-F7", "CTRL-ALT-SHIFT-F8" }) do
      assert.equals("", w.api.getAction(key))
    end
    assert.equals("TOGGLEWORLDMAP", w.live["CTRL-ALT-SHIFT-F6"])
    assert.is_true(w.loads < 20)
  end)

  it("says when the bridge is not running, and waits in combat", function()
    local w = world()
    w.link = Link.new(w.api, { session = "1A2B3C4D" })
    w.link:send("M", "hola")
    assert.equals("sending", w.link:tick(1))
    assert.equals("nobridge", w.link:tick(30)) -- nobody acknowledges
    w.combat = true
    local saves = w.saves
    assert.equals("combat", w.link:tick(31))
    assert.equals(saves, w.saves) -- no binding changes in combat
  end)

  it("says when the inbox addons are missing or used up", function()
    local w = world()
    w.missing = true
    w.link = Link.new(w.api, { session = "1A2B3C4D" })
    w.link:send("M", "hola")
    w.link:tick(1)
    assert.equals("noinbox", w.link:tick(3))
    local small = world()
    small.link = Link.new(small.api, { session = "1A2B3C4D", ring = 2 })
    small.link:send("M", "hola")
    for t = 1, 6 do
      small.link:tick(t)
    end
    assert.equals("exhausted", small.link.status)
  end)

  it("never sends a message longer than its frames allow", function()
    local w = world()
    local link = Link.new(w.api, { session = "1A2B3C4D" })
    assert.same({ false, "too long" }, { link:send("M", ("x"):rep(Link.MAX_PAYLOAD * Link.MAX_PARTS)) })
  end)

  it("clears frames a previous session left behind", function()
    local w = world()
    w.live["CTRL-ALT-SHIFT-F5"] = Link.action({ session = "00000001", seq = 1, slot = 1, msg = 1, part = 1,
      count = 1, payload = "Mhola" })
    local link = Link.new(w.api, { session = "1A2B3C4D" })
    assert.is_true(link:scrub())
    assert.equals("", w.api.getAction("CTRL-ALT-SHIFT-F5"))
    assert.equals("TOGGLEWORLDMAP", w.live["CTRL-ALT-SHIFT-F6"])
  end)
end)
