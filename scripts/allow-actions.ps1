# nullCarbon Revit Export -- allow GitHub Actions used by our workflows.
#
# By default this fork's "Actions permissions" was locked down to
# "Allow bhupas actions and reusable workflows" only, which blocks
# actions/checkout, actions/setup-dotnet, actions/upload-artifact, and
# softprops/action-gh-release. That breaks build.yml, release.yml, and
# sync-upstream.yml.
#
# This script switches the repo to the "selected" policy and explicitly
# allows:
#   - all actions created by GitHub        (covers actions/*)
#   - all Verified Creator actions         (covers softprops/action-gh-release)
#   - any extra patterns we add below
#
# Idempotent: re-running it just re-applies the same settings.
#
# Prerequisites:
#   - gh CLI installed and authenticated (gh auth login)
#   - You are an admin on bhupas/revit
#
# Usage:
#   scripts\allow-actions.ps1
#
# To verify without changing anything:
#   gh api repos/bhupas/revit/actions/permissions
#   gh api repos/bhupas/revit/actions/permissions/selected-actions

[CmdletBinding()]
param(
    [string]$Owner = 'bhupas',
    [string]$Repo  = 'revit',
    [string[]]$ExtraPatterns = @()
)

$ErrorActionPreference = 'Stop'

function Step($msg) { Write-Host ""; Write-Host "==> $msg" -ForegroundColor Cyan }
function Ok($msg)   { Write-Host "    $msg" -ForegroundColor Green }
function Warn($msg) { Write-Host "    $msg" -ForegroundColor Yellow }
function Fail($msg) { Write-Host ""; Write-Host "ERROR: $msg" -ForegroundColor Red; exit 1 }

# --- Preflight ---------------------------------------------------------------
Step "Checking gh CLI"
$gh = Get-Command gh -ErrorAction SilentlyContinue
if (-not $gh) {
    Fail @"
gh CLI is not installed.

Install with:
    winget install --id GitHub.cli

Then close + re-open this terminal so PATH picks it up, run:
    gh auth login

...and re-run this script.
"@
}
Ok (& gh --version | Select-Object -First 1)

Step "Checking gh authentication"
& gh auth status 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) {
    Fail @"
gh CLI is installed but not authenticated.

Run:
    gh auth login

Pick GitHub.com -> HTTPS -> 'Login with a web browser'. Then re-run this script.
"@
}
Ok "Authenticated."

# --- Step 1: switch repo to the "selected" actions policy --------------------
# Possible values: all, local_only, selected
# We need 'selected' so we can mix bhupas + GitHub-owned + verified creators.
Step "Setting actions permissions policy to 'selected'"

$permsBody = @{
    enabled         = $true
    allowed_actions = 'selected'
} | ConvertTo-Json -Compress

$tmpPerms = [System.IO.Path]::GetTempFileName()
Set-Content -Path $tmpPerms -Value $permsBody -Encoding UTF8

& gh api -X PUT "repos/$Owner/$Repo/actions/permissions" `
    -H "Accept: application/vnd.github+json" `
    --input $tmpPerms 2>&1 | Out-Null
$exit = $LASTEXITCODE
Remove-Item $tmpPerms -Force -ErrorAction SilentlyContinue

if ($exit -ne 0) {
    Fail "Could not update actions permissions (exit $exit). Are you an admin on $Owner/$Repo?"
}
Ok "Policy = selected"

# --- Step 2: allow GitHub-owned + verified creators + our patterns -----------
Step "Allowing GitHub-owned, verified creators, and extra patterns"

# Patterns we know our workflows need. Add more here as workflows grow.
$patterns = @(
    'softprops/action-gh-release@*'
) + $ExtraPatterns | Select-Object -Unique

$selectedBody = @{
    github_owned_allowed = $true   # actions/checkout, actions/setup-dotnet, actions/upload-artifact, ...
    verified_allowed     = $true   # softprops, docker, hashicorp, ... (anything with the verified badge)
    patterns_allowed     = $patterns
} | ConvertTo-Json -Compress

$tmpSel = [System.IO.Path]::GetTempFileName()
Set-Content -Path $tmpSel -Value $selectedBody -Encoding UTF8

& gh api -X PUT "repos/$Owner/$Repo/actions/permissions/selected-actions" `
    -H "Accept: application/vnd.github+json" `
    --input $tmpSel 2>&1 | Out-Null
$exit = $LASTEXITCODE
Remove-Item $tmpSel -Force -ErrorAction SilentlyContinue

if ($exit -ne 0) {
    Fail "Could not update selected-actions allow list (exit $exit)."
}
Ok "github_owned_allowed = true"
Ok "verified_allowed     = true"
foreach ($p in $patterns) { Ok "pattern              = $p" }

# --- Done -------------------------------------------------------------------
Step "Done"
Ok "$Owner/$Repo can now run actions/* and softprops/action-gh-release."
Ok ""
Ok "Verify in browser:"
Ok "    https://github.com/$Owner/$Repo/settings/actions"
