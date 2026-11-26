# Nibbelz Loot

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
