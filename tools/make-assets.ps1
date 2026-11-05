<#
.SYNOPSIS
    Renders KeepGreen's logo (PNG), multi-size app icon (ICO) and README banner from code.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File tools/make-assets.ps1
#>
param(
    [string]$AssetsDir = (Join-Path $PSScriptRoot '..\src\KeepGreen\Assets'),
    [string]$DocsDir = (Join-Path $PSScriptRoot '..\docs')
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

function Get-Color([int]$a, [int]$r, [int]$g, [int]$b) { [System.Drawing.Color]::FromArgb($a, $r, $g, $b) }

function New-RoundedRectPath([float]$x, [float]$y, [float]$w, [float]$h, [float]$radius) {
    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    $d = $radius * 2
    $path.AddArc($x, $y, $d, $d, 180, 90)
    $path.AddArc($x + $w - $d, $y, $d, $d, 270, 90)
    $path.AddArc($x + $w - $d, $y + $h - $d, $d, $d, 0, 90)
    $path.AddArc($x, $y + $h - $d, $d, $d, 90, 90)
    $path.CloseFigure()
    return $path
}

# The mark: a glowing "available" dot on a dark rounded tile.
function Draw-Mark([System.Drawing.Graphics]$g, [float]$x, [float]$y, [float]$s) {
    $tile = New-RoundedRectPath $x $y ($s - 1) ($s - 1) ($s * 0.23)
    $bg = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
        (New-Object System.Drawing.PointF($x, $y)),
        (New-Object System.Drawing.PointF(($x + $s), ($y + $s))),
        (Get-Color 255 18 46 35), (Get-Color 255 5 16 12))
    $g.FillPath($bg, $tile)

    $cx = $x + $s / 2
    $cy = $y + $s / 2
    foreach ($ring in @(@(0.42, 34), @(0.33, 64))) {
        $r = $s * $ring[0]
        $brush = New-Object System.Drawing.SolidBrush((Get-Color $ring[1] 34 197 94))
        $g.FillEllipse($brush, $cx - $r, $cy - $r, 2 * $r, 2 * $r)
        $brush.Dispose()
    }

    $r = $s * 0.23
    $dotRect = New-Object System.Drawing.RectangleF(($cx - $r), ($cy - $r), (2 * $r), (2 * $r))
    $dot = New-Object System.Drawing.Drawing2D.LinearGradientBrush($dotRect, (Get-Color 255 110 231 160), (Get-Color 255 22 163 74), [single]50)
    $g.FillEllipse($dot, $dotRect)

    if ($s -ge 32) {
        $shine = New-Object System.Drawing.SolidBrush((Get-Color 140 255 255 255))
        $g.FillEllipse($shine, $cx - $r * 0.62, $cy - $r * 0.66, $r * 0.5, $r * 0.36)
        $shine.Dispose()
    }

    $bg.Dispose(); $dot.Dispose(); $tile.Dispose()
}

