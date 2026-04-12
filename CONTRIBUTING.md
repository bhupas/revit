# Contributing to nullCarbon Revit Export

## Branch model

This repo uses two long-lived branches:

| Branch | What it is | Who pushes here directly | How code lands here |
|---|---|---|---|
| **`master`** | The release branch. Every tagged release is built from here. Always production-ready. | Only the repo owner, and only for releases. | Pull requests from `dev`. |
| **`dev`** | The development branch. Day-to-day work. | Only the repo owner, and only for small fixes. | Pull requests from feature branches OR direct push by the owner. |

Anything else (`sync/upstream-YYYY-MM-DD`, `feature/foo`, `fix/bar`) is short-lived and gets deleted after merge.

### The flow

```
                feature/foo
                    |
                    v
upstream/master --> dev --> master --> tag v26.3.4 --> GitHub Release
                                      ^
                                      | (PR + review)
```

1. **Make a change**: branch off `dev`, work, push, open a PR targeting `dev`.
2. **Merge to dev**: review (or self-review), merge the PR. CI builds it on `dev` to confirm.
3. **Promote to master**: when `dev` is in a shippable state, open a PR `dev → master`. Merge it.
4. **Release**: from `master`, run `do\3-release.cmd` (which refuses to run from any other branch). The wizard tags `vX.Y.Z`, pushes the tag, and `release.yml` publishes the GitHub Release with the installer attached.

Upstream-sync PRs (from the weekly `sync-upstream.yml` workflow) automatically target `dev`, so you can review them and bake them in `dev` before they ever touch `master`.

## Branch protection rules

The repo owner has applied these rules on GitHub. They formalize the "only owner can land things on master" intent.

### `master`

| Setting | Value |
|---|---|
| Restrict who can push to matching branches | Repo admins (owner) only |
| Require a pull request before merging | optional (the owner can push directly for releases) |
| Require status checks to pass before merging | `Build / Build Release2023`, `Build / Build Release2024`, `Build / Build Release2025`, `Build / Build Release2026` |
| Require branches to be up to date before merging | yes |
| Require linear history | yes |
| Allow force pushes | NO |
| Allow deletions | NO |

### `dev`

| Setting | Value |
|---|---|
| Restrict who can push to matching branches | Repo admins (owner) only |
| Require status checks to pass before merging | `Build / Build Release2023`, `Build / Build Release2024`, `Build / Build Release2025`, `Build / Build Release2026` |
| Allow force pushes | NO |
| Allow deletions | NO |

### Applying the rules

Two ways:

1. **Run `scripts\protect-branches.ps1`** (recommended). It uses the `gh` CLI to apply the rules above. Requires `gh auth login` first.
2. **Manually via the GitHub web UI**: Settings -> Branches -> Add branch ruleset (or Add classic branch protection rule). Apply to `master` and `dev` separately, with the settings in the tables above.

The script is idempotent — running it twice is safe. Re-run it after any fresh clone of the repo if you want to verify the remote rules still match.

## Coding conventions

- All nullCarbon-specific code lives under [`src/NullCarbon/`](src/NullCarbon/). It's the only path under `src/` that upstream merges never touch.
- Edits to upstream-tracked files are limited to `src/SCaddins.cs`, `src/SCaddins.csproj`, `src/SCaddins.addin`, `src/Constants.cs`, and `src/Common/BasicDialogService.cs`. Each one is documented in [`docs/SYNCING.md`](docs/SYNCING.md).
- Commit messages use the conventional `feat:` / `fix:` / `chore:` / `docs:` / `refactor:` prefixes.
- Don't commit `.claude/settings.json`, `setup/out/*.exe`, `src/Resources/BuildDate.txt`. They're build artifacts / IDE state.

## Releases

See [`docs/RELEASING.md`](docs/RELEASING.md). The TL;DR:

1. On `master` (after merging `dev` to `master`), edit `RELEASE_NOTES.md` and add a `## v<version>` section.
2. Double-click `do\3-release.cmd`. The wizard prompts for the version, validates the release notes, builds, packages, tags, and pushes.
3. The tag push triggers `.github/workflows/release.yml` which publishes the GitHub Release.
