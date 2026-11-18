# ADR 0001: the companion chat goes through a bridge program on the PC

- Status: accepted
- Date: 2026-11-18

## Context

The player wants to talk to an AI companion (Claude, later others) from inside World of Warcraft: Forever, about their own character: what to do next, which quests are worth it, talents, dungeons.

An addon cannot open files, sockets or programs. It can only write SavedVariables, and the game writes those only on logout or `/reload`. Reading pixels from the screen would work, but that is how bots read the game, so it is out.

[Witchcraft](https://github.com/Geraldlol/witchcraft) (MIT, for Forever 16001) found two channels that need no reload. TrailMate takes the idea and writes its own code:

- **Game → PC:** the addon puts a message frame on an unused key combination (`SetBinding`) and calls `SaveBindings`. The game writes `bindings-cache.wtf` at once, and a program on the PC reads it.
- **PC → game:** the program writes into small load-on-demand addons, and the addon loads the next one with `LoadAddOn`. Each one loads once per session.

## Decision

1. **A bridge program, `trailmate-bridge`, written in Go.** It builds into one `.exe` with nothing to install: Node is not on the player's PC, and Go's standard library has everything needed. It has no third-party dependencies.
2. **Frames.** Each frame carries 32 bytes on one of eight reserved keys (`CTRL-ALT-SHIFT-F1` to `F8`; Witchcraft uses F9 to F12). It is base32 text with a CRC-32 checksum, a session id, a sequence number, the message number and part, and the inbox the addon will load next. A key the player uses is never touched. Nothing is written in combat. The keys are cleared when the conversation is idle.
3. **Inboxes.** `trailmate-bridge init` makes 1000 addons, `TrailMate_Inbox_0001` to `_1000`. The bridge writes the same envelope (acknowledgement, "thinking", error, last four answers) into the 64 inboxes from the one the addon announced, so the addon finds it even if it moved on. The addon announces again before it runs past them. It polls only while it waits: every second for an acknowledgement, every two seconds for an answer, slower after a minute. After 1000 loads, a `/reload` starts again.
4. **Data, not code.** An inbox is one call, `TrailMate_Inbox({ ... })`, with a table of strings and numbers. The addon checks it (`Link.envelope`) before using it. Whoever can write into `Interface\AddOns` can already change any addon, so this adds no new opening.
5. **The companion has no tools** (project decision D-44). The first companion is the player's own Claude Code, in print mode: `claude -p --tools "" --strict-mcp-config --safe-mode --system-prompt … --output-format json`. It runs in an empty folder of its own and keeps one conversation (`--session-id`, then `--resume`). It only answers in text. A second companion, `echo`, checks the link without a model.
6. **Context.** With the first question, and whenever it changes, the addon sends the character's state as short lines: class, level, race, faction, XP, gold, zone, bags, current plan and next steps, quest log, next talent, dungeons for the level. It sends no names.
7. **One encoder, two languages, one test file.** `tools/link_vectors.lua` writes frames with the addon's encoder into `bridge/internal/link/testdata/vectors.txt`. The Go tests must read them exactly. The Go tests write `bridge/internal/inbox/testdata/example.lua`, and the addon's tests load it.

## Consequences

- **Speed.** A question takes a few seconds: eight frames, 256 bytes, per round trip of about one to two seconds. The context goes once.
- **Setup.** The player runs `init` once and restarts the game, then keeps `trailmate-bridge run` open while playing.
- **Found in the game (2026-11-18).** With `synchronizeBindings` at 1 (the default), `SaveBindings` does not write `bindings-cache.wtf`: the bindings go to Blizzard's servers. Set to 0, the file is written and the bridge reads it. The chat says so and never changes the setting on its own: the player types `/tm chat local`, and `/tm chat sync` undoes it. Whether `LoadAddOn` reads an inbox changed after the game started is still to be confirmed in the game.
- **Size.** Eight keys (`Ctrl+Alt+Shift+F1` to `F8`) carry 256 bytes per save, and the context is cut to 480 bytes, so a question goes out in one or two saves.
- **Not done yet.** Other companions (ChatGPT through its own CLI), and the companion proposing plans as validated data, are left for later.
