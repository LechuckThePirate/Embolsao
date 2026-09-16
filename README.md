# Embolsao!!

World of Warcraft (Retail) addon that improves the single-bag system: category
filter tabs (All, Weapons, Gear, Consumables, Trade Goods, Quest Items, Misc)
plus custom tabs defined by `itemID` and/or category/subcategory.

A small nod to [Apparcao](https://apparcao.com).

## Repo layout

- `src/` — addon code (`Embolsao.toc`, `Core.lua`, `Filters.lua`, `UI.lua`, `Locales/`, `icons/`).
  This is the folder that gets packaged as `Embolsao/` when installing or publishing.
- `images/` — source icon artwork (unprocessed).

## Localization

UI strings live in `Embolsao.L` (`src/Locales/`), keyed by string ID. `enUS.lua`
defines every key as the English base and always loads first; other locale
files only override the keys they translate and early-return on
`GetLocale()` mismatch. Any key without a translation for the active client
locale falls back to English automatically — no addon crash, no missing text.

Currently translated: `enUS` (base), `esES`/`esMX`. To add another locale,
copy `src/Locales/esES.lua`, rename it, swap the locale check and the
strings, and list the new file in `Embolsao.toc` (must load after `enUS.lua`).

## How it works

- `Core.lua` scans every bag via `C_Container` and groups identical items into
  a virtual inventory (`Embolsao.VirtualInventory`), summing quantities across stacks.
- `Filters.lua` defines the built-in tabs (by `Enum.ItemClass`) and the matching
  logic for custom tabs (`EmbolsaoDB.customTabs`), which can combine whole
  categories/subcategories, per-`itemID` overrides, and optionally the shared
  ignored-item list (`useIgnoredList`).
- `UI.lua` creates a basic frame hooked to both `ContainerFrameCombinedBags`
  (single-bag mode) and `ContainerFrame1` (legacy bags mode), anchoring to
  whichever is currently visible, and shows the virtual inventory filtered by
  the active tab.

## Installing (development)

Copy or symlink the `src/` folder as `Embolsao` into:

```
World of Warcraft/_retail_/Interface/AddOns/Embolsao/
```

## Status

Base structure / work in progress. No in-game editor yet for creating custom
tabs (for now, define them by hand in `EmbolsaoDB.customTabs`).
