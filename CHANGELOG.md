# Changelog

Each version has its release on GitHub with the addon (`TrailMate-<version>.zip`, to copy into `World of Warcraft/_forever_/Interface/AddOns/`) and the companion bridge for Windows (`trailmate-bridge.exe`, optional).

## 0.5.2-beta

- **Objects in the preview:** a quest about a chest or another object (Reclaimed Treasures in Uldaman: the Garrett Family Chest) now has its magnifier too, inside the dungeon and on the step. The preview shows its 3D model like a creature's, with *Search* and the object's name; when there is none, the icon of the item you take from it.
- **Objects that give or take quests:** when a quest starts or is handed in at an object (a wanted board, a chest), its step shows that object's 3D model too. Dungeon quests show who gives them and who takes them back, like the guides.
- **A magnifier for the quest you mark:** when you click a quest in the tracker or the quest log and the arrow follows it, the window shows its magnifier too: the creature or object of its objectives, and who takes it back once it is done, when TrailMate's lists know the quest.
- Marking again the quest the game followed before a reload works: TrailMate took it as its own while the guide's quest was not in your log yet, and ignored the click.
- **The flight map's mark can be seen now:** the gold beat melted into the parchment. The point to fly to gets a gold halo that breathes around it and TrailMate's purple pin floating just above it, the same mark as on the world map. The chat says which point it is.
- The purple pin on the minimap stays on its spot while you walk: since 0.5.0 it moved only five times a second and jumped.

## 0.5.1-beta

- **Objectives inside a dungeon:** the window used to say only "Do here: <quest>". Now it lists what is left of each quest of the dungeon in your log: its objectives as the game words them, with the count in a column of its own and a green check for the ones done, under a heading per quest when you carry several. A magnifier next to each creature to kill shows it in the preview; click it to keep that one shown. The counter says how many objectives are done. A finished quest stays, marked done, and when all are finished the window says to hand them in outside. Inside a dungeon the counts are read again every two seconds, so the last kill is never missed. Who each dungeon quest is about comes from the Questie database for Forever.
- **A far step, the quickest way:** when the next step is far away and flying (or a zeppelin, a ship or your hearthstone) is quicker than walking, the arrow takes you to the flight master first and says the flight ("Fly from Orgrimmar to Shadowprey Village."), with the flights you know, and lands in the step's own zone when you know a flight point there. The map's mark stays on the step itself. On the flight map, that point beats in gold, and its tooltip says "TrailMate: fly here".
- The dotted route no longer follows a walked trail that stops far from the target: in Orgrimmar, with the next step in Desolace, it led into the Valley of Spirits, a dead end.

## 0.5.0-beta

- **Step preview:** a magnifier next to the current step. Hover it (or the step) and the game's 3D model of who the step is about appears next to the window, with what to do: *Talk to* the quest giver, *Turn in to*, *Kill*, *Dropped by* the creature that drops the item, or *Search* for objects (a chest, a plant), which show only their name. Click the magnifier to keep the preview shown; the same choice is in Esc > Options > AddOns and `/tm preview on|off` (`/tm vista`). It hides in combat. From the Questie database for Forever, like the guides.
- **Lighter:** the arrow still turns with your camera twenty times a second, but works out where you and the target are only five times a second, and does nothing while you do not turn; the walked-trail route is no longer worked out again while you stand in one spot. `/tm perf` (`/tm rendimiento`) measures for a minute what each part costs and writes it to the Log tab.
- Fixed the icon: the shadow of the two middle toes had a light crescent in it (the light of the toe next to it). Each part of the paw now casts its own shadow, the same way in all of them.

## 0.4.0-beta

- **Class quests as side quests:** at each new level (and when you log in) TrailMate says which quests of your class and race you can pick up now: totems, pets, forms, stances, mounts and the rest, levels 1 to 59. `/tm class` (`/tm clase`) lists them with who gives them and where, and the next level that opens more; `/tm class 1` takes you to the quest giver and back to your guide when it is handed in. When several trainers give the same quest, it is the nearest one, even if it opens a level or two later (a troll shaman gets Call of Earth in the Valley of Trials, not on Zephras Isle). From the Questie database for Forever, checked against Wowhead's.
- The step window starts at the top left of the screen, under the target frame, on characters that never moved it.
- The self-test (Log tab) checks the class quests: what you would be offered now and level by level, and what the game says you handed in.

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
