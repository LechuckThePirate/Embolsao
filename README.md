# Embolsao!!

World of Warcraft addon (Retail, TBC Anniversary, Classic Era and the Classic
"Forever" beta) that replaces the built-in bags -- and the bank -- with its
own window: a merged/virtual inventory (identical items grouped into one
stack), category filter tabs, a name search box, sortable listing, Recent and
Junk groups, and empty-slot counters to drop new stacks into. The bank opens
in the same window, side by side with the bags.

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
- `Filters.lua` defines the single built-in tab ("All") and the matching logic
  for custom tabs, which can combine whole categories/subcategories and
  per-`itemID` overrides. Tabs come in two independent sets, the bags' and the
  bank's (`Embolsao:GetFilters(domain)`).
- `UI.lua` builds one standalone, resizable window (reusing Blizzard's own
  frame templates -- `PortraitFrameFlatTemplate`, the bare `ItemButton`
  widget type, `UIPanelScrollFrameTemplate`, the Blizzard_Menu API) holding up
  to two panes side by side, bank and bags, each with its own tabs, search box
  and footer. It takes over display duty from the native bag and bank frames
  whenever the player opens them.
- `Compat.lua` papers over the API differences between clients (namespaced
  vs. global functions, the old vs. modern bank).
- `ForeverSVFallback.lua` is a temporary workaround for the Classic "Forever"
  beta not handing saved variables back to addons; delete it (and its call in
  `Core.lua`) once Blizzard fixes that.

## Installing (development)

Copy or symlink this repo's root as `Embolsao` into the client's AddOns folder:

```
World of Warcraft/_retail_/Interface/AddOns/Embolsao/
World of Warcraft/_anniversary_/Interface/AddOns/Embolsao/
World of Warcraft/_classic_era_/Interface/AddOns/Embolsao/
World of Warcraft/_classic_beta_/Interface/AddOns/Embolsao/
```

## Status

Beta (`0.6.3-beta`); see `CHANGELOG.md`. Everything is configured in game:
custom tabs, bindings and preferences.
