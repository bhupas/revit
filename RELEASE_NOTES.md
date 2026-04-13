# Release notes

This file is the single source of truth for what shows up in:

- The **GitHub Release description** at https://github.com/bhupas/revit/releases
- The **in-app "Update now" dialog** that pops up when a new version is detected (the dialog reads the GitHub release body)

## How to write a new entry

Before running `do\3-release.cmd`, add a section at the top of this file with the version you're about to ship. The wizard refuses to release a version that doesn't have an entry here. The release workflow extracts the section between `## vX.Y.Z` and the next `## v...` heading and ships it as the release body.

Format (replace `X.Y.Z` with the real version, e.g. `26.3.3`):

```markdown
## vX.Y.Z -- YYYY-MM-DD

### Added
- New "Export to PDF" option in the export dialog.

### Fixed
- Schedule export no longer crashes when a column has a null formula.

### Changed
- Login window now remembers the last successful username.
```

Section headings (`### Added`, `### Fixed`, `### Changed`, `### Removed`, `### Security`) follow the [Keep a Changelog](https://keepachangelog.com/) convention. They are optional -- you can also write free-form prose under the version heading.

Keep entries **short and user-facing**. The in-app updater dialog truncates to 600 characters, so put the most important things first.

> The example above uses `vX.Y.Z` rather than a real version number on purpose. The extractor script (`scripts/extract-release-notes.ps1`) is also code-fence-aware so it ignores any `## v...` headings inside code blocks, but using a placeholder is belt-and-braces.

---

## v26.4.2 -- 2026-04-13

### Fixed
- **Update check no longer crashes with "Could not load file or assembly 'System.Text.Json, Version=9.0.0.0'".** The updater's .NET 8 branch deserialized the GitHub Releases JSON via `System.Text.Json.JsonSerializer`, but Revit pre-loads a different `System.Text.Json` into the AppDomain and the fusion loader refused to bind the 9.0.0 assembly we shipped. Switched both framework branches to `Newtonsoft.Json` (already shipped and working), eliminating the dependency entirely.
- **"Failed to load buildings: Unexpected character encountered while parsing value: {"** when fetching teams. `Building.Team` was declared as `string`, but the backend has switched the field to a nested object. The property is unused locally, so it's simply dropped and Newtonsoft now ignores the JSON field (its default behavior for unknown keys).

## v26.4.1 -- 2026-04-13

### Fixed
- **Login window now actually opens.** v26.4.0 shipped the title-bar and window-settings fix but still crashed on construction because the "Check for updates" `<Hyperlink>` inside `LoginView` had a `cal:Message.Attach` — Caliburn.Micro's `ActionMessage` can only attach to `FrameworkElement`, and `Hyperlink` is a `FrameworkContentElement`. Replaced with a plain WPF `Click` handler in the code-behind that forwards to the viewmodel through `DataContext`.
- **Installer banner text is readable.** The License Agreement, Custom Setup, Verify, and Progress dialogs were drawing their WiX-native title ("End-User License Agreement", etc.) on top of the wordmark in our banner bitmap. Regenerated the banner with the logo pinned to the far right and the left ~370 px kept pure white so WiX's own text has a clean canvas.
- **nullCarbon logo reliably shows in every addon title bar.** v26.4.0's central icon loader used a `pack://application:,,,` URI which is unreliable in Revit's hosted WPF context (no `Application.Current`). Switched to `GetManifestResourceStream` with the logo explicitly registered as an `EmbeddedResource` with a pinned `LogicalName` — same mechanism the ribbon icons already use.

## v26.4.0 -- 2026-04-13

### Changed
- **BREAKING: install path simplified.** The per-user install now lives at `%LocalAppData%\nullCarbon-LCA-Export\<year>\` — the old `Studio.SC\` parent folder is gone. `MajorUpgrade` sweeps the old tree automatically on upgrade; no user action needed.
- **Revit ribbon tab renamed.** The tab that hosts the **nullCarbon Export** button is now called **nullCarbon** (was `Studio.SC`). Any saved ribbon customisation referencing the old tab will reset on first launch.
- **Installer UI branded.** The MSI's Welcome, Finish, and progress dialogs now show the nullCarbon logo (custom banner + dialog bitmaps) instead of the stock WixUI blue gradient.

### Added
- **Logo in every dialog's title bar.** Every WPF window the plugin shows (login, export, options) now displays the nullCarbon logo in its title bar icon slot.
- **winget distribution.** `winget install nullCarbon.RevitExport` installs the plugin on any Windows machine once the inaugural `microsoft/winget-pkgs` PR is merged.

### Fixed
- **Login window now opens.** Clicking **Login** in the export panel previously did nothing — any XAML / view-locator exception was swallowed by Caliburn's async action-message handler. The dialog now opens correctly, and any remaining failure surfaces as a visible error TaskDialog instead of a silent no-op.

## v26.3.4 -- 2026-04-13

### Changed
- **Installer is now a per-user MSI** (`nullCarbon-LCA-Export-win64-<version>.msi`) instead of the old Inno Setup `.exe`. Same per-user install location (`%LocalAppData%\Studio.SC\nullCarbon-LCA-Export\`), no admin required, no UAC prompt.

### Added
- **License Agreement page**: the installer now shows a real LGPL-3.0 EULA (with nullCarbon and SCaddins copyrights) before any files are written. Read it, accept it, then proceed.
- **Revit version picker**: the new "Custom Setup" page lets you tick which Revit versions (2023 / 2024 / 2025 / 2026) to install for. The auto-updater preserves your selection across updates -- silent upgrades will never re-install a Revit year you previously turned off.

### Fixed
- The in-app updater now downloads the `.msi` and runs it via `msiexec /qn /norestart` after a 3-second delay, giving Revit time to close cleanly so DLL handles aren't fighting the installer.

## v26.3.3 -- 2026-04-12

### Fixed
- Release notes extractor was not code-fence aware and shipped template prose instead of the actual release notes for v26.3.2.
- `RELEASE_NOTES.md` template now uses a placeholder version (`vX.Y.Z`) in the example so a literal `## v26.3.2` heading inside the example code block can never collide with a real release.

### Changed
- Hardened the local git config: the `upstream` remote (acnicholas/scaddins) is now push-disabled and a `pre-push` hook also rejects any push attempt to it. Pushes to `origin` (bhupas/revit) are unaffected.

---

## v26.3.2 -- 2026-04-12

First public nullCarbon-branded release.

### Added
- Single ribbon button **nullCarbon Export** with the nullCarbon logo (light + dark variants).
- Login window with token caching against the nullCarbon API.
- One-click in-app updater that downloads + runs the installer when a new release is published.
- Automatic startup update check (silent if already on the latest version, never blocks Revit launch).
- Single `.exe` installer covering Revit 2023, 2024, 2025 and 2026 (per-user, no admin needed).
- `RELEASE_NOTES.md` as the single source of truth for this changelog and the in-app updater dialog.
- Interactive `do\3-release.cmd` and `do\4-sync.cmd` wizards.
- One-shot `do\0-install-prerequisites.cmd` that installs the .NET SDK 8, .NET Framework 4.8 Dev Pack, and Inno Setup 6 via winget.

### Changed
- Based on SCaddins by Andrew Nicholas (LGPL-3.0). Every other SCaddins feature is hidden from the user; only the rebranded ExportSchedules window is exposed.

---

## v26.3.1 -- placeholder

Initial nullCarbon-branded test build. Replace this entry the next time you actually ship a 26.3.1.