function New-Canvas([int]$width, [int]$height) {
    $bitmap = New-Object System.Drawing.Bitmap($width, $height, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($bitmap)
    $g.SmoothingMode = 'AntiAlias'
    $g.InterpolationMode = 'HighQualityBicubic'
    $g.PixelOffsetMode = 'HighQuality'
    $g.TextRenderingHint = 'AntiAliasGridFit'
    $g.Clear([System.Drawing.Color]::Transparent)
    return @($bitmap, $g)
}

function Get-PngBytes([System.Drawing.Bitmap]$bitmap) {
    $stream = New-Object System.IO.MemoryStream
    $bitmap.Save($stream, [System.Drawing.Imaging.ImageFormat]::Png)
    $bytes = $stream.ToArray()
    $stream.Dispose()
    return , $bytes
}

New-Item -ItemType Directory -Force -Path $AssetsDir, $DocsDir | Out-Null

# Logo PNG (used inside the app and the README).
$bitmap, $g = New-Canvas 256 256
Draw-Mark $g 0 0 256
$g.Dispose()
$bitmap.Save((Join-Path $AssetsDir 'logo.png'), [System.Drawing.Imaging.ImageFormat]::Png)
$bitmap.Dispose()

# Multi-size ICO with PNG frames (Windows Vista and later).
$sizes = 16, 20, 24, 32, 40, 48, 64, 128, 256
$frames = New-Object 'System.Collections.Generic.List[byte[]]'
foreach ($size in $sizes) {
    $bitmap, $g = New-Canvas $size $size
    Draw-Mark $g 0 0 $size
    $g.Dispose()
    $frames.Add((Get-PngBytes $bitmap))
    $bitmap.Dispose()
}

$file = [System.IO.File]::Create((Join-Path $AssetsDir 'KeepGreen.ico'))
$writer = New-Object System.IO.BinaryWriter($file)
$writer.Write([UInt16]0); $writer.Write([UInt16]1); $writer.Write([UInt16]$sizes.Count)
$offset = 6 + 16 * $sizes.Count
for ($i = 0; $i -lt $sizes.Count; $i++) {
    $dimension = if ($sizes[$i] -ge 256) { 0 } else { $sizes[$i] }
    $writer.Write([byte]$dimension); $writer.Write([byte]$dimension)
    $writer.Write([byte]0); $writer.Write([byte]0)
    $writer.Write([UInt16]1); $writer.Write([UInt16]32)
    $writer.Write([UInt32]$frames[$i].Length); $writer.Write([UInt32]$offset)
    $offset += $frames[$i].Length
}
foreach ($frame in $frames) { $writer.Write($frame) }
$writer.Dispose(); $file.Dispose()

# README banner.
$bitmap, $g = New-Canvas 1280 400
$background = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
    (New-Object System.Drawing.Point(0, 0)), (New-Object System.Drawing.Point(1280, 400)),
    (Get-Color 255 4 14 11), (Get-Color 255 14 42 31))
$g.FillRectangle($background, 0, 0, 1280, 400)
$glow = New-Object System.Drawing.SolidBrush((Get-Color 26 34 197 94))
$g.FillEllipse($glow, 40, -60, 520, 520)
Draw-Mark $g 110 80 240

$titleFont = New-Object System.Drawing.Font('Segoe UI Semibold', 72, [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Pixel)
$tagFont = New-Object System.Drawing.Font('Segoe UI', 30, [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Pixel)
$pillFont = New-Object System.Drawing.Font('Segoe UI Semibold', 20, [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Pixel)
$white = New-Object System.Drawing.SolidBrush((Get-Color 255 255 255 255))
$mint = New-Object System.Drawing.SolidBrush((Get-Color 255 167 243 208))
$g.DrawString('KeepGreen', $titleFont, $white, 420, 104)
$g.DrawString('Stay available on your schedule, automatically.', $tagFont, $mint, 424, 196)

# [char] keeps the script ASCII, so Windows PowerShell 5.1 reads it correctly without a BOM.
$pillText = 'Windows 10 & 11  ' + [char]0x00B7 + '  Free & open source'
$pillSize = $g.MeasureString($pillText, $pillFont)
$pill = New-RoundedRectPath 424 262 ($pillSize.Width + 36) 44 22
$pillBrush = New-Object System.Drawing.SolidBrush((Get-Color 40 34 197 94))
$pillPen = New-Object System.Drawing.Pen((Get-Color 120 34 197 94), 1.5)
$g.FillPath($pillBrush, $pill)
$g.DrawPath($pillPen, $pill)
$g.DrawString($pillText, $pillFont, $mint, 442, 271)

$g.Dispose()
$bitmap.Save((Join-Path $DocsDir 'banner.png'), [System.Drawing.Imaging.ImageFormat]::Png)
$bitmap.Dispose()

Write-Host "Wrote logo.png, KeepGreen.ico and docs/banner.png"
