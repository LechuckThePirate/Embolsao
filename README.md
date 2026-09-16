# Embolsao!!

World of Warcraft (Retail) addon that improves the single-bag system: category
filter tabs (All, Weapons, Gear, Consumables, Trade Goods, Quest Items, Misc)
plus custom tabs defined by `itemID` and/or category/subcategory.

A small nod to [Apparcao](https://apparcao.com).

## Repo layout

- `src/` — addon code (`Embolsao.toc`, `Core.lua`, `Filters.lua`, `UI.lua`, `icons/`).
  This is the folder that gets packaged as `Embolsao/` when installing or publishing.
- `images/` — source icon artwork (unprocessed).

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
