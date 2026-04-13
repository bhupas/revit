# nullCarbon Revit Export -- installer packager.
#
# Wraps WiX v5. Reads the assembly version from one of the built DLLs,
# auto-detects which Release<year> folders exist, and passes -d R<year>=Enabled
# defines so the .wxs preprocessor bundles only those Revit versions.
#
# Usage:
#     scripts\build-installer.ps1                         # auto-detect version + configs
#     scripts\build-installer.ps1 -Version 26.3.1
#     scripts\build-installer.ps1 -WixExe "C:\path\to\wix.exe"
#
# If wix.exe is not on PATH and -WixExe is not given, the script installs it
# as a dotnet global tool (dotnet tool install --global wix).
#
# Output: ONE file per release at setup\out\nullCarbon-LCA-Export-win64-<version>.msi

[CmdletBinding()]
param(
    [string]$Version,
    [string]$WixExe
)

$ErrorActionPreference = 'Stop'
$RepoRoot = (Resolve-Path "$PSScriptRoot\..").Path
Set-Location $RepoRoot

function Step($msg) { Write-Host ""; Write-Host "==> $msg" -ForegroundColor Cyan }
function Ok($msg)   { Write-Host "    $msg" -ForegroundColor Green }
function Fail($msg) { Write-Host "ERROR: $msg" -ForegroundColor Red; exit 1 }

# --- Locate wix.exe -----------------------------------------------------------
if (-not $WixExe) {
    $candidate = Get-Command wix -ErrorAction SilentlyContinue
    if ($candidate) {
        $WixExe = $candidate.Source
    }
}

# We pin to WiX v5. WiX v7 introduced a paid Open Source Maintenance Fee
# EULA (https://wixtoolset.org/osmf/) that has to be accepted out-of-band
# before `wix build` will run. v5 is the last fully-free version and has
# everything we need (Files element, perUser scope, MajorUpgrade, ...).
$WixVersion = '5.0.2'

function Test-WixIsV5 {
    param([string]$ExePath)
    if (-not (Test-Path $ExePath)) { return $false }
    $verLine = & $ExePath --version 2>$null | Select-Object -First 1
    if (-not $verLine) { return $false }
    return $verLine -match '^5\.'
}

$toolsDir = Join-Path $env:USERPROFILE ".dotnet\tools"

if (-not $WixExe -or -not (Test-Path $WixExe)) {
    if (Test-Path "$toolsDir\wix.exe") {
        $WixExe = "$toolsDir\wix.exe"
    }
}

if (-not $WixExe -or -not (Test-Path $WixExe) -or -not (Test-WixIsV5 $WixExe)) {
    Step "Installing WiX v$WixVersion as dotnet global tool"
    $dotnet = Get-Command dotnet -ErrorAction SilentlyContinue
    if (-not $dotnet) {
        Fail "dotnet SDK not found. Install .NET 8 SDK first, then re-run."
    }
    # Uninstall any pre-existing wix tool so we don't end up with v6/v7 stuck
    # in place (which would hit the OSMF EULA wall).
    & dotnet tool uninstall --global wix 2>&1 | Out-Null
    & dotnet tool install --global wix --version $WixVersion 2>&1 | Write-Host
    if ($LASTEXITCODE -ne 0) {
        Fail "dotnet tool install wix --version $WixVersion failed (exit $LASTEXITCODE)."
    }
    if (Test-Path "$toolsDir\wix.exe") {
        $WixExe = "$toolsDir\wix.exe"
        if (-not ($env:PATH -split ';' | Where-Object { $_ -eq $toolsDir })) {
            $env:PATH = "$toolsDir;$env:PATH"
        }
    } else {
        Fail "WiX install appeared to succeed but wix.exe was not found at $toolsDir\wix.exe."
    }
}
Step "WiX"
Ok $WixExe
& $WixExe --version 2>&1 | ForEach-Object { Ok $_ }

# --- Make sure the WiX UI extension is installed ------------------------------
# WixUI_FeatureTree (the feature picker dialog) lives in WixToolset.UI.wixext,
# which has to be added to wix's per-user extension cache before `wix build`
# can resolve the ui:WixUI namespace in our .wxs.
Step "WiX UI extension"
$extList = & $WixExe extension list --global 2>&1
$hasUiExt = $false
if ($extList) {
    foreach ($line in $extList) {
        if ($line -match 'WixToolset\.UI\.wixext') { $hasUiExt = $true; break }
    }
}
if ($hasUiExt) {
    Ok "WixToolset.UI.wixext already installed"
} else {
    Write-Host "    Installing WixToolset.UI.wixext/$WixVersion"
    & $WixExe extension add --global "WixToolset.UI.wixext/$WixVersion" 2>&1 | ForEach-Object { Write-Host "    $_" }
    if ($LASTEXITCODE -ne 0) {
        Fail "wix extension add WixToolset.UI.wixext/$WixVersion failed (exit $LASTEXITCODE)"
    }
    Ok "Installed."
}

