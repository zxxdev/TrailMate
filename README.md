# TrailMate

A leveling coach for **World of Warcraft: Forever** (game version 1.60, interface 16001). It turns your quest log into steps with an arrow, tells you what to learn at the class trainer and what to sell, keep or auction at a vendor, and explains why.

**It advises, it never plays.** TrailMate does not press keys, move your character, buy, sell or train anything. It reads the game and shows text and an arrow; every action is yours.

> Status: early development. Screenshots arrive with version 0.1.0. Not affiliated with Blizzard Entertainment.

## What it does today

| Feature | How |
|---|---|
| Steps from your quest log | `/tm questlog` orders your quests by distance and builds "do" and "turn in" steps. Steps tick themselves off from game events. |
| Arrow | Points at the current quest. Uses [TomTom](https://www.curseforge.com/wow/addons/tomtom) when it is installed, and the game's own map pin otherwise. |
| Trainer advice | When you open a class trainer: *learn*, *skip* or *later* for each spell, with the reason. Keeps a gold reserve you choose. Hunters can skip tracking spells. |
| Vendor advice | When you open a vendor: what to sell (and roughly for how much), what to keep, and what is worth the auction house. Warns when your bags are almost full. |
| Character summary | `/tm status`: class, level, XP, gold, position, quests and bag space. No names are stored. |

## Install

1. Copy the `TrailMate` folder into `World of Warcraft/_forever_/Interface/AddOns/`.
2. Restart the game or type `/reload`.
3. Type `/tm` to see the commands. English and Spanish commands both work (`/tm questlog` or `/tm diario`).

## Commands

| Command | What it does |
|---|---|
| `/tm questlog` · `/tm diario` | Build a plan from your quest log |
| `/tm skip` · `/tm salta` | Skip the current step |
| `/tm done` · `/tm hecho` | Mark the current step as done |
| `/tm undo` · `/tm deshaz` | Undo the last mark |
| `/tm trainer` · `/tm instructor` | Advice at the open trainer |
| `/tm vendor` · `/tm vender` | What to sell, keep or auction |
| `/tm status` · `/tm estado` | Character summary |
| `/tm tracking on\|off` · `/tm rastreos si\|no` | Learn or skip hunter tracking spells |
| `/tm reserve <gold>` · `/tm reserva <oro>` | Gold the trainer advice never spends |
| `/tm show` / `/tm hide` | Show or hide the window |
| `/tm clear` · `/tm borrar` | Remove the plan |
| `/tm diag` | What this client exposes, for bug reports (no personal data) |

## How it works

```mermaid
flowchart LR
  E[Game events] --> A[Adapter: game/]
  A -->|facts| C[Core: core/]
  C -->|current step, advice| A
  A --> U[Window, arrow, chat]
```

- `TrailMate/core/` is plain Lua 5.1 with no game API: the plan format and its validator, the step engine, the quest-log planner and the trainer and bag advisors. It is fully tested outside the game.
- `TrailMate/game/` is a thin adapter: it reads the game, turns events into facts and draws the window. Every game function is feature-detected, because this client is new.
- A plan is **pure data** and is validated every time it is loaded. Later versions receive plans written by an external program, so a plan can never carry code.

## Development

Requires Lua 5.1 and LuaRocks.

```bash
luarocks install --local busted 2.3.0-1
luarocks install --local luacheck 1.2.0-1
luacheck .
busted
```

## Roadmap

- 0.1.0: installable release, screenshots.
- Bridge program and Claude: a plan for the next hours prepared from your character's state, delivered to the game as validated data.
- Measured accuracy and cost of the advice.

## Limitations

- Arrival at a place is approximate: zones have different sizes and the radius is in map units.
- Trainer rules are generic plus hunter tracking; class-specific advice grows over time.
- The vendor advice uses item level as a rough guide for gear, not stats.

## Related work

[Azeroth Companion](https://github.com/nardo86/azeroth-companion) (MIT) pioneered the addon-plus-desktop-app pattern for in-game AI chat. TrailMate is a coach rather than a chat, and works without any AI.

## License

[MIT](LICENSE).
