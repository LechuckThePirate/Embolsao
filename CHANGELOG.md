# Changelog

## 1.0.0

- Embolsao!! leaves beta: this is the first stable release, with no feature
  changes since 0.9.1-beta. The welcome window no longer calls it a beta.

## 0.9.1-beta

- Item tooltips anywhere (crafting ingredients, chat links, vendors...) now
  say how many of that item are in your bank and in the Warband bank, from
  the Offline Bank's saved copy -- and list your other characters that
  have it too ("Pepito: 5 in bags, 10 in bank"). Each character saves its
  counts as it plays, so one shows up once it has been in the game with
  this version; its bank part needs a visit to a banker. Needs "Offline
  Bank" on in Preferences.
- Fixed (Classic "Forever" beta): a character whose name has two words
  (like "Elsa Cacorchos") could lose its own saved settings and get a fresh
  copy of the shared ones on every login.

## 0.9.0-beta

- New tab type: **Gearset**. The "+" button now asks whether the new tab is
  a Filter (as before) or a Gearset -- a fixed list of items you equip as a
  set (fishing, a profession, a second spec...). Drag the items in; a set
  holds at most what you can wear at once (two rings, two trinkets, two
  hands' worth of weapons/shield). Equip or unequip it from the button above
  its item list or from the tab's right-click menu -- the button only shows
  when there is something to do.
- Equipping a Gearset remembers what it replaced, slot by slot (a rogue's two
  daggers go back to the right hands), and shows it in a dismissible
  "Previously Equipped" group. Items of the set you're wearing show as
  "Equipped" (green check) and ones you don't have with you as "Unavailable"
  (dimmed, red mark). The tab of the set you're wearing gets a green outline.
- Optional "Unequip everything else" on a Gearset: takes off everything
  outside the set as well. It checks first that your bags can hold it all
  and, if not, does nothing and tells you -- no half-done result.
- At a banker, a Gearset tab gets "Move to Bank" (stashes the set's items)
  and "Get from Bank" (fetches the ones you're missing).
- New floating Gearset bar: one button per Gearset, draggable anywhere.
  Click to equip, click again to take it off; click another set while one
  is worn and that one comes off first. Turn it on/off with "Show Gearset
  Bar" in Preferences (its own X turns that off too).
- Optional "Hide from bags" on a Gearset: its items then show only on
  Gearset tabs, never on regular tabs, whatever their filters say.
- Fixed: the tooltip of an item in your bags didn't show its enchant, gems
  or random suffix (the character sheet did); it now does.
- Fixed: a character using "Character Specific Customization" for the
  first time could suddenly see no custom tabs or category rules (the shared
  data was never lost, it just wasn't copied over). New characters are no
  longer affected; a character already hit can bring its tabs back with
  Preferences > "Reset to Shared".
- Fixed: closing the tab editor undid every change made in that session.
- Fixed: at a mailbox, right-clicking a super-stack only attached its first
  stack; it now attaches all of them, as many as the mail has room for.
- The tab column is a little wider.

## 0.8.0-beta

- New "Forced Items" on custom tabs (and built-in overrides), alongside
  Hidden Items: items you drag in always show on that tab regardless of its
  category rules or advanced filters. Drop onto the small zone or straight
  onto the list itself -- both work now, for Hidden Items too. An item can't
  be in both lists at once: adding it to one removes it from the other.
- Editing an existing tab now applies every change live to the bags/bank
  window as you make it (checkboxes, sort, category rules, advanced
  filters, hidden/forced items) -- no more clicking Update to see it.
  Creating a new tab is unchanged, still requires Create. The button that
  used to say Update now reads Close while editing.
- Fixed: Hidden Items weren't being respected inside the pinned Recent,
  Junk and Quest Items groups -- an item you'd hidden could still show up
  there.
- Fixed: the Advanced Filters section read visibly indented compared to
  Categories above it; the tab editor window now also actually shrinks and
  grows as you collapse/expand Advanced Filters instead of leaving blank
  space.
- Fixed: Manage Tabs' delete button (Preferences) was present but
  effectively unclickable.
- "Categories" renamed to "Categories Filter" in the tab editor.

## 0.7.0-beta

- New "Advanced Filters" on custom tabs (and the "All" tab's own override),
  alongside the existing category/subcategory rules: quality, item level and
  stats (e.g. "quality Rare or better", "Intellect > 0"), all combined
  together -- an item has to pass every one you add. Set them from the tab
  editor's new "Advanced Filters" section.
- Every item now shows its quality as a colored icon border, including Poor
  and Common (previously only Uncommon and up were bordered, matching
  Blizzard's own bags).
- Quest-starter items now show the same yellow "!" native bags do, and items
  tied to an in-progress quest get a border -- neither ever showed before.
- Junk items now show a small coin badge on their icon.
- New pinned "Quest Items" group (next to Recent and Junk), for quest
  starters and in-progress quest items -- off by default for new tabs, and
  wherever a tab hasn't chosen; toggle it from the Sort By menu or the tab's
  own editor, same as Recent/Junk.
- Internal: SecureToggle moved out of UI.lua into its own file, the next
  step of splitting that file up. No change in behavior.

## 0.6.5-beta

- Fixed an error on Retail that fired every frame while the bags were open
  (0.6.4): the "Fade window while moving" check compared the character's
  speed, which Retail 12 now hides from addons at times ("secret" values).
  When the speed is hidden the window simply stays opaque.
- Internal: the About / welcome window, Preferences and the click bindings
  moved out of UI.lua into About.lua, Prefs.lua and Bindings.lua, the next
  steps of splitting that file up. No change in behavior.

## 0.6.4-beta

- New "Fade window while moving" (on by default): like the world map, the
  window turns mostly transparent while your character walks, so it doesn't
  hide what is ahead, and comes back when you stop -- or whenever the cursor
  is over it, so it stays usable on the move. It eases in and out, and a
  slider in Preferences ("Opacity while moving", 10% to 90%, 30% by default)
  sets how transparent it gets. It only changes transparency, which the game
  allows even in combat.

## 0.6.3-beta

- Fixed an error on the Classic "Forever" beta when opening the bags with the
  bags key (introduced in 0.6.2). That client cannot run secure snippets yet
  (Blizzard's own restricted-execution code finds its `loadstring` missing),
  so the secure bags key added in 0.6.2 is now switched off there and the key
  is Blizzard's again. Everywhere else it is only taken over after a dry run
  shows the game accepts it, and a failing dry run no longer raises an error.
  On Forever, then, closing the window with the key in combat is not
  possible (the window says so and closes when combat ends), and with "Close
  bags in combat" on, opening the bags in combat shows Blizzard's own bags --
  which no addon can hide in combat -- and Embolsao takes over again when
  combat ends. Closing at the start of combat works as before.
- The menu's "Sort By" is now "Sort and Group" (it holds the grouping too),
  and "Show Recent" / "Show Junk" joined it at the top level of the bags
  menu, acting on the active tab like the rest. Their Preferences checkboxes
  are gone: each tab's editor has them, and tabs that haven't chosen keep
  whatever the global setting was.
- Shorter labels for the new Preferences ("Close bags in combat", "Offline
  Bank") and two Spanish ones that were cut off.
- Internal: the sorting, grouping and row-layout code moved out of UI.lua into
  Layout.lua (with Constants.lua for the sizes both share), the first step of
  splitting that file up. No change in behavior.

## 0.6.2-beta

- The bags key now works in combat: it closes the window whenever it is up,
  and opens it too unless "Close bags in combat" is on (then opening is
  blocked while in combat). Blizzard only lets its own secure code show or
  hide a window that holds the item buttons' secure click areas, so the key
  (TOGGLEBACKPACK / OPENALLBAGS) is bound to a secure button that does it;
  out of combat everything else -- scan, layout, refresh -- runs as usual and
  in combat it catches up when combat ends. The window's own X and Escape
  already worked in combat. The minimap and Blizzard's bag button still can't
  close the window in combat and say so. The key is only taken over once the
  window has item buttons, and is given back if Embolsao is disabled from the
  minimap menu.
- With bank and bags side by side, the pane's name and the "Sorted by ..."
  line now share one heading row ("Bank (offline)   Sorted by Name
  (Ascending)") instead of overlapping; alone, the sort line stays under the
  search box.
- Closing the window with its X or Escape in combat no longer shows a
  "can't be closed" message for a window that has in fact closed.
- Fixed a load error on some builds ("function has more than 60 upvalues")
  from the window code growing past Lua 5.1's limit; the helpers involved now
  hang off the UI table.
- The chat report of a blocked action is down to one short line (the full
  stack is still kept in the saved variables for bug reports).

## 0.6.1-beta

- New Offline Bank: every visit to a banker saves what the bank holds, and
  away from one an "Offline Bank" button next to the bags' search box opens
  the bank part on that saved copy -- tabs, search, sorting and empty-slot
  counters all work, but it is strictly read only (nothing can be picked up,
  moved or used) and the footer says when the copy was saved. The personal
  bank is kept per character, the Warband bank for the whole account. Can be
  switched off in Preferences, which also drops what was saved.
- Retail: a "Deposit Reagents" button (and "Deposit Warbound" while viewing
  the Warband bank) next to the bags' search box at a banker, doing what the
  button on Blizzard's own bank panel does. The bank's Bank / Warband Bank
  buttons now sit right beside its search box too, so both panes read the
  same.
- Sorting and grouping are now per tab, from the tab's own editor as well as
  the Sort By menu: sort mode and direction, group by category, group by
  subcategory, and whether the tab shows the Recent and Junk groups. The
  "Group By" checkboxes left Preferences; the values you had there are the
  starting point for tabs that haven't chosen. Grouping now leads: groups
  are ordered A to Z and the sort orders the items inside each group (group
  by category + sort by name = alphabetical categories, alphabetical items).
  Sorting by category also orders items by name within each category. The
  grouping options are always in the Sort By menu, and a line under the
  search box says how the active tab is sorted.
- Preferences: "Close bags in combat (reopen afterwards)", off by default,
  and "Offline Bank".
- Footer: XP and rested XP in thousands ("5.23k", trailing zeros dropped) and
  the addon's memory use, which gives way to the XP text on a narrow window.
- Scrollbars only take room while their list actually overflows, and the
  item grid uses the space they leave.
- Clicking an empty-slot counter opens that bag with either mouse button
  (left click still drops the item you're carrying into it).
- Fixed right-click on an item at the mailbox equipping it instead of
  attaching it; it now behaves like Blizzard's own bag slots (attach, sell or
  use depending on where you are).
- Fixed left-clicking an item while a spell waits for its target (Disenchant,
  Prospecting...) picking it up instead of casting on it, and the pointer
  turning into the sell bag over items at a vendor.
- Fixed the Classic bank with the bags already open swallowing the bags part,
  and closing the bank part or the window not ending the conversation with
  the banker. The bank footer no longer repeats your money.
- Fixed the "blocked from an action only available to the Blizzard UI"
  message on Forever's first bank visit: replacing the game's bag toggle
  functions made Blizzard's own bank opening (which buys a character's free
  first bank tab) count as addon code. Retail and Forever now leave those
  functions alone and recognise the bags key from the bags opening.
- Combat: Blizzard forbids moving, resizing, showing or hiding a window that
  holds the item buttons' secure click areas, so in combat the window says
  it can't be moved or closed instead of failing with error messages, its
  layout and contents catch up when combat ends, and opening the bags in
  combat leaves Blizzard's own bags up until combat is over.

## 0.6.0-beta

- Added support for the Classic "Forever" beta. That client is still rough:
  it currently fails to hand saved settings back to addons on load (Questie,
  Auctionator and others lose theirs too), so Embolsao keeps its settings
  across /reload there with a temporary workaround, and the welcome window
  says so in plain words. After fully quitting the game they may still reset
  -- a Blizzard bug, expected to go away as the beta settles.
- The bank now opens inside the same window as your bags: one frame with the
  bank on the left and the bags on the right, each with its own tabs, search
  box and footer, split by a separator and named above their items. The
  window doubles in width while you're at a banker and returns to normal
  after; resizing or moving it moves both. An X on the bank part closes just
  that part. Works on Retail, Forever, TBC and Classic Era, including the
  Warband Bank (Retail/Forever) with its own toggle.
- The bank has its own set of tabs, independent from the bags' -- tick or
  untick "Separate tabs for Bank and Bags" in Preferences to share them
  again. Tabs, order, hidden items and the selected tab are all kept apart.
- Right-click at a banker now moves every stack of a merged super-stack, not
  just the first, and tells the modern bank which bank (personal or Warband)
  you mean.
- Buy more bank space from the bank footer: the next bank tab (Retail/Forever,
  personal or Warband) or bank bag slot (TBC/Classic Era), with its price,
  through Blizzard's own confirmation dialog. Your money is shown next to it.
- New "Recent" group pinned at the top of every tab, filled with items you
  just picked up, that stays until you dismiss it -- per item with the small
  X on it, or all at once from the X on its header. It no longer empties
  itself when the bags close, and works whatever the active tab filters.
- New "Junk" group below it with your grey items and a coin button on its
  header that sells them all at a vendor, one by one, with a chat message of
  what was sold. Mark any other item as junk yourself from the item menu, and
  optionally turn on "Auto-sell Junk at Vendors" in Preferences (off by
  default). Both groups can be switched off in Preferences.
- "Empty Slots" is now always a category of its own at the bottom, in every
  sorting mode. Special bags of the same kind (two Mining Bags, say) share
  one counter, labelled by profession -- Mining, Herbalism, Enchanting,
  Engineering, Leatherworking, Jewelcrafting, Inscription, Quiver, Ammo and
  Soul Bag.
- Without category grouping, the items that are left form a group named after
  the tab, under Recent and Junk.
- Sort mode and direction are remembered per tab.
- New Bindings window (main menu) to choose which modifier key does what when
  clicking an item: show a super-stack's real stacks (Ctrl), split a stack
  (Shift) and a new item actions menu (Alt): show stacks, split, link in
  chat, hide on the current tab, mark or unmark as junk, remove from Recent
  and sell. Item tooltips list the bound actions that apply to that item and
  light up the one you're holding, and while you hold a modifier the items it
  can't act on fade out.
- Fixed right-clicking an item to use it: hearthstones, scrolls and quest
  items were being blocked with an "action only available to the Blizzard UI"
  message when used from Embolsao's window.
- Fixed right-click on an empty-slot counter not opening the bag with
  Blizzard's combined bags.
- Only "All" ships as a default tab now; make the rest as custom tabs. The
  category pickers in the tab editor are sorted alphabetically with the
  obsolete categories hidden, the hidden-items list is a grid, and you can
  drop an item onto the tab's icon button to use its icon.
- Fixed hiding an item on a built-in tab only taking effect after a reload.
- Pawn users get the green upgrade arrows on items again.
- The footer shows rested XP next to your XP.
- Preferences is now scrollable and resizable, for smaller screens.
- The welcome window can show a short notice for the current version, and
  can be reopened from About with the new "What's New" button.
- Fixed several errors on the Forever beta caused by APIs that moved into
  namespaces there.

## 0.5.0-beta

- Category headers (Sort By Category) can now be collapsed/expanded
  individually by clicking them, plus Collapse All / Expand All in the main
  menu. Collapse state can be remembered per tab or shared across every tab,
  via a new "Synchronize Category Visibility" preference (on by default).
- Renamed "Sort By: Type" to "Sort By: Category" to match how it actually
  groups items.
- Right-click empty space on the tab bar to quickly re-show any hidden tabs
  from a small menu.
- Tab/filter customization (custom tabs, hidden items, category rules, tab
  order) is now shared across every character by default, exactly like
  Blizzard's own Account Keybindings, with a new "Character Specific
  Customization" preference to make one character keep its own independent
  copy instead.
- Empty bag slots are now grouped into a dedicated "Empty Slots" category
  that always sorts last: one shared counter for ordinary bags, plus a
  separate counter (with that bag's own icon, shown desaturated) for each
  special bag currently equipped -- the reagent bag, and the keyring on
  Classic Era/TBC. Right-click a counter to open just that bag (or all your
  ordinary bags) without closing Embolsao.
- The keyring's actual contents (Classic Era/TBC) are now scanned into the
  merged inventory too, not just counted.
- Added a money and XP footer, pinned to the bottom of the window (not part
  of the scroll area), showing your current gold and, below max level, your
  XP with percentage.
- Bank bags can now be opened at the same time as Embolsao's own window --
  previously the addon's bag takeover silently broke them entirely.
- Fixed a crash opening bags on retail caused by a namespaced API
  (GameRulesUtil.IsPlayerAtEffectiveMaxLevel), and stale leftover keyring
  globals on retail reporting a bogus 100+ "empty slots" bag and getting
  confused with the reagent bag.
- Fixed a bagID collision on Classic Era/TBC where the first bank bag slot
  was mistaken for the (nonexistent there) reagent bag.
- Fixed the bag keybind (B) occasionally getting stuck opening Blizzard's
  native bags instead of Embolsao's after peeking at a single special bag.
- Added a one-time "still in beta" notice on login, with a feedback email
  and a changelog box, and a "don't show this again" option that resets on
  every new version.

## 0.4.1-beta

- "Group By Subclass" (Sort By Type) now defaults to off; class headers
  alone are enough for most tabs, and subclass nesting is still one click
  away in Preferences.

## 0.4.0-beta

- Built-in tabs (All, Weapons, Gear, etc.) can now be customized just like
  custom tabs: hide specific items or add category rules to them. A Reset
  button restores a built-in tab to its factory defaults.
- Drag an item straight onto any tab to hide it there, with a confirmation
  prompt.
- Ctrl+Click a merged stack to open a small popout showing the real stacks
  behind it, each fully interactive (drag, use, split) like a mini-bag.
- Added a minimap button: left-click opens Embolsao, right-click gives Open,
  Preferences, Open Default Bags (Blizzard's native window, one-off), and a
  Disable Embolsao toggle. Can be turned off in Preferences.
- The bag keybind (B) now closes Embolsao's window on a second press,
  instead of appearing to do nothing.
- Fixed Shift+Click stack splitting being completely broken on Classic Era
  and TBC Classic (Anniversary) -- Classic never picked up the modern
  StackSplitFrame API retail uses.
- Fixed the addon's icon not showing in the AddOns list.

## 0.3.0-beta

- Added support for TBC Classic (Anniversary) and Classic Era.
- The main window now uses the right portrait frame style for each client
  automatically — no user-facing change on retail.

## 0.2.0-beta

- Full custom tab management: create, edit, delete, hide/show, and
  drag-to-reorder tabs, with a visual drop indicator while dragging.
- Custom tabs can target specific item categories/subcategories (including
  an explicit "All Categories" rule) or specific hidden items, dragged
  straight from your bags.
- The category rule editor now blocks duplicate rules and keeps the rule
  list sorted from broadest to narrowest coverage.
- "Sort By" now supports grouping by type, with class/subclass separator
  headers (toggle each independently in Preferences), sorted alphabetically.
- The "All" tab is now pinned first, can't be hidden, and no longer opens
  an empty right-click menu.
- Window position and size are now both remembered across a UI reload.

## 0.1.0-beta

- Initial release: merges every bag (including the reagent bag) into a
  single virtual inventory window styled after Blizzard's own bag UI.
- Category filter tabs (All, Weapons, Gear, Consumables, Trade Goods,
  Quest Items, Misc).
- Sort by name, quantity, quality, or type; ascending/descending.
- Resizable, scrollable window with a search box and a Preferences panel.
- English and Spanish localization.
