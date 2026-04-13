# nullCarbon Revit Export

[![Build](https://github.com/bhupas/revit/actions/workflows/build.yml/badge.svg)](https://github.com/bhupas/revit/actions/workflows/build.yml)
[![Latest release](https://img.shields.io/github/v/release/bhupas/revit?include_prereleases)](https://github.com/bhupas/revit/releases/latest)
[![License: LGPL-3.0](https://img.shields.io/badge/License-LGPL--3.0-blue.svg)](COPYING.LESSER)

A Revit add-in that exports schedules straight to the **nullCarbon** LCA platform. Adds a single ribbon button to Revit; all other features hidden.

Built on top of [acnicholas/scaddins](https://github.com/acnicholas/scaddins) (LGPL-3.0). See [NOTICE](NOTICE).

---

## For users — install

1. Download `nullCarbon-LCA-Export-win64-<version>.msi` from the [latest release](https://github.com/bhupas/revit/releases/latest).
2. Double-click it. **No admin rights needed** — installs per-user under `%LocalAppData%\Studio.SC\nullCarbon-LCA-Export\`, no UAC prompt.
3. Read and accept the **License Agreement** (LGPL-3.0-or-later).
4. On the **Custom Setup** page, tick the Revit versions you want to install for (any combination of 2023 / 2024 / 2025 / 2026). Defaults to all bundled versions.
5. Start Revit. Look for the **nullCarbon** ribbon panel with the **nullCarbon Export** button.

**One MSI covers every Revit version.** Same `.msi`, no separate per-Revit downloads, same file works for upgrades.

### Updates

You don't need to do anything. The add-in checks GitHub on every Revit start. If a newer version is found, you get a one-click **Update now** dialog. Click it → close Revit → `msiexec` runs silently in the background → re-open Revit on the new version. The silent updater preserves the Revit-version selection you made on first install (MSI `MajorUpgrade` migrates feature state across versions), so it never re-installs Revit years you previously turned off.

---

## For maintainers — the four files to double-click

Open the **`do\`** folder. There are exactly four files there, numbered. That's the entire interface — just double-click in Explorer.

| # | File | What it does |
|---|---|---|
| **1** | [`do\1-build.cmd`](do/1-build.cmd) | Builds the add-in for Revit 2023 + 2024 + 2025 + 2026. Output → `src\bin\Release<year>\` |
| **2** | [`do\2-installer.cmd`](do/2-installer.cmd) | Packages the WiX MSI installer. Run **after** `1-build.cmd`. Output → `setup\out\nullCarbon-LCA-Export-win64-<version>.msi` |
| **3** | [`do\3-release.cmd`](do/3-release.cmd) | Bumps the version, builds, packages, tags, and (with `-Push`) publishes a GitHub Release. **The only command you need for shipping.** |
| **4** | [`do\4-sync.cmd`](do/4-sync.cmd) | Pulls new commits from upstream SCaddins into a sync branch. Tells you about conflicts if any. |

See [`do\README.md`](do/README.md) for examples and the first-time install commands.

> The repo root also has `build.bat`, `build.ps1`, `build_installer.bat`, `build_tests.bat`, `run_tests.bat` — those are **upstream's old Cake-based pipeline**. **Ignore them.** They're left untouched so upstream syncs stay clean. **Always use the four files in `do\` instead.**

### First time on this machine? Install these once

```cmd
winget install --id Microsoft.DotNet.SDK.8 --silent --accept-package-agreements --accept-source-agreements
winget install --id Microsoft.DotNet.Framework.DeveloperPack_4 --silent --accept-package-agreements --accept-source-agreements
dotnet tool install --global wix
```

After installing, **close any open terminal/Explorer window** and re-open one so PATH picks them up. Then double-click `do\1-build.cmd`.

---

## Where is the version number?

**There is exactly one place to change the version: [`src\SCaddins.csproj`](src/SCaddins.csproj).**

But you don't edit it by hand. Run:

```cmd
do\3-release.cmd -Version 26.3.2
```

That rewrites the version in the csproj, builds, packages, and (optionally) tags + pushes. Everything downstream picks up the change automatically:

| Where the version shows up | How it gets there |
|---|---|
| Login window footer ("Build v26.3.2") | [`LoginViewModel.VersionLabel`](src/NullCarbon/Login/LoginViewModel.cs) → `Branding.VersionShort` → assembly |
| Export window header (small subscript next to logo) | [`ExportSchedulesViewModel.VersionLabel`](src/NullCarbon/ExportSchedules/ViewModels/ExportSchedulesViewModel.cs) → `Branding.VersionShort` → assembly |
| Ribbon button long-description / tooltip | [`NullCarbonModule.LoadExportButtonData`](src/NullCarbon/NullCarbonModule.cs) → `Branding.ProductWithVersion` → assembly |
| Installer filename (`nullCarbon-LCA-Export-win64-26.3.2.msi`) | [`scripts\build-installer.ps1`](scripts/build-installer.ps1) reads it from the built DLL |
| Installer Add/Remove Programs entry | WiX is passed `Version` by `build-installer.ps1` (`-d Version=<version>`) |
| GitHub release tag (`v26.3.2`) | `do\3-release.cmd -Version` creates the tag |
| Updater "Available: 26.3.2" dialog | [`NullCarbonUpdater`](src/NullCarbon/Update/NullCarbonUpdater.cs) parses the GitHub tag |

The single source of truth is **`<AssemblyVersion>` in [`src/SCaddins.csproj`](src/SCaddins.csproj)**. All UI surfaces read from the assembly at runtime via [`Branding.VersionShort`](src/NullCarbon/Branding.cs). You should never have to touch the version in more than one place.

---

## Sync from upstream SCaddins

This fork is structured so `git merge upstream/master` only ever touches a tiny set of files. The export code, the rebrand, and the updater are all isolated under `src/NullCarbon/` and never collide. See [docs/SYNCING.md](docs/SYNCING.md) for the full architecture.

The short version:

```bash
# One-time setup per fresh clone
git remote add upstream https://github.com/acnicholas/scaddins.git
git config merge.ours.driver true
```

Then either let it happen automatically (the [weekly sync workflow](.github/workflows/sync-upstream.yml) opens a PR every Monday) or double-click `do\4-sync.cmd` locally when you want to.

---

## Repository layout

```
do/                            <- the four files you double-click
  1-build.cmd
  2-installer.cmd
  3-release.cmd
  4-sync.cmd
  README.md                       what each does + first-time install

src/
  NullCarbon/                 nullCarbon-only code (export, login, API, updater, branding)
    Branding.cs                 single source of truth for product strings + version
    NullCarbonModule.cs         ribbon hook called from SCaddins.cs
    Update/NullCarbonUpdater.cs one-click updater
    Api/                        nullCarbon API client + DTOs
    Login/                      login window
    Models/                     shared export-domain types
    ExportSchedules/            the rewritten ExportSchedules implementation
  Assets/
    nullcarbon-logo.svg         source logo
    Ribbon/nullcarbon-rvt*.png  ribbon icons
  SCaddins.cs                 upstream entry point + 2 #if NULLCARBON islands
  SCaddins.csproj             upstream csproj + 1 nullCarbon edit block + version
  SCaddins.addin              rebranded; merge=ours
  Constants.cs                rebranded URLs; merge=ours
  LatestRelease.cs            untouched (GitHub Releases JSON model)

setup/
  nullcarbon/                 nullCarbon WiX v5 MSI installer
    nullcarbon-installer.wxs
    nullcarbon-license.rtf      EULA shown by the installer (LGPL-3.0)
    nullcarbon.ico

scripts/                      PowerShell scripts that the do/*.cmd files wrap
  build.ps1
  build-installer.ps1
  release.ps1
  sync.ps1

.github/workflows/
  build.yml                   CI: build all 3 Revit configs on push/PR
  release.yml                 build + package + publish on tag push
  sync-upstream.yml           weekly upstream sync PR

docs/
  SYNCING.md                  upstream sync runbook
  RELEASING.md                release procedure
```

---

## License

LGPL-3.0-or-later. Based on [SCaddins](https://github.com/acnicholas/scaddins) by Andrew Nicholas. See [NOTICE](NOTICE), [COPYING](COPYING), and [COPYING.LESSER](COPYING.LESSER).
