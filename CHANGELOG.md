# Changelog

Each version has its release on GitHub with the addon (`TrailMate-<version>.zip`, to copy into `World of Warcraft/_forever_/Interface/AddOns/`) and the companion bridge for Windows (`trailmate-bridge.exe`, optional).

## Unreleased

- **Class quests as side quests:** at each new level (and when you log in) TrailMate says which quests of your class and race you can pick up now: totems, pets, forms, stances, mounts and the rest, levels 1 to 59. `/tm class` (`/tm clase`) lists them with who gives them and where, and what opens at your next level; `/tm class 1` takes you to the quest giver and back to your guide when it is handed in. From the Questie database for Forever, checked against Wowhead's.

## 0.3.0-alpha

- **Every language of the game's client:** besides English and Spanish, German, French, Italian, Portuguese (Brazil), Russian, Korean and Chinese (simplified and traditional). These were translated with AI: corrections are welcome (see CONTRIBUTING.md). A few texts with place or talent names stay in English, and so do the commands.
- Each version is also published on CurseForge.

## 0.2.2-alpha

- In a dungeon, the arrow and the step window step aside: the guide's next step is outside. When the quest log has quests of that dungeon, the window lists them instead ("Do here: ..."). Leaving brings the guide back.

## 0.2.1-alpha

- Fixed: the talent plan showed with the spellbook too. In this client they are one window with tabs; the plan now shows with the talents tab only.
- The options page (Esc > Options > AddOns) says where a thanks in the game can go.

## 0.2.0-alpha

Fixes and additions from playing the first alpha in Stranglethorn Vale.

- **Follow a quest of your own**: click a quest in the tracker or the quest log and the arrow goes to it, then to its turn-in. "Back to the guide" in the step window returns to the guide; handing the quest in or dropping it does too.
- **Guides by zone**: "Automatic" and choosing a zone pick the guide with the biggest part where you are, for your level. The guide being followed stays when you cross into the next zone.
- **No external links**: the guides' notes by their authors (thanks, links, donations) are left out.
- **A clearer step window**: "Guide:" or "Route:" in the title, how many steps are done, and an Undo button.
- **Trips survive a /reload**: the way to another zone (hearthstone, flights) is saved with the character.
- **The arrow can be brought back** to the top or the middle of the screen (`/tm arrow top|center`, or the buttons in the panel and the options page). The item button (hearthstone, quest items) sits centred under the arrow's text.
- **A new icon**: a badge with a gold ring, a paw print and a trail in your AI companion's colour. On the minimap it sits on the edge inside the game's gold ring, like other addons' buttons.
- **Options page** in Esc > Options > AddOns (`/tm options`); `/tm minimap` shows or hides the minimap button.
- Fixed: a quest you never had could be asked for ("Do: ..."); the minimap button sat inside the minimap; text in the step window ran into each other.

## 0.1.0-alpha

The first alpha for WoW Forever (interface 16001). It needs no other addon.

- **Guides**: 78 quest guides (order from the TUGs guides for Guidelime, places from the Questie database for Forever). Quests the character can no longer pick up are left out.
- **Arrow and map**: TrailMate's own arrow, a pin on the minimap and the world map, and a dotted path that follows ways walked before.
- **Talents**: templates with a picture of the three trees and level labels on the game's talent window.
- **Advice**: class trainer, vendor, reminders (full bags, level up, talent points), travel planner and dungeons by level.
- **Companion chat** (optional): `/tm chat` with `trailmate-bridge` on your PC.
