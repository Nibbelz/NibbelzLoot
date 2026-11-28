# Nibbelz Loot

## 1.6.1 (minor)

- Options: the category "Others" is removed. Its settings (AH prices, window style, Gold per dungeon in chat) are now in "General" at the top, together with the minimap button.

## 1.6.0 (minor)

- Classic style reworked to look like the WoW Forever interface: windows in the game menu's dialog frame (dark, metal corners), the game's red buttons with gold text (white on hover), gold titles and section headers over bronze lines like the quest tracker, Blizzard check boxes and the game's slider knob.
- Classic style: the metal frame sits around the window, so title bars, buttons and search boxes no longer run into it. Rolls in the Loot Rolls window show the game's roll icon (dice, coin, cross) with the word instead of coloured boxes.
- Sliders: the coloured bar now reaches exactly to the knob (all styles).
- First start after installing: a window lets you choose between the Nibbelz style and the Classic style (with a small preview of each). Change it later in Options > Others. `/rolls style` opens it again.
- Quest loot: when the last item of a quest objective is looted, a short hint shows at the top of the screen ("The Hunt Begins: all Plainstrider Meat looted", or "quest complete!" when nothing is left). Optional sound (off by default). Both switch in Options > Loot icons.
- Quest loot: the quest item icon no longer shows for an objective that is already done (the quest log is read fresh at the kill).
- New: loot battle history. The last 30 battles with place, mode, date, players, stake and winner; click one to see its result, right-click to delete it. Open it from the loot battle window's title bar or Options > Loot battle, where "Delete battle history" deletes all of them.
- The "What's new" window shows the 1.6.0 changes once after the update.
- Options: new category "General" at the top (minimap button). The "Roll history" category is gone: its buttons (add / remove demo history, delete roll history) are in the Roll History window's title bar now, "Gold per dungeon in chat" is under "Others". The Undermine Reals button under "Loot icons" is removed (it is under "Windows").

## 1.5.1 (minor)

- Quest loot: the icon and the tooltip line only count items from quests in your own quest log. In a group, the enemy's tooltip also lists your group members' quests; those are ignored now.
- Quest item icon: the green background (and "Drag to move") only shows while you move the icon, not on every kill.

## 1.5.0 (minor)

- New: "What's new" window. After an update it opens once at login with the latest changes in short: what is new or changed and how to use it (up to the last four versions). Open it again any time with `/rolls news`. A fresh install shows nothing.
- The window has a box "Don't show the changelog any more": ticked, it no longer opens after updates (`/rolls news` still works, untick it there to get it back).
- `/rolls news` is listed in the `/rolls` help.

## 1.4.9 (minor)

Less CPU:
- Quest loot: every enemy is looked at once (until your quest log changes) instead of on every mouseover and nameplate. The death checks (health, flags, nameplates) only listen while a quest enemy is being watched, and only to your target's health instead of every unit's.
- Quest loot tooltip line: uses the tooltip's own data instead of reading the unit's tooltip a second time.
- Player loot history: the "hover" tooltip mode no longer runs code every frame on every row, only on the row under the mouse.
- Undermine Reals window: reads the saved state once per rebuild instead of twice per boss.

## 1.4.8 (minor)

- Loot icons: the quest item icon and the Undermine Real reminder look the same now: same size, a frame in the addon's accent colour (follows the window style), a gold line on top ("Loot it for your quest" / "Loot your Real!") and a white line with the item or boss.

## 1.4.7 (minor)

- Undermine Real reminder: now also for the bosses of Blackmaw Hold and Shaper's Terrace (e.g. Blackmaw Behemoth showed "drops no Real" although it gave one).
- The reminder learns: a boss that gives you a Real but is not on the list yet is remembered and reminds you from then on (for all your characters).

## 1.4.6 (minor)

- Undermine Real reminder fixed: it now works like NaowhForever's. The day's first kill of a boss that drops a Real (by encounter) shows the blinking Real until you open that boss's loot. It no longer depends on the Reals already counted for the window, and several bosses in a row are remembered.
- New: `/reals test` shows the reminder for a few seconds, `/reals debug` prints every boss kill and what the reminder did in chat.
- Options: "Quest loot" and "Undermine Reals" are now one category, "Loot icons".
- Options: the addon version is shown top right.

## 1.4.5 (minor)

- New: Undermine Real reminder. After the day's first kill of a boss that drops a Tarnished Undermine Real, a blinking Real ("Loot your Real!" with the boss name) shows on screen until you loot the boss. Right-click hides it. New options category "Undermine Reals": on/off, icon size (50-250 %), time shown (1-60 seconds or until looted) and "Move icon".

## 1.4.4 (minor)

- Undermine Reals: in a dungeon, the window opens with that dungeon unfolded (all other dungeons stay folded). Fold it by hand and it stays folded until you enter a dungeon again.

## 1.4.3 (minor)

- Options > Roll history: "Gold per dungeon in chat" is now a dropdown. Pick "All dungeons + total" (as before) or a single dungeon to post only its gold, items, runs and AH value.

## 1.4.2 (minor)

- Undermine Reals: all dungeons start folded (click one to unfold it). New search for a dungeon or boss: matching dungeons unfold, with only the matching bosses when you searched a boss.
- Options: every category can be folded with a click on its title (remembered).
- Options: new category "Windows" with Roll history, Fair share, Group stats and Undermine Reals. New order: Loot roll window, Roll history, Windows, Quest loot, Loot battle, Others.

## 1.4.1 (minor)

