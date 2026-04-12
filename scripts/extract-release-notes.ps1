# nullCarbon Revit Export -- extract a single version's release notes from
# RELEASE_NOTES.md and write them to a file (or stdout).
#
# Used by:
#   - .github\workflows\release.yml  -> sets the GitHub Release body
#   - scripts\release-interactive.ps1 -> validates an entry exists before tag
#
# Usage:
#   scripts\extract-release-notes.ps1 -Version 26.3.2
#   scripts\extract-release-notes.ps1 -Version 26.3.2 -Output notes-out.md
#   scripts\extract-release-notes.ps1 -Version 26.3.2 -CheckOnly
#
# Exit codes:
#   0 = section found (and written if -Output given)
#   1 = section not found
#   2 = RELEASE_NOTES.md missing or unreadable

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$Version,

    [string]$NotesFile,
    [string]$Output,
    [switch]$CheckOnly
)

$ErrorActionPreference = 'Stop'
$RepoRoot = (Resolve-Path "$PSScriptRoot\..").Path
if (-not $NotesFile) { $NotesFile = Join-Path $RepoRoot 'RELEASE_NOTES.md' }

if (-not (Test-Path $NotesFile)) {
    Write-Error "RELEASE_NOTES.md not found at $NotesFile"
    exit 2
}

$lines = Get-Content -Path $NotesFile -Encoding UTF8

# Find the line index of "## vX.Y.Z" (with optional trailing date / text),
# IGNORING any lines that fall inside a fenced code block (``` ... ```).
# Without the code-fence guard, an example "## v26.3.2 ..." inside a
# template code block would be matched as a real heading and we'd ship
# template prose instead of actual release notes.
$escaped = [regex]::Escape($Version)
$startHeader = -1
$inFence = $false
for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -match '^\s*```') {
        $inFence = -not $inFence
        continue
    }
    if ($inFence) { continue }
    if ($lines[$i] -match "^##\s+v$escaped(\s|$)") {
        $startHeader = $i
        break
    }
}

if ($startHeader -lt 0) {
    if ($CheckOnly) { exit 1 }
    Write-Error "No '## v$Version' section found in $NotesFile."
    Write-Error "Add one and re-run. See the top of RELEASE_NOTES.md for the format."
    exit 1
}

if ($CheckOnly) {
    Write-Host "OK: found '## v$Version' at line $($startHeader + 1)" -ForegroundColor Green
    exit 0
}

# Find the next "## v..." heading (or EOF) -- that's where this section ends.
# Same code-fence guard as above so an example heading inside a code block
# inside our section can't truncate it early.
$endIdx = $lines.Count
$inFence2 = $false
for ($j = $startHeader + 1; $j -lt $lines.Count; $j++) {
    if ($lines[$j] -match '^\s*```') {
        $inFence2 = -not $inFence2
        continue
    }
    if ($inFence2) { continue }
    if ($lines[$j] -match '^##\s+v\d') {
        $endIdx = $j
        break
    }
}

# Slice from line AFTER the heading to line BEFORE the next heading,
# trim leading/trailing blank lines.
$bodyLines = @()
if ($startHeader + 1 -lt $endIdx) {
    $bodyLines = $lines[($startHeader + 1)..($endIdx - 1)]
}
function Test-IsBlankOrHr($line) {
    return [string]::IsNullOrWhiteSpace($line) -or ($line -match '^\s*---+\s*$')
}
while ($bodyLines.Count -gt 0 -and (Test-IsBlankOrHr $bodyLines[0])) {
    $bodyLines = $bodyLines[1..($bodyLines.Count - 1)]
}
while ($bodyLines.Count -gt 0 -and (Test-IsBlankOrHr $bodyLines[-1])) {
    $bodyLines = $bodyLines[0..($bodyLines.Count - 2)]
}

$section = ($bodyLines -join "`n")

if ($Output) {
    Set-Content -Path $Output -Value $section -Encoding UTF8
    Write-Host "Wrote release notes for v$Version to $Output" -ForegroundColor Green
} else {
    Write-Output $section
}
exit 0
