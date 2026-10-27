# Render the fork's brand raster assets from brand.json without any network access.
#
# Produces, relative to apps/desktop:
#   resources/icon-windows.png          1024x1024 application icon (electron-builder derives the .ico)
#   resources/icon-windows.svg          vector source of the same artwork (tray icon renderer input)
#   resources/tray-windows.ico          multi-size tray icon (16..64 px, PNG-compressed entries)
#   installer/assets/brand.png          600x196  installer header wordmark, light background
#   installer/assets/brand-2x.png       1200x392 installer header wordmark, light background
#   installer/assets/brand-dark.png     600x196  installer header wordmark, dark background
#   installer/assets/brand-dark-2x.png  1200x392 installer header wordmark, dark background
#   installer/assets/uninstaller-sidebar.png 164x314 uninstaller side panel
#
# Run: powershell -NoProfile -ExecutionPolicy Bypass -File apps/desktop/local-fork/render-assets.ps1

[CmdletBinding()]
param([string]$BrandFile)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

if (-not $BrandFile) { $BrandFile = Join-Path $PSScriptRoot 'brand.json' }
$brand = Get-Content -LiteralPath $BrandFile -Raw -Encoding UTF8 | ConvertFrom-Json
$appRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$resources = Join-Path $appRoot 'resources'
$assets = Join-Path $appRoot 'installer/assets'

$productName = [string]$brand.productName
if ([string]::IsNullOrWhiteSpace($productName)) { throw 'brand.json: productName is required' }

# Palette: deep blue to violet, white glyph. Change these to re-skin the whole asset set.
$colorStart = [Drawing.Color]::FromArgb(255, 59, 107, 255)
$colorEnd = [Drawing.Color]::FromArgb(255, 139, 92, 246)
$lightInk = [Drawing.Color]::FromArgb(255, 16, 24, 40)
$darkInk = [Drawing.Color]::FromArgb(255, 245, 247, 250)
$glyph = [Drawing.Color]::White

function New-RoundedPath([single]$x, [single]$y, [single]$width, [single]$height, [single]$radius) {
  $path = [Drawing.Drawing2D.GraphicsPath]::new()
  $diameter = $radius * 2
  $path.AddArc($x, $y, $diameter, $diameter, 180, 90)
  $path.AddArc($x + $width - $diameter, $y, $diameter, $diameter, 270, 90)
  $path.AddArc($x + $width - $diameter, $y + $height - $diameter, $diameter, $diameter, 0, 90)
  $path.AddArc($x, $y + $height - $diameter, $diameter, $diameter, 90, 90)
  $path.CloseFigure()
  return $path
}

# Four-point sparkle built from four cubic segments whose control points hug the axes,
# which pulls the outline inward and leaves slim concave points.
function Get-SparklePoints([double]$centerX, [double]$centerY, [double]$radius, [double]$waist = 0.16, [int]$samples = 48) {
  $c = $radius * $waist
  $anchors = @(
    @(0, -$radius, 0, -$c, $c, 0, $radius, 0),
    @($radius, 0, $c, 0, 0, $c, 0, $radius),
    @(0, $radius, 0, $c, -$c, 0, -$radius, 0),
    @(-$radius, 0, -$c, 0, 0, -$c, 0, -$radius)
  )
  $points = [System.Collections.Generic.List[Drawing.PointF]]::new()
  foreach ($segment in $anchors) {
    $x0 = $segment[0]; $y0 = $segment[1]
    $x1 = $segment[2]; $y1 = $segment[3]
    $x2 = $segment[4]; $y2 = $segment[5]
    $x3 = $segment[6]; $y3 = $segment[7]
    for ($i = 0; $i -lt $samples; $i++) {
      $t = $i / [double]$samples
      $u = 1 - $t
      $x = $u * $u * $u * $x0 + 3 * $u * $u * $t * $x1 + 3 * $u * $t * $t * $x2 + $t * $t * $t * $x3
      $y = $u * $u * $u * $y0 + 3 * $u * $u * $t * $y1 + 3 * $u * $t * $t * $y2 + $t * $t * $t * $y3
      $points.Add([Drawing.PointF]::new([single]($centerX + $x), [single]($centerY + $y)))
    }
  }
  return , $points.ToArray()
}

