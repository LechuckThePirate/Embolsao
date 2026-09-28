# Embolsao!!

World of Warcraft addon (Retail, TBC Anniversary, Classic Era and the Classic
"Forever" beta) that replaces the built-in bags -- and the bank -- with its
own window: a merged/virtual inventory (identical items grouped into one
stack), category filter tabs, a name search box, sortable listing, Recent and
Junk groups, and empty-slot counters to drop new stacks into. The bank opens
in the same window, side by side with the bags.

A small nod to [Apparcao](https://apparcao.com).

## Repo layout

The repo root is the addon (`Embolsao.toc`, `.pkgmeta`) — this is what release
tooling and CurseForge expect to package directly as `Embolsao/`. The code is
split by area under `Modules/`, in the same spirit as
[Questie](https://github.com/Questie/Questie), each file with its unit tests
right next to it (`X.lua` + `X.test.lua`):

```
Embolsao.toc            load order of everything below
Locales/                enUS (base) + translations
Modules/
  Core/                 Compat (client differences), Core (saved variables,
                        bag/bank scanning, offline bank, alts), Constants
  Filters/              tabs and their matching rules
  Gearset/              gearset equip/unequip logic, the floating gearset bar
  Layout/               sorting, grouping and row layout for the item grid
  Bindings/             modifier-click bindings and their window
  Tooltip/              bank / alt counts on item tooltips
  UI/                   the window (UI), tab editor, Preferences, About,
                        the secure bags-key toggle
  Minimap/              minimap button
icons/                  in-game textures
test/                   fake WoW API, test helpers, local test runner
setupTests.lua          loaded by every *.test.lua
```

- `images/` — source icon artwork (unprocessed).
- `.github/workflows/release.yml` — manual (`workflow_dispatch` only) release
  pipeline via [BigWigsMods/packager](https://github.com/BigWigsMods/packager),
  packaging the repo root and uploading to CurseForge. Tests are left out of
  the package (`.pkgmeta`).
- `.github/workflows/tests.yml` — runs the tests on every push and PR.

## Tests

Unit tests use [busted](https://lunarmodules.github.io/busted/)'s syntax and run
outside the game against a fake client (`test/WowApiMock.lua`): every test gets
a fresh one, then loads the addon's own files the way the game does (in `.toc`
order, sharing one namespace). From the repo root:

```
lua test/busted.lua                          # all of them, no install needed
lua test/busted.lua Modules/Core/Core.test.lua
busted -p ".test.lua" .                      # real busted (what CI runs, Lua 5.1)
```

`test/busted.lua` is a small runner for the subset of busted the tests use, so
nothing has to be compiled on Windows. A new module gets its `X.test.lua` next
to it, starting with `dofile("setupTests.lua")`.

## Localization

UI strings live in `Embolsao.L` (`Locales/`), keyed by string ID. `enUS.lua`
defines every key as the English base and always loads first; other locale
files only override the keys they translate and early-return on
`GetLocale()` mismatch. Any key without a translation for the active client
locale falls back to English automatically — no addon crash, no missing text.

Currently translated: `enUS` (base), `esES`/`esMX`. To add another locale,
copy `Locales/esES.lua`, rename it, swap the locale check and the strings,
and list the new file in `Embolsao.toc` (must load after `enUS.lua`).

## How it works

- `Modules/Core/Core.lua` scans every bag (backpack, bags, reagent bag) via `C_Container`
  and groups identical items into a virtual inventory
  (`Embolsao.VirtualInventory`), summing quantities across stacks — this can
  be turned off per-item-type in Preferences (Consolidate Stacks), which
  keys each physical stack separately instead of merging by itemID. Also
  tracks every genuinely empty slot (`Embolsao.EmptySlots`).
- `Modules/Filters/Filters.lua` defines the single built-in tab ("All") and the matching logic
  for custom tabs, which can combine whole categories/subcategories and
  per-`itemID` overrides. Tabs come in two independent sets, the bags' and the
  bank's (`Embolsao:GetFilters(domain)`).
- `Modules/UI/UI.lua` builds one standalone, resizable window (reusing Blizzard's own
  frame templates -- `PortraitFrameFlatTemplate`, the bare `ItemButton`
  widget type, `UIPanelScrollFrameTemplate`, the Blizzard_Menu API) holding up
  to two panes side by side, bank and bags, each with its own tabs, search box
  and footer. It takes over display duty from the native bag and bank frames
  whenever the player opens them.
- `Modules/Core/Compat.lua` papers over the API differences between clients (namespaced
  vs. global functions, the old vs. modern bank).

## Installing (development)

Copy or symlink this repo's root as `Embolsao` into the client's AddOns folder:

```
World of Warcraft/_retail_/Interface/AddOns/Embolsao/
World of Warcraft/_anniversary_/Interface/AddOns/Embolsao/
World of Warcraft/_classic_era_/Interface/AddOns/Embolsao/
World of Warcraft/_classic_beta_/Interface/AddOns/Embolsao/
```

## Status

Stable (`1.0.0`); see `CHANGELOG.md`. Everything is configured in game:
custom tabs, bindings and preferences.