# --- Detect built configurations ---------------------------------------------
$years = @('2023','2024','2025','2026')
$builtYears = @()
foreach ($y in $years) {
    if (Test-Path "$RepoRoot\src\bin\Release$y\SCaddins.dll") { $builtYears += $y }
}
if ($builtYears.Count -eq 0) {
    Fail "No built configurations found under src\bin\Release<year>. Run do\1-build.cmd first."
}
Step "Detected built configurations"
$builtYears | ForEach-Object { Ok "Release$_" }

# --- Resolve version ----------------------------------------------------------
if (-not $Version) {
    foreach ($y in @('2025','2026','2024','2023')) {
        $dll = "$RepoRoot\src\bin\Release$y\SCaddins.dll"
        if (Test-Path $dll) {
            $info = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($dll)
            $Version = "$($info.FileMajorPart).$($info.FileMinorPart).$($info.FileBuildPart)"
            Step "Detected version $Version from $dll"
            break
        }
    }
}
if (-not $Version) {
    Fail "Could not auto-detect version. Pass -Version explicitly."
}

# --- Stage files for WiX ------------------------------------------------------
# WiX v5's <Files> element has no Exclude attribute, so we can't tell it to
# skip the Revit API DLLs that get copied into the build output by the C#
# compiler (they're <CopyLocal>true</CopyLocal> for compilation but must NOT
# ship in our installer -- Revit ships its own copies).
#
# Instead we filter here in PowerShell and copy the keep-list into a staging
# tree that WiX can ingest with a simple `Files Include="...\**"` glob.
#
# Layout:
#   setup\out\stage\<year>\addin\nullCarbon-LCA-Export.addin
#   setup\out\stage\<year>\app\<filtered DLLs + Monaco\**>
$stageRoot = "$RepoRoot\setup\out\stage"
Step "Staging files for WiX"
if (Test-Path $stageRoot) {
    Remove-Item -Recurse -Force $stageRoot
}
New-Item -ItemType Directory -Force -Path $stageRoot | Out-Null

# Files we never ship -- they belong to Revit, not us.
$excludePatterns = @(
    'AdWindows.dll',
    'UIFramework.dll',
    'RevitAPI.dll',
    'RevitAPIUI.dll'
)

foreach ($y in $builtYears) {
    $src = "$RepoRoot\src\bin\Release$y"
    $appDst   = "$stageRoot\$y\app"
    $addinDst = "$stageRoot\$y\addin"
    New-Item -ItemType Directory -Force -Path $appDst   | Out-Null
    New-Item -ItemType Directory -Force -Path $addinDst | Out-Null

    # 1) Filtered DLLs into stage\<y>\app\
    Get-ChildItem -Path $src -Filter '*.dll' -File | Where-Object {
        $excludePatterns -notcontains $_.Name -and
        $_.Name -notlike 'Revit*'
    } | Copy-Item -Destination $appDst -Force

    # 2) Monaco/ subtree (optional -- only present for some configs).
    if (Test-Path "$src\Monaco") {
        Copy-Item -Recurse -Force "$src\Monaco" "$appDst\Monaco"
    }

    # 3) The .addin manifest, renamed to the canonical filename.
    $addinSrc = "$src\nullCarbon-LCA-Export-$y.addin"
    if (-not (Test-Path $addinSrc)) {
        Fail "Missing addin manifest: $addinSrc"
    }
    Copy-Item $addinSrc "$addinDst\nullCarbon-LCA-Export.addin" -Force

    $count = (Get-ChildItem -Recurse -File $appDst | Measure-Object).Count
    Ok "Release$y -> $count files staged in $appDst"
}

# --- Run WiX ------------------------------------------------------------------
$wxs = "$RepoRoot\setup\nullcarbon\nullcarbon-installer.wxs"
if (-not (Test-Path $wxs)) { Fail "Installer source not found: $wxs" }

$outDir = "$RepoRoot\setup\out"
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
$outFile = "$outDir\nullCarbon-LCA-Export-win64-$Version.msi"

# Preprocessor defines. -d Name=Value sets $(var.Name) inside the .wxs file.
# -ext loads the UI dialog set so ui:WixUI Id="WixUI_FeatureTree" resolves.
$wixArgs = @(
    'build',
    '-arch', 'x64',
    '-ext', 'WixToolset.UI.wixext',
    '-d', "Version=$Version"
)
foreach ($y in $builtYears) {
    $wixArgs += @('-d', "R$y=Enabled")
}
$wixArgs += @('-o', $outFile, $wxs)

Step "Compiling installer"
Ok ("wix " + ($wixArgs -join ' '))

# WiX must run from the .wxs file's directory so the relative StageDir
# (..\out\stage) and nullcarbon.ico paths resolve correctly.
Push-Location (Split-Path $wxs)
try {
    & $WixExe @wixArgs
    $exit = $LASTEXITCODE
} finally {
    Pop-Location
}
if ($exit -ne 0) { Fail "WiX build failed (exit $exit)" }

Step "Done"
if (Test-Path $outFile) {
    $size = [math]::Round((Get-Item $outFile).Length / 1MB, 1)
    Ok "Output: $outFile ($size MB)"
    Ok "Bundles: $($builtYears -join ', ')"
} else {
    Fail "Expected output not found: $outFile"
}
