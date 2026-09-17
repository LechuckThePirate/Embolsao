# Changelog

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
