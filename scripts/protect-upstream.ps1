# nullCarbon Revit Export -- one-shot upstream-push protection.
#
# Locks down this clone so that nothing can accidentally push to
# acnicholas/scaddins (the upstream we forked from).
#
# Two layers (defense in depth):
#   1. Sets the push URL of the 'upstream' remote to a clearly-broken value.
#      Any 'git push upstream' fails immediately with a recognizable error.
#   2. Installs a pre-push hook (.git/hooks/pre-push) that refuses to push
#      to any remote whose URL contains 'acnicholas/scaddins'. Catches the
#      case where someone restores the push URL later.
#
# Both layers are local to this clone (.git is not tracked). Run this once
# after every fresh `git clone` of this repo. The first-time installer
# (do\0-install-prerequisites.cmd) calls it automatically.
#
# Idempotent. Safe to run multiple times.

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$RepoRoot = (Resolve-Path "$PSScriptRoot\..").Path
Set-Location $RepoRoot

function Step($msg) { Write-Host ""; Write-Host "==> $msg" -ForegroundColor Cyan }
function Ok($msg)   { Write-Host "    $msg" -ForegroundColor Green }
function Skip($msg) { Write-Host "    $msg" -ForegroundColor DarkGray }
function Warn($msg) { Write-Host "    $msg" -ForegroundColor Yellow }
function Fail($msg) { Write-Host ""; Write-Host "ERROR: $msg" -ForegroundColor Red; exit 1 }

# --- Sanity ------------------------------------------------------------------
if (-not (Test-Path "$RepoRoot\.git")) {
    Fail "Not a git repository (no .git folder at $RepoRoot)."
}

$remotes = git remote
if ($remotes -notcontains 'upstream') {
    Warn "No 'upstream' remote configured. Nothing to protect."
    Warn "If you intend to track upstream, add it first:"
    Warn "    git remote add upstream https://github.com/acnicholas/scaddins.git"
    exit 0
}

# --- Layer 1: disable upstream push URL --------------------------------------
Step "Layer 1: disable 'upstream' push URL"
$disabledUrl = 'DO_NOT_PUSH_TO_UPSTREAM_USE_ORIGIN_INSTEAD'
$currentPush = git config --get remote.upstream.pushurl 2>$null
if ($currentPush -eq $disabledUrl) {
    Skip "Already disabled."
} else {
    git remote set-url --push upstream $disabledUrl
    if ($LASTEXITCODE -ne 0) { Fail "Could not set upstream push URL." }
    Ok "upstream push URL set to: $disabledUrl"
}

# --- Layer 2: pre-push hook --------------------------------------------------
Step "Layer 2: pre-push hook"
$hookPath = "$RepoRoot\.git\hooks\pre-push"
$hookBody = @'
#!/bin/sh
# nullCarbon Revit Export -- pre-push hook.
# Refuses any push to a remote whose URL points at acnicholas/scaddins.
# Pushes to origin (bhupas/revit) are unaffected.
# Bypass once (DANGEROUS): git push --no-verify ...

remote_name="$1"
remote_url="$2"

case "$remote_url" in
    *acnicholas/scaddins*)
        echo "" >&2
        echo "============================================================" >&2
        echo " pre-push hook: REFUSING PUSH" >&2
        echo "============================================================" >&2
        echo "" >&2
        echo " You tried to push to:" >&2
        echo "   $remote_name -> $remote_url" >&2
        echo "" >&2
        echo " That's the upstream SCaddins repo. We never push there." >&2
        echo " Push to 'origin' (bhupas/revit) instead:" >&2
        echo "" >&2
        echo "   git push origin <branch>" >&2
        echo "" >&2
        exit 1
        ;;
esac

exit 0
'@

# Always overwrite -- it's small and we want the canonical version on disk.
Set-Content -Path $hookPath -Value $hookBody -Encoding ASCII -NoNewline
# Make it executable on systems that respect the bit (Git Bash, WSL, msys).
# On native Windows it doesn't matter; git on Windows runs hooks via sh.
try {
    & icacls.exe $hookPath /grant "*S-1-1-0:RX" 2>&1 | Out-Null
} catch { }
Ok "pre-push hook installed at .git\hooks\pre-push"

# --- Verification ------------------------------------------------------------
Step "Verifying"
git remote -v | ForEach-Object {
    if ($_ -match 'upstream') {
        if ($_ -match $disabledUrl) {
            Ok "$_"
        } elseif ($_ -match '\(fetch\)') {
            Ok "$_"
        } else {
            Warn "$_  <-- still has a real push URL!"
        }
    }
}

Step "Done"
Ok "upstream is now push-protected on this clone."
Ok "(Both layers are local to .git/, which is per-clone -- re-run this"
Ok " script on any fresh 'git clone' of this repo.)"
