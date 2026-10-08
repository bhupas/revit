# nullCarbon Revit Export -- apply branch protection rules to bhupas/revit.
#
# Uses the GitHub CLI (gh) to set the protection rules described in
# CONTRIBUTING.md on the master and dev branches. Idempotent: running
# this twice is safe and just re-applies the same rules.
#
# Prerequisites:
#   - gh CLI installed (do\0-install-prerequisites.cmd installs it via winget)
#   - You have authenticated:  gh auth login
#   - You are an admin on bhupas/revit (you should be -- it's your repo)
#
# Usage:
#   scripts\protect-branches.ps1
#
# To verify rules without changing them:
#   gh api repos/bhupas/revit/branches/master/protection
#   gh api repos/bhupas/revit/branches/dev/protection

[CmdletBinding()]
param(
    [string]$Owner = 'bhupas',
    [string]$Repo  = 'revit'
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

# --- Build the protection payload --------------------------------------------
# This is the GitHub Branch Protection API JSON. Notes on each field:
#   required_status_checks       -> CI must pass (build.yml's matrix jobs)
#   enforce_admins=false         -> admin (you) can bypass for hot fixes / releases
#   required_pull_request_reviews=null -> solo dev, no review required
#   restrictions={users:[Owner]} -> only the owner can push directly
#   required_linear_history=true -> rebase / squash, no merge commits on master
#   allow_force_pushes=false     -> never rewrite published history
#   allow_deletions=false        -> the branch cannot be deleted

$statusChecks = @{
    strict   = $true   # branch must be up to date with base before merge
    contexts = @(
        'Build Release2023',
        'Build Release2024',
        'Build Release2025',
        'Build Release2026',
        'Build Release2027'
    )
}

function Set-Protection {
    param(
        [string]$BranchName,
        [bool]$RequireLinearHistory
    )
    Step "Applying protection to '$BranchName'"

    $body = @{
        required_status_checks         = $statusChecks
        enforce_admins                 = $false
        required_pull_request_reviews  = $null
        restrictions                   = @{
            users = @($Owner)
            teams = @()
            apps  = @()
        }
        required_linear_history        = $RequireLinearHistory
        allow_force_pushes             = $false
        allow_deletions                = $false
        block_creations                = $false
        required_conversation_resolution = $false
    }

    $json = $body | ConvertTo-Json -Depth 10 -Compress
    $tmpFile = [System.IO.Path]::GetTempFileName()
    Set-Content -Path $tmpFile -Value $json -Encoding UTF8

    & gh api -X PUT "repos/$Owner/$Repo/branches/$BranchName/protection" `
        -H "Accept: application/vnd.github+json" `
        --input $tmpFile 2>&1 | Out-Null
    $exit = $LASTEXITCODE
    Remove-Item $tmpFile -Force -ErrorAction SilentlyContinue

    if ($exit -ne 0) {
        Warn "Could not apply protection to '$BranchName' (exit $exit)."
        Warn "If the branch doesn't exist on the remote yet, push it first:"
        Warn "    git push -u origin $BranchName"
        Warn "If the rule already exists with different settings, this is fine -- it just got updated."
        return $false
    }
    Ok "OK"
    return $true
}

# --- Apply ------------------------------------------------------------------
$ok1 = Set-Protection -BranchName 'master' -RequireLinearHistory $true
$ok2 = Set-Protection -BranchName 'dev'    -RequireLinearHistory $false

# --- Done -------------------------------------------------------------------
Step "Done"
if ($ok1 -and $ok2) {
    Ok "Both 'master' and 'dev' are now protected per CONTRIBUTING.md."
    Ok ""
    Ok "Verify in browser:"
    Ok "    https://github.com/$Owner/$Repo/settings/branches"
} else {
    Warn "One or more rules did not apply cleanly. Check the messages above."
    Warn "Manual fallback: open Settings -> Branches and apply the rules from CONTRIBUTING.md."
}