- Quest loot: the bag icon next to the nameplates is removed again (it could sit in the wrong place with nameplate addons). Enemies to loot for a quest are still marked in their tooltip.
- Quest loot reminder: when you kill an enemy that drops an item your quest still needs, the icon of that item (with its name) pops up on screen for a moment. Options: on/off, icon size (50-250 %), how long it is shown (1-10 seconds) and "Move icon" to drag it where you want it.

## 1.4.0 (minor)

- **Quest loot:** enemies that drop an item one of your quests still needs get a bag icon next to their nameplate and a line in their tooltip ("Loot it for your quest"). Kill objectives and finished objectives are left out. Two new switches under "Quest loot": in dungeons and outdoors.
- **Undermine Reals:** new window (button under "Quest loot", or `/reals`) showing which bosses already gave you your Tarnished Undermine Reals today. All bosses from Sunken Temple and Blackrock Depths on (Dire Maul, Lower/Upper Blackrock Spire, Scholomance, Stratholme, Blackmaw Hold, Shaper's Terrace), last bosses marked with 3, the others 1. Shows your Reals, today's total and the time until the daily reset. Per character; the dungeon you are in comes first; option to hide looted bosses; dungeons fold with a click.

## 1.3.1 (minor)

- The options window scrolls (mouse wheel) and can now also be made taller or shorter at the bottom-right corner.
- Loot battle, Fair share, Roll history and Group stats are one block of four buttons (2 x 2).
- New category "Others": AH prices and window style side by side (replaces the "Design" category).

## 1.3.0 (minor)

(Released on GitHub as 2.0.0 by mistake: no new features, so it is a minor version.)

Options window re-sorted and resizable.

- New order: Loot roll window (Window size, Window stays open, Show minimap button, Play a sound, Hide roll messages, buttons), Roll history, Loot battle (with the Fair share / Roll history / Group stats buttons and the AH prices below them), and the new category **Design** with the window style.
- "Open loot battle" is now just "Loot battle".
- "Gold per dungeon in chat" moved down, next to "Delete roll history".
- The "Display" category is gone; its settings moved as listed above.
- The options window can be made wider by dragging the bottom-right corner (double-click for the default size); the buttons grow with it.

## 1.2.4 (minor)

- Loot history window: item tooltips are off by default. A new button switches between "off", "hover" (item tooltip only) and "compare" (item tooltip plus the comparison with your equipped item). The setting is saved.
- Group stats: no more tooltip when hovering a player, everything is already in the row.
- Group stats: hint in the title bar "Right-click a player for their loot history".

## 1.2.3 (minor)

- Group stats: right-click a player to open their loot history in a small window: every item they won (or, with "All rolls", every item they rolled on) with their pick, roll, place, date and value. Follows the time range of Group stats.
- The loot history window shows about five items, the rest scrolls. It can be resized by dragging the bottom-right corner (double-click for the default size).

## 1.2.2 (minor)

- Roll history search: when you search a player, each item now shows that player's pick and roll (and whether they won it, or who got it) instead of the winner.
- Roll history > Stats: the "Only me" switch is replaced by "Only me" / "Group" for the Overview. "Only me" (default) shows your own numbers, "Group" adds up everyone's picks, items won, gold and AH value.
- Roll History, Group stats, Loot battle and Fair share can be resized by dragging the bottom-right corner, like the Loot Rolls window. The size is saved; double-click the corner for the default size.

## 1.2.1 (minor)

- Roll history only keeps dungeons. Rolls and coins outside of dungeons (e.g. Durotar) are no longer saved; they still show in the Loot Rolls window. Entries from zones saved by older versions are removed once.
- Roll history search works for players: type a name to see every item that player rolled on, with their pick, roll and wins on the right. The search looks through the whole history, item names work too.
- Roll history > Stats: new "Only me" switch to see only your own stats.
- Roll history > Rolls: removed the "Picked" filter (it showed almost the same as "All").

## 1.2.0

- AH value now also from **TradeSkillMaster** (AuctionDB market value, else min buyout), **Auctionator** (last scan) and **Auctioneer** (market value), besides NaowhForever.
- New option "AH prices": Automatic (first addon that knows a price, in the order TSM, Auctionator, Auctioneer, NaowhForever) or one fixed source. Addons that are not installed are greyed out.
- AH prices are taken when an item drops; older items without a price look it up once (again after switching the source).

## 1.1.0

- New option: how long the Loot Rolls window stays open after the last roll. From "Never opens" through 1-60 seconds to "Stays open" (replaces the two old switches, your old setting is kept).
- Money looted: coins from mobs and chests (and your share of the group's coins) are now tracked as gold, silver and copper, per run and per place.
- Roll history stats: new rows "Money looted" and "Total (money + vendor value)". Choose which stats you see with the new "Shown stats" menu.
- Options: Fair share, Roll history and Group stats buttons right below the loot battle button.

## 1.0.0

First public release.

- Loot Rolls window: live Need / Greed / Pass / still choosing for every group roll, with timer bars, class-coloured names and collapsible item cards. Resizable via the grip in the bottom-right corner; closes on its own when all rolls are done.
- Roll history by day and dungeon, with vendor value and auction house value of everything won.
- Group stats: everyone you ran with, items, gold and AH value won, sortable, grouped by guild, compare ticked players over the runs you did together.
- Fair share: who has to trade whom how much so everyone ends up with the same gold. Counts only in dungeons, early leavers only share until they leave, run history with delete.
- Loot battle: contest or tip game with gold stake, loot categories and extra bets (damage, boss damage, healing, killing blows, deaths, ...). Players without the addon join via `!join` / `!tip` in chat.
- Sound when someone rolls a 100, option to hide Blizzard's roll messages in chat.
- Six window styles (Nibbelz, EllesmereUI, Classic, Naowh, Midnight, Dark), minimap button, addon compartment entry, English and German.
