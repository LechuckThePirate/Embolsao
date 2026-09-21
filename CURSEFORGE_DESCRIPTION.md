# Embolsao!!

**One bag to rule them all.** Embolsao merges every bag you carry — backpack,
regular bags, and the reagent bag — into a single, clean window with
identical items stacked together, smart category tabs, and full control
over what shows up where. Visit a banker and your bank joins the same window,
side by side with your bags.

![Main window](main_window.png)

---

## Features

### A merged, searchable inventory
No more hunting across six different bags for the same reagent. Embolsao
combines every stack of the same item into one, with a live search box and
sortable listing (name, quantity, quality, or type).

### Category tabs that actually adapt to you
Start from **All** and build the tabs you actually want. Hide specific items
you never want to see, or add category/subcategory rules on top. Even "All"
can be customized, and one click resets it back to factory defaults. Sort
mode and direction are remembered per tab.

![Sort by type, with class/subclass headers](category_sort.png)

### Build your own tabs
Hit the **+** button to create a tab from scratch: pick a name and icon,
drag items straight from your bags to hide them, and stack up category
rules (down to the subcategory level) to define exactly what shows.

![Creating a custom tab](new_custom_tab_form.png)
![Editing hidden items on a tab, with Reset](hide_items.png)

Tabs can be reordered by dragging them right in the sidebar, hidden without
being deleted, and renamed or edited any time via right-click.

### Bank and bags in one window
At a banker the window doubles: bank on the left, bags on the right, each
with its own tabs, search box and footer. Right-click an item to move it
across — a merged stack moves all its real stacks. Buy more bank tabs or bag
slots right from the bank's footer, switch to the Warband Bank on Retail and
Forever, and close just the bank part with its own X. The bank can keep its
own set of tabs, separate from the bags'.

### Offline Bank
Every visit to a banker saves what your bank holds. Away from one, the
**Offline Bank** button next to the bags' search box opens that saved copy in
the bank part of the window — tabs, search and sorting included, strictly
read only, with the date it was saved. The Warband bank is remembered too.
Turn it off in Preferences if you'd rather not keep it.

### Per-tab sorting and grouping
Each tab has its own sort mode and direction, its own grouping by category
and subcategory (groups first, A to Z, with the sort ordering what's inside
each), and its own choice of showing the Recent and Junk groups — set from
the tab's editor or the Sort By menu. A line under the search box always
says how the tab is sorted.

### Recent, Junk and empty slots
- **Recent** pins what you just picked up at the top until you dismiss it.
- **Junk** gathers your grey items (and anything you mark as junk) with a
  one-click sell button at vendors, and an optional auto-sell.
- **Empty Slots** is always its own category, with one counter per kind of
  special bag, labelled by profession.

### Bindings and the item menu
Choose which modifier does what when clicking an item: show a merged
stack's real stacks, split it, or open an **item actions menu** (split, link
in chat, hide on this tab, mark as junk, sell…). Tooltips show the shortcuts
that apply to each item, and the items a held key can't act on fade out.

### Quality-of-life details
- **Drag an item onto a tab** to hide it there instantly, with a
  confirmation prompt — or onto a tab's icon button to use its icon.
- Window position and size are remembered across reloads.
- **Fades while you walk**, like the world map — with a slider for how much —
  so it never hides what's ahead; hover it to bring it back.
- Gold and XP (with rested XP) in the window's footer.
- Fully in-game preferences panel — no config files to hand-edit.

![Preferences panel](preferences.png)

### Minimap button
Left-click to open Embolsao, right-click for a quick menu: open,
preferences, a one-off peek at Blizzard's native bags, and a full
disable toggle. Optional — turn it off in Preferences if you'd rather use
the keybind.

![Minimap button](minimap_button.png)

---

## Supported game versions

- Retail
- TBC Classic (Anniversary)
- Classic Era
- Classic "Forever" (beta)

One codebase, same feature set, everywhere. The Forever beta client
currently fails to hand saved settings back to addons on load, which affects
every addon, not just this one; Embolsao works around it as best it can.

## Localization

English and Spanish out of the box. Missing a translation for your locale?
Open an issue or a PR on GitHub.

## Feedback & Issues

Found a bug or have an idea? [Open an issue on GitHub](https://github.com/LechuckThePirate/Embolsao/issues).
