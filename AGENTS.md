# Embolsao!! — agent guide

World of Warcraft addon that replaces the built-in bags and bank with one window: merged/virtual inventory, category and custom
tabs, search, gearsets, alt-character counts in tooltips. Runs on Retail, TBC Anniversary, Classic Era and the Classic "Forever"
beta (`## Interface: 120100, 20506, 11509, 16001`). Public repo `LechuckThePirate/Embolsao` (branch `master`), CurseForge project
id 1698765. Siblings with the same conventions: `Completao` and `Aggreao` (under `D:\Source\WowAddons\`).

## How to work with the maintainer

- **Chat in Spanish from Spain** ("tú", never Argentine voseo: not "tenés", "contame", "fijate", "dale"). **Everything committed
  is in English**: code comments, test names, docs, workflow comments, commit messages. Spanish only in `Locales/esES.lua`.
- Windows machine. Prefer the PowerShell tool over Bash. Multi-line commit messages: write a file and use `git commit -F <file>`.
- Work happens in git worktrees (`.claude/worktrees/<name>`, branch `claude/<name>`). **After every change (tests green) commit and
  push** (`git push origin HEAD`). **Merging to `master` and releasing only happen when the maintainer asks.**
- Keep the maintainer informed in one or two short lines during long tasks.

## Layout

The repo root is the addon (`Embolsao.toc`, `.pkgmeta`), packaged as `Embolsao/`. Code is split by area under `Modules/`, each file
with its unit tests next to it (`X.lua` + `X.test.lua`):

- `Locales/` — `enUS.lua` (base, loads first) + `esES.lua`; other locales only override keys and early-return on `GetLocale()`
  mismatch; missing keys fall back to English. UI strings live in `Embolsao.L`.
- `Modules/Core` (Compat = client differences, Core = saved variables / scanning / offline bank / alts, Constants), `Filters`,
  `Gearset`, `Layout`, `Bindings`, `Tooltip`, `UI` (window, tab editor, Preferences, About, secure bags-key toggle), `Minimap`.
- `test/` (fake WoW API `WowApiMock.lua`, `TestUtils.lua`, local runner `busted.lua`), `setupTests.lua`, `icons/` (in-game textures),
  `images/` (artwork + `screencaps/` for the CurseForge page), `media/` (config of the media host, see Infra).

## Commands (PowerShell, repo root)

```powershell
lua test/busted.lua                                   # all tests, no busted install needed (Lua 5.1+)
lua test/busted.lua Modules/Core/Core.test.lua        # one file
busted -p ".test.lua" .                               # real busted (what CI runs, Lua 5.1)
```

There is no deploy script: the addon is installed as a folder `Embolsao` in
`D:\Games\World of Warcraft\{_retail_,_anniversary_,_classic_era_,_classic_beta_}\Interface\AddOns\` (the maintainer usually gets
released versions through CurseForge; for development copy the repo root there without `test/`, `images/`, `media/`, `*.test.lua`,
`setupTests.lua`), then `/reload`.

## Code conventions

- Lua 5.1. Every file starts with `local ADDON_NAME, Embolsao = ...` (shared namespace) and hangs its API on `Embolsao`; no new
  globals.
- A new module gets its `X.test.lua` next to it, starting with `dofile("setupTests.lua")`; tests load the addon's files in `.toc`
  order through `TestUtils.loadAddon(...)` and set saved variables through `_G.X` (busted's addon code sees globals only that way).
- Client differences (namespaced vs global APIs, old vs modern bank, Warband bank) go through `Modules/Core/Compat.lua`.
- Tooltip and action-bar hooks must never touch action bar buttons or read "secret values": that tainted the bars once (1.0.5).
- Comments explain *why*, are short, and match the surrounding density. Match surrounding naming and idiom.
- User-visible changes go in `CHANGELOG.md` (newest first, one section per version, `New:` / `Fixed:` bullets, plain sentences).

## Infra and release

- **CI:** `.github/workflows/tests.yml` runs busted on Lua 5.1 on every push/PR except doc-only or artwork-only changes (Lua and
  busted are cached, superseded runs are cancelled).
- **Release** (only when asked): one commit `release: X.Y.Z -- short summary` that bumps `## Version` in `Embolsao.toc`, adds the
  section to `CHANGELOG.md` and updates `LATEST_CHANGELOG_TEXT` in `Modules/UI/About.lua`; then `git tag vX.Y.Z`, push `master` and
  the tag, and `gh workflow run release.yml --repo LechuckThePirate/Embolsao --ref vX.Y.Z` (workflow_dispatch only; BigWigsMods/packager
  uploads to CurseForge with repo secret `CF_API_KEY` and creates the GitHub release). Watch with `gh run watch`.
- **Repo hardening:** actions are pinned by commit SHA (Dependabot updates them weekly; the repo requires SHA pinning), a ruleset
  makes `master` PR-only (the owner can bypass), and `CF_API_KEY` belongs to the `release` environment, which only `master` and
  `v*` tags can use. Repository deploy keys count as admins for ruleset bypass, so never add a write deploy key.
- **Screenshots:** `images/screencaps/*.png` are shrunk (1000 px wide, pngquant) and rsynced by `.github/workflows/sync-media.yml`
  (push to master touching that path, or `gh workflow run sync-media.yml`) to
  `https://media.joanvilarino.online/embolsao/images/screencaps/`, which `CURSEFORGE_DESCRIPTION.md` references. Secret
  `EMBOLSAO_MEDIA_SSH_KEY` (restricted rsync-only user on the maintainer's VPS).
- **Media host** (`media/`): a Caddy container serving `/srv/embolsao-media` read-only, reverse-proxied by the Apparcao Caddy over the
  shared Docker network; `docker compose up -d` from `/opt/embolsao-media` on the VPS. Completao and Aggreao reuse the same host in their own subfolders.
- `.pkgmeta` keeps `images`, `media`, tests and `CURSEFORGE_DESCRIPTION.md` out of the package.
