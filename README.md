# Embolsao!!

World of Warcraft (Retail) addon that replaces the built-in single-bag view
with its own window: a merged/virtual inventory (identical items grouped into
one stack), category filter tabs, a name search box, sortable listing, and a
dedicated empty-slot button to drop new stacks into.

A small nod to [Apparcao](https://apparcao.com).

## Repo layout

The addon files live at the repo root (`Embolsao.toc`, `Core.lua`, `Filters.lua`,
`UI.lua`, `Locales/`, `icons/`, `.pkgmeta`) — this is what release tooling and
CurseForge expect to package directly as `Embolsao/`.

- `images/` — source icon artwork (unprocessed).
- `.github/workflows/release.yml` — manual (`workflow_dispatch` only) release
  pipeline via [BigWigsMods/packager](https://github.com/BigWigsMods/packager),
  packaging the repo root and uploading to CurseForge.

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

- `Core.lua` scans every bag (backpack, bags, reagent bag) via `C_Container`
  and groups identical items into a virtual inventory
  (`Embolsao.VirtualInventory`), summing quantities across stacks — this can
  be turned off per-item-type in Preferences (Consolidate Stacks), which
  keys each physical stack separately instead of merging by itemID. Also
  tracks every genuinely empty slot (`Embolsao.EmptySlots`).
- `Filters.lua` defines the built-in tabs (by `Enum.ItemClass`) and the
  matching logic for custom tabs (`EmbolsaoDB.customTabs`), which can combine
  whole categories/subcategories, per-`itemID` overrides, and optionally the
  shared ignored-item list (`useIgnoredList`).
- `UI.lua` builds a standalone, resizable, scrollable window (reusing
  Blizzard's own frame templates — `PortraitFrameFlatTemplate`, the bare
  `ItemButton` widget type, `UIPanelScrollFrameTemplate`, the Blizzard_Menu
  API) that takes over display duty from the native bag frames (hidden
  whenever ours shows) whenever the player opens their bags.

## Installing (development)

Copy or symlink this repo's root as `Embolsao` into:

```
World of Warcraft/_retail_/Interface/AddOns/Embolsao/
```

## Status

Beta (`0.1.0-beta`). No in-game editor yet for creating custom tabs (for now,
define them by hand in `EmbolsaoDB.customTabs`).
