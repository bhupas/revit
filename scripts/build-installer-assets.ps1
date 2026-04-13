# nullCarbon Revit Export -- WiX installer branding bitmap generator.
#
# Renders the two branding bitmaps the WiX v5 WixUI_FeatureTree dialog set
# expects, from the source nullcarbon logo PNG in src\Assets. Run once (or
# whenever the brand changes); the BMPs are committed to
# setup\nullcarbon\ and consumed at install time via WixUIBannerBmp /
# WixUIDialogBmp WixVariables in nullcarbon-installer.wxs.
#
#   Banner : 493 x 58  px, 24-bit BMP, white background, logo pinned to the
#            FAR RIGHT. The left ~370 px are kept pure white because WiX
#            draws its dialog title ("End-User License Agreement", etc.)
#            and subtitle over the left portion of the banner on every
#            interior dialog. Any art there collides with that text.
#   Dialog : 493 x 312 px, 24-bit BMP, white background, logo in the left
#            third; the right ~300 px are left blank because WiX draws
#            the Welcome / Finish body text over that region.
#
# Usage:
#     scripts\build-installer-assets.ps1

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$RepoRoot = (Resolve-Path "$PSScriptRoot\..").Path

Add-Type -AssemblyName System.Drawing

$logoPath  = Join-Path $RepoRoot 'src\Assets\nullcarbon-logo-256.png'
$outDir    = Join-Path $RepoRoot 'setup\nullcarbon'
$bannerOut = Join-Path $outDir   'nullcarbon-banner.bmp'
$dialogOut = Join-Path $outDir   'nullcarbon-dialog.bmp'

if (-not (Test-Path $logoPath)) {
    throw "Logo source not found: $logoPath"
}
if (-not (Test-Path $outDir)) {
    throw "Output folder not found: $outDir"
}

$logo = [System.Drawing.Image]::FromFile($logoPath)

function New-Bmp24 {
    param([int]$Width, [int]$Height)
    New-Object System.Drawing.Bitmap $Width, $Height, ([System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
}

function Save-Bmp24 {
    param([System.Drawing.Bitmap]$Bitmap, [string]$Path)
    # Force 24-bit BMP output. WiX v5's native UI rejects 32-bit or
    # indexed BMPs with a cryptic dialog-rendering failure.
    $Bitmap.Save($Path, [System.Drawing.Imaging.ImageFormat]::Bmp)
}

function drawLogo {
    param(
        [System.Drawing.Graphics]$Graphics,
        [System.Drawing.Image]$Logo,
        [int]$X, [int]$Y, [int]$Size
    )
    $Graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $Graphics.SmoothingMode     = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
    $Graphics.PixelOffsetMode   = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $Graphics.DrawImage($Logo, $X, $Y, $Size, $Size)
}

# ---------------------------------------------------------------------------
# Banner: 493 x 58. Pure white left half -- WiX draws its own dialog title
# ("End-User License Agreement" / "Custom Setup" / etc.) and subtitle over
# that area, so anything we put there collides visually with the text. Only
# the far right edge gets the logo. 1 px hairline bottom border.
# ---------------------------------------------------------------------------
$bannerW = 493
$bannerH = 58

$banner = New-Bmp24 $bannerW $bannerH
$g = [System.Drawing.Graphics]::FromImage($banner)
$g.Clear([System.Drawing.Color]::White)

# Logo pinned to the right. 42 px tall (8 px top+bottom margin in the 58 px
# banner), 12 px right margin. Starts at x = 493 - 12 - 42 = 439.
$logoSize = 42
$logoX    = $bannerW - 12 - $logoSize
$logoY    = [math]::Floor(($bannerH - $logoSize) / 2)
drawLogo -Graphics $g -Logo $logo -X $logoX -Y $logoY -Size $logoSize

# 1 px bottom border for visual separation from the dialog body.
$borderPen = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(221, 221, 221))
$g.DrawLine($borderPen, 0, $bannerH - 1, $bannerW, $bannerH - 1)

$g.Dispose()
Save-Bmp24 $banner $bannerOut
$banner.Dispose()
Write-Host "Wrote $bannerOut ($bannerW x $bannerH)"

# ---------------------------------------------------------------------------
# Dialog: 493 x 312, logo stacked over a tagline in the left third. Right
# ~200 px kept clean for WiX's overlaid Welcome / Finish text.
# ---------------------------------------------------------------------------
$dialogW = 493
$dialogH = 312

$dialog = New-Bmp24 $dialogW $dialogH
$g = [System.Drawing.Graphics]::FromImage($dialog)
$g.Clear([System.Drawing.Color]::White)

# Logo centred horizontally inside the left 165 px strip, 60 px from top
$logoSize = 150
$logoX    = [math]::Round((165 - $logoSize) / 2)   # ~8 px
$logoY    = 55
drawLogo -Graphics $g -Logo $logo -X $logoX -Y $logoY -Size $logoSize

# Tagline under the logo. Two lines so we don't bleed into WiX's text area.
$g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::ClearTypeGridFit
$line1Font = New-Object System.Drawing.Font 'Segoe UI', 13, ([System.Drawing.FontStyle]::Bold), ([System.Drawing.GraphicsUnit]::Pixel)
$line2Font = New-Object System.Drawing.Font 'Segoe UI', 11, ([System.Drawing.FontStyle]::Regular), ([System.Drawing.GraphicsUnit]::Pixel)

$taglineBrush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(26, 53, 95))
$subBrush     = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(102, 102, 102))

$sf = New-Object System.Drawing.StringFormat
$sf.Alignment = [System.Drawing.StringAlignment]::Center

$g.DrawString('nullCarbon',          $line1Font, $taglineBrush, 82, 220, $sf)
$g.DrawString('Revit Export',        $line1Font, $taglineBrush, 82, 240, $sf)
$g.DrawString('Per-user - No admin', $line2Font, $subBrush,     82, 270, $sf)

# Hairline divider on the right edge of the logo strip (gives visual weight).
$divPen = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(230, 230, 230))
$g.DrawLine($divPen, 165, 30, 165, $dialogH - 30)

$g.Dispose()
Save-Bmp24 $dialog $dialogOut
$dialog.Dispose()
Write-Host "Wrote $dialogOut ($dialogW x $dialogH)"

$logo.Dispose()
Write-Host "Done."
