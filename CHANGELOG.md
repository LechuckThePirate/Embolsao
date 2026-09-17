# Changelog

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
