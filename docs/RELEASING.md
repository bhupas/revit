# Releasing nullCarbon Revit Export

## TL;DR

After your work has landed on `dev` and been merged into `master` via PR (see [CONTRIBUTING.md](../CONTRIBUTING.md)), the actual release is three commands:

```cmd
git checkout master
git pull
do\3-release.cmd
```

Or as a one-liner:

```cmd
git checkout master && git pull && do\3-release.cmd
```

The first two commands make sure your local `master` matches what's on GitHub (so the tag points at the right commit). The third launches the interactive release wizard, which:

1. Refuses to run from anything except `master`.
2. Prompts you for the new version (validates `MAJOR.MINOR.PATCH`).
3. Checks `RELEASE_NOTES.md` for a matching `## v<version>` section -- if missing, opens Notepad so you can add one.
4. Bumps the version in `src\SCaddins.csproj`.
5. Builds Release2023 + Release2024 + Release2025 + Release2026.
6. Packages the WiX MSI installer.
7. Creates a `vX.Y.Z` git tag and pushes it.
8. The tag push triggers [`.github/workflows/release.yml`](../.github/workflows/release.yml) which builds on a clean runner and publishes a GitHub Release with the installer attached AND the release notes from `RELEASE_NOTES.md`.

Before any of that, add a new section to [`RELEASE_NOTES.md`](../RELEASE_NOTES.md):

```markdown
## v26.3.4 -- 2026-04-12

### Fixed
- Whatever bug got fixed.
```

(The wizard will refuse to ship without one and offer to open Notepad if missing.)

That's it. Pushing the tag triggers [`.github/workflows/release.yml`](../.github/workflows/release.yml) which builds on a clean runner and publishes a GitHub Release with the installer attached AND the release notes from `RELEASE_NOTES.md`. Users get the update via the in-app one-click updater on their next Revit start.

## Where to write release notes

**One file: [`RELEASE_NOTES.md`](../RELEASE_NOTES.md)** at the repo root. The wizard refuses to ship a version that doesn't have a matching `## v<version>` section there.

The same text ends up in two places:

| Surface | How |
|---|---|
| **GitHub Release description** at https://github.com/bhupas/revit/releases | `release.yml` runs `scripts\extract-release-notes.ps1` to pull the matching `## v<version>` section, writes it to `release-notes-extracted.md`, and passes that as `body_path` to `softprops/action-gh-release`. |
| **In-app "Update now" dialog** | [`NullCarbonUpdater`](../src/NullCarbon/Update/NullCarbonUpdater.cs) reads `latest.body` from the GitHub API -- which is exactly what the workflow above set. The dialog truncates to 600 chars, so put the most important things first. |

The wizard:

1. Validates that `## v<new-version>` exists in `RELEASE_NOTES.md`.
2. If missing, opens Notepad on the file. You add the section, save, close. The wizard re-checks.
3. Shows a preview of the notes that will be published.
4. Only then does it tag + push.

That guarantees you can never accidentally ship a release with empty / wrong release notes.

---

## What gets published

**Exactly one artifact per release**, regardless of how many Revit versions it supports:

```
nullCarbon-LCA-Export-win64-<version>.msi
```

This single WiX v5 MSI (built from [`setup/nullcarbon/nullcarbon-installer.wxs`](../setup/nullcarbon/nullcarbon-installer.wxs)) bundles every Revit version that was built before packaging:

- Per-Revit-version content is gated by `<?if $(var.R20XX) = "Enabled" ?>` WiX preprocessor directives, both for the `<ComponentGroup>` payloads and the matching `<Feature>` entries.
- [`scripts/build-installer.ps1`](../scripts/build-installer.ps1) auto-detects which `src\bin\Release<year>\` folders exist and passes the matching `-d R<year>=Enabled` defines to `wix build`.
- The MSI is **per-user** (`<Package Scope="perUser">`) — no UAC, no admin.
- The interactive UI is `WixUI_FeatureTree` (from `WixToolset.UI.wixext`), which is **Welcome → License → Custom Setup → Verify → Progress → Finish**. The license text shown is [`setup/nullcarbon/nullcarbon-license.rtf`](../setup/nullcarbon/nullcarbon-license.rtf) (LGPL-3.0-or-later, with nullCarbon and SCaddins copyrights).
- Each Revit year (2023/2024/2025/2026) is its own MSI Feature, so users get checkboxes on the Custom Setup page. Default state: all bundled years installed.

It:

- Installs per-user under `%LocalAppData%\nullCarbon-LCA-Export\<year>\` — **no admin needed, no UAC prompt**.
- Drops a `nullCarbon-LCA-Export.addin` manifest into `%AppData%\Autodesk\Revit\Addins\<year>\` for each ticked version.
- Uses `<MajorUpgrade />` so new MSIs cleanly replace older ones. The default WiX MigrateFeatures behaviour preserves the user's feature selection across upgrades, so the silent auto-updater never re-installs Revit years they previously turned off.
- Relies on Windows Restart Manager to gracefully close Revit before replacing files when `msiexec /i ... /qn` runs.
- Runs uninstall cleanly via Add/Remove Programs.

If you build only some Revit versions (e.g. `do\1-build.cmd -Configurations Release2025`), only those end up in the MSI. If you build none, `do\2-installer.cmd` errors out before invoking `wix build`.

The installer asset filename suffix (`.msi`) is what the in-app updater (`NullCarbonUpdater`) looks for via [`Branding.PreferredAssetSuffix`](../src/NullCarbon/Branding.cs). Don't change the suffix without also updating Branding.cs.

---

## Release tag format

The updater parses the GitHub tag name as a `System.Version` after stripping a leading `v`. Use SemVer-ish numeric tags only:

| Good | Bad |
|---|---|
| `v26.3.1` | `release-2026-q1` |
| `26.3.1` | `v26.3.1-beta` |
| `26.3.1.0` | `v26.3` |

The tag must match `^v\d+\.\d+\.\d+$` for `release.yml` to accept it.

---

## Three release paths

Pick one based on what you want to control.

### A. Fully automated — push a tag, GitHub Actions does the rest

```powershell
do\3-release.cmd -Version 26.3.2 -Push
```

This bumps the csproj, builds locally as a sanity check, tags, and pushes. The tag push triggers the workflow which builds + packages on a clean runner and publishes the Release.

Use this when you trust the local build matches what CI will produce. Recommended for normal releases.

### B. Build locally, push tag manually

```powershell
do\3-release.cmd -Version 26.3.2     :: no -Push
# inspect setup\out\nullCarbon-LCA-Export-win64-26.3.2.msi
git push origin v26.3.2                  # then push to trigger CI
```

Use this when you want to test the installer locally before triggering the public release.

### C. CI-only via workflow_dispatch

GitHub → Actions → Release → Run workflow → enter version `26.3.2`. Skips the local steps entirely. Useful when you don't have a build environment handy and just want to ship a hotfix.

---

## Local build environment

You only need this for paths A and B.

| Tool | Why | Get it |
|---|---|---|
| .NET SDK 8.x (Windows Desktop) | Builds Release2025 / Release2026 + hosts WiX | https://dot.net |
| .NET Framework 4.8 dev pack | Builds Release2023 / Release2024 (both target `net48`) | https://dotnet.microsoft.com/download/dotnet-framework/net48 (scroll to "Developer Pack") |
| WiX v5 | Packages the MSI | `dotnet tool install --global wix` |

After installing WiX, `do\2-installer.cmd` (which wraps `scripts\build-installer.ps1`) finds it via:
1. `wix` on PATH
2. `%USERPROFILE%\.dotnet\tools\wix.exe` (default dotnet global tool location)
3. The `-WixExe <path>` parameter

If `wix` is missing altogether, `scripts\build-installer.ps1` will run `dotnet tool install --global wix` automatically on first use.

---

## How the in-app updater finds your release

1. On Revit startup, [`NullCarbonModule`](../src/NullCarbon/NullCarbonModule.cs) fires a background task that calls `NullCarbonUpdater.CheckForUpdates(quietIfNotNewer: true)`.
2. The updater hits `https://api.github.com/repos/bhupas/revit/releases/latest`.
3. It parses `tag_name` as a version and compares against the running assembly version.
4. If newer, it picks the first asset whose name ends with `.msi` (configurable via `Branding.PreferredAssetSuffix`).
5. It shows a Revit `TaskDialog` with **Update now** / **Later**.
6. **Update now** downloads the .msi to `%TEMP%\nullCarbon-RevitExport-Update\` and shells out to `cmd.exe /c timeout 3 && msiexec /i <path> /qn /norestart`.
7. The user is asked to close Revit. Once they do, `msiexec` (already spawned in its own process tree) runs the MSI silently, MajorUpgrade removes the old install, new files land in place.
8. User re-opens Revit on the new version.

If GitHub is unreachable, the silent path swallows the error so Revit startup is never blocked.

---

## Smoke test the updater (without cutting a real release)

1. Pick a throwaway test repo or branch and publish a fake release tagged higher than the currently-installed version, with a dummy `.msi` asset.
2. Edit [`src/NullCarbon/Branding.cs`](../src/NullCarbon/Branding.cs) `GitHubOwner`/`GitHubRepo` to point at the throwaway.
3. Build Release2025, sideload the DLL, restart Revit.
4. The startup background check should pop the upgrade dialog within a few seconds.
5. Click **Update now** — verify the download and the silent `msiexec /qn` install behavior end-to-end.
6. **Revert the Branding.cs change before committing.**

---

## Versioning policy

The version lives in [`src/SCaddins.csproj`](../src/SCaddins.csproj). `do\3-release.cmd` rewrites:

- `<AssemblyVersion>X.Y.Z.0</AssemblyVersion>`
- `<FileVersion>X.Y.Z</FileVersion>`
- `<VersionPrefix>X.Y.Z</VersionPrefix>`
- `<AssemblyInformationalVersion>X.Y.Z</AssemblyInformationalVersion>`
- `<AssemblyInformationalVersionAttribute>X.Y.Z</AssemblyInformationalVersionAttribute>`
- `<InformationalVersionAttribute>X.Y.Z.0</InformationalVersionAttribute>`

Use SemVer roughly:

- **Patch** (`26.3.1` → `26.3.2`): bug fixes, internal cleanups, no schema or API changes.
- **Minor** (`26.3.x` → `26.4.0`): new features, new exported fields, backward-compatible.
- **Major** (`26.x.x` → `27.0.0`): incompatible Revit version drop, breaking nullCarbon API change.

When upstream SCaddins bumps its version, you don't need to follow it.

---

## Pre-release checklist

- [ ] All changes merged to `main`, working tree clean.
- [ ] `git log v<previous>..HEAD` reviewed for the changelog notes.
- [ ] [`CHANGELOG.md`](../CHANGELOG.md) updated (optional but nice).
- [ ] No leaked rebrand (run the verification command in [docs/SYNCING.md](SYNCING.md#verification-commands)).
- [ ] Local smoke test on at least Revit 2025.
- [ ] `do\3-release.cmd -Version <X.Y.Z>` runs without errors.
- [ ] Inspect `setup\out\nullCarbon-LCA-Export-win64-<X.Y.Z>.msi`.
- [ ] Push the tag (or let the workflow do it).
- [ ] After CI, download the published artifact and install on a clean machine.