function New-SparklePath([double]$centerX, [double]$centerY, [double]$radius, [double]$waist = 0.16) {
  $path = [Drawing.Drawing2D.GraphicsPath]::new()
  $path.AddPolygon((Get-SparklePoints $centerX $centerY $radius $waist))
  return $path
}

function Set-HighQuality([Drawing.Graphics]$graphics) {
  $graphics.SmoothingMode = [Drawing.Drawing2D.SmoothingMode]::AntiAlias
  $graphics.InterpolationMode = [Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
  $graphics.PixelOffsetMode = [Drawing.Drawing2D.PixelOffsetMode]::HighQuality
  $graphics.TextRenderingHint = [Drawing.Text.TextRenderingHint]::AntiAliasGridFit
}

function New-Canvas([int]$width, [int]$height) {
  $bitmap = [Drawing.Bitmap]::new($width, $height, [Drawing.Imaging.PixelFormat]::Format32bppArgb)
  $graphics = [Drawing.Graphics]::FromImage($bitmap)
  Set-HighQuality $graphics
  $graphics.Clear([Drawing.Color]::Transparent)
  return @($bitmap, $graphics)
}

function Get-GradientBrush([Drawing.RectangleF]$bounds) {
  return [Drawing.Drawing2D.LinearGradientBrush]::new(
    [Drawing.PointF]::new($bounds.X, $bounds.Y),
    [Drawing.PointF]::new($bounds.Right, $bounds.Bottom),
    $colorStart, $colorEnd)
}

# Draws the tile artwork (rounded gradient square plus sparkle) into the given rectangle.
function Add-Tile([Drawing.Graphics]$graphics, [Drawing.RectangleF]$bounds, [double]$glyphScale) {
  $radius = $bounds.Width * 0.2266
  $path = New-RoundedPath $bounds.X $bounds.Y $bounds.Width $bounds.Height $radius
  $brush = Get-GradientBrush $bounds
  try { $graphics.FillPath($brush, $path) } finally { $brush.Dispose(); $path.Dispose() }

  $centerX = $bounds.X + $bounds.Width / 2
  $centerY = $bounds.Y + $bounds.Height / 2
  $radius = $bounds.Width * $glyphScale

  $accent = New-SparklePath ($centerX + $bounds.Width * 0.215) ($centerY - $bounds.Height * 0.215) ($radius * 0.3)
  $accentBrush = [Drawing.SolidBrush]::new([Drawing.Color]::FromArgb(205, 255, 255, 255))
  try { $graphics.FillPath($accentBrush, $accent) } finally { $accentBrush.Dispose(); $accent.Dispose() }

  $main = New-SparklePath $centerX $centerY $radius
  $mainBrush = [Drawing.SolidBrush]::new($glyph)
  try { $graphics.FillPath($mainBrush, $main) } finally { $mainBrush.Dispose(); $main.Dispose() }
}

function Save-Png([Drawing.Bitmap]$bitmap, [string]$path) {
  $bitmap.Save($path, [Drawing.Imaging.ImageFormat]::Png)
  Write-Output "rendered $path"
}

# --- application icon -------------------------------------------------------------------------
$margin = 24
$canvas = New-Canvas 1024 1024
$icon = $canvas[0]; $g = $canvas[1]
try {
  Add-Tile $g ([Drawing.RectangleF]::new($margin, $margin, 1024 - 2 * $margin, 1024 - 2 * $margin)) 0.293
}
finally { $g.Dispose() }
try { Save-Png $icon (Join-Path $resources 'icon-windows.png') } finally { $icon.Dispose() }

# --- vector source used by `pnpm run render:tray-icon` ----------------------------------------
function Format-Number([double]$value) { return $value.ToString('0.##', [Globalization.CultureInfo]::InvariantCulture) }

function Get-SparklePathData([double]$centerX, [double]$centerY, [double]$radius, [double]$waist = 0.16) {
  $c = $radius * $waist
  $points = @(
    @(0, -$radius), @(0, -$c), @($c, 0), @($radius, 0),
    @($c, 0), @(0, $c), @(0, $radius),
    @(0, $c), @(-$c, 0), @(-$radius, 0),
    @(-$c, 0), @(0, -$c), @(0, -$radius)
  )
  $builder = [Text.StringBuilder]::new()
  [void]$builder.Append(("M {0} {1}" -f (Format-Number ($centerX + $points[0][0])), (Format-Number ($centerY + $points[0][1]))))
  $index = 1
  while ($index -lt $points.Count) {
    $c1 = $points[$index]; $c2 = $points[$index + 1]; $end = $points[$index + 2]
    [void]$builder.Append((" C {0} {1} {2} {3} {4} {5}" -f
      (Format-Number ($centerX + $c1[0])), (Format-Number ($centerY + $c1[1])),
      (Format-Number ($centerX + $c2[0])), (Format-Number ($centerY + $c2[1])),
      (Format-Number ($centerX + $end[0])), (Format-Number ($centerY + $end[1]))))
    $index += 3
  }
  [void]$builder.Append(' Z')
  return $builder.ToString()
}

$svgMain = Get-SparklePathData 512 512 286
$svgAccent = Get-SparklePathData 721.8 302.2 85.8
$svg = @"
<svg width="1024" height="1024" viewBox="0 0 1024 1024" fill="none" xmlns="http://www.w3.org/2000/svg">
<rect x="24" y="24" width="976" height="976" rx="221" fill="url(#tile)"/>
<path id="tray-glyph" d="$svgMain" fill="#FFFFFF"/>
<path d="$svgAccent" fill="#FFFFFF" fill-opacity="0.8"/>
<defs>
<linearGradient id="tile" x1="24" y1="24" x2="1000" y2="1000" gradientUnits="userSpaceOnUse">
<stop offset="0" stop-color="#3B6BFF"/>
<stop offset="1" stop-color="#8B5CF6"/>
</linearGradient>
</defs>
</svg>
"@
[IO.File]::WriteAllText((Join-Path $resources 'icon-windows.svg'), $svg, [Text.UTF8Encoding]::new($false))
Write-Output "rendered $(Join-Path $resources 'icon-windows.svg')"

# --- tray icon: one crisp bitmap per display scale, packed as PNG entries ----------------------
$traySizes = @(16, 20, 24, 32, 40, 48, 64)
$trayBlobs = @()
foreach ($size in $traySizes) {
  $tray = New-Canvas $size $size
  $bitmap = $tray[0]; $g = $tray[1]
  $stream = [IO.MemoryStream]::new()
  try {
    Add-Tile $g ([Drawing.RectangleF]::new(0, 0, $size, $size)) 0.36
    $g.Dispose()
    $bitmap.Save($stream, [Drawing.Imaging.ImageFormat]::Png)
    $trayBlobs += ,@($size, $stream.ToArray())
  }
  finally { $stream.Dispose(); $g.Dispose(); $bitmap.Dispose() }
}

$icoStream = [IO.MemoryStream]::new()
$writer = [IO.BinaryWriter]::new($icoStream)
try {
  $writer.Write([uint16]0)                     # reserved
  $writer.Write([uint16]1)                     # type: icon
  $writer.Write([uint16]$trayBlobs.Count)
  $offset = 6 + 16 * $trayBlobs.Count
  foreach ($blob in $trayBlobs) {
    $size = $blob[0]; $data = $blob[1]
    $writer.Write([byte]$size)                 # width
    $writer.Write([byte]$size)                 # height
    $writer.Write([byte]0)                     # palette size
    $writer.Write([byte]0)                     # reserved
    $writer.Write([uint16]1)                   # colour planes
    $writer.Write([uint16]32)                  # bits per pixel
    $writer.Write([uint32]$data.Length)
    $writer.Write([uint32]$offset)
    $offset += $data.Length
  }
  foreach ($blob in $trayBlobs) { $writer.Write([byte[]]$blob[1]) }
  $writer.Flush()
  [IO.File]::WriteAllBytes((Join-Path $resources 'tray-windows.ico'), $icoStream.ToArray())
}
finally { $writer.Dispose(); $icoStream.Dispose() }
Write-Output "rendered $(Join-Path $resources 'tray-windows.ico')"

# --- installer wordmark -----------------------------------------------------------------------
function Save-Wordmark([int]$width, [int]$height, [Drawing.Color]$ink, [string]$path) {
  $canvas = New-Canvas $width $height
  $bitmap = $canvas[0]; $g = $canvas[1]
  try {
    $scale = $height / 196.0
    $name = $productName
    # Shrink the type until the mark and the complete name fit the canvas with a safe margin.
    $fontSize = 76 * $scale
    $font = $null
    $textSize = $null
    while ($true) {
      if ($null -ne $font) { $font.Dispose() }
      $font = [Drawing.Font]::new('Segoe UI', [single]$fontSize, [Drawing.FontStyle]::Bold, [Drawing.GraphicsUnit]::Pixel)
      $textSize = $g.MeasureString($name, $font)
      $markSize = $fontSize * 1.37
      $gap = $fontSize * 0.39
      if (($markSize + $gap + $textSize.Width) -le ($width * 0.9) -or $fontSize -le 10) { break }
      $fontSize = $fontSize - 2
    }
    try {
      $format = [Drawing.StringFormat]::new()
      try {
        $format.Alignment = [Drawing.StringAlignment]::Near
        $format.LineAlignment = [Drawing.StringAlignment]::Center
        $format.FormatFlags = [Drawing.StringFormatFlags]::NoWrap
        $markSize = $fontSize * 1.37
        $gap = $fontSize * 0.39
        $totalWidth = $markSize + $gap + $textSize.Width
        $originX = ($width - $totalWidth) / 2
        $originY = ($height - $markSize) / 2
        Add-Tile $g ([Drawing.RectangleF]::new($originX, $originY, $markSize, $markSize)) 0.293
        $brush = [Drawing.SolidBrush]::new($ink)
        try {
          $g.DrawString($name, $font, $brush,
            [Drawing.RectangleF]::new([single]($originX + $markSize + $gap), 0, [single]($textSize.Width + 4), [single]$height),
            $format)
        }
        finally { $brush.Dispose() }
      }
      finally { $format.Dispose() }
    }
    finally { $font.Dispose() }
  }
  finally { $g.Dispose() }
  try { Save-Png $bitmap $path } finally { $bitmap.Dispose() }
}

Save-Wordmark 600 196 $lightInk (Join-Path $assets 'brand.png')
Save-Wordmark 1200 392 $lightInk (Join-Path $assets 'brand-2x.png')
Save-Wordmark 600 196 $darkInk (Join-Path $assets 'brand-dark.png')
Save-Wordmark 1200 392 $darkInk (Join-Path $assets 'brand-dark-2x.png')

# --- uninstaller side panel ---------------------------------------------------------------------
$panel = New-Canvas 164 314
$panelBitmap = $panel[0]; $panelGraphics = $panel[1]
try {
  $panelBounds = [Drawing.RectangleF]::new(0, 0, 164, 314)
  $panelBrush = Get-GradientBrush $panelBounds
  try { $panelGraphics.FillRectangle($panelBrush, $panelBounds) } finally { $panelBrush.Dispose() }
  # The panel already carries the brand gradient, so only the glyph is drawn on it.
  $panelGlyph = New-SparklePath 82 132 52
  $panelGlyphBrush = [Drawing.SolidBrush]::new([Drawing.Color]::White)
  try { $panelGraphics.FillPath($panelGlyphBrush, $panelGlyph) }
  finally { $panelGlyphBrush.Dispose(); $panelGlyph.Dispose() }
  $panelAccent = New-SparklePath 122 96 16
  $panelAccentBrush = [Drawing.SolidBrush]::new([Drawing.Color]::FromArgb(200, 255, 255, 255))
  try { $panelGraphics.FillPath($panelAccentBrush, $panelAccent) }
  finally { $panelAccentBrush.Dispose(); $panelAccent.Dispose() }
  $panelFont = [Drawing.Font]::new('Segoe UI', [single]17, [Drawing.FontStyle]::Bold, [Drawing.GraphicsUnit]::Pixel)
  try {
    $panelFormat = [Drawing.StringFormat]::new()
    try {
      $panelFormat.Alignment = [Drawing.StringAlignment]::Center
      $panelFormat.LineAlignment = [Drawing.StringAlignment]::Center
      $panelInk = [Drawing.SolidBrush]::new([Drawing.Color]::White)
      try {
        $panelGraphics.DrawString($productName, $panelFont, $panelInk,
          [Drawing.RectangleF]::new(8, 200, 148, 80), $panelFormat)
      }
      finally { $panelInk.Dispose() }
    }
    finally { $panelFormat.Dispose() }
  }
  finally { $panelFont.Dispose() }
}
finally { $panelGraphics.Dispose() }
try { Save-Png $panelBitmap (Join-Path $assets 'uninstaller-sidebar.png') } finally { $panelBitmap.Dispose() }

Write-Output "brand assets rendered for `"$productName`""
