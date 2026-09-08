$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$source = [Drawing.Image]::FromFile((Join-Path $projectRoot 'assets/branding/app-icon.png'))
function Write-IconPng([int]$size, [string]$destination) {
    $bitmap = [Drawing.Bitmap]::new($size, $size, [Drawing.Imaging.PixelFormat]::Format24bppRgb)
    $graphics = [Drawing.Graphics]::FromImage($bitmap)
    try {
        $graphics.Clear([Drawing.Color]::FromArgb(4, 12, 40))
        $graphics.InterpolationMode = [Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $graphics.PixelOffsetMode = [Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        $graphics.DrawImage($source, [Drawing.Rectangle]::new(0, 0, $size, $size))
        $bitmap.Save($destination, [Drawing.Imaging.ImageFormat]::Png)
    } finally { $graphics.Dispose(); $bitmap.Dispose() }
}
try {
    $iosPath = Join-Path $projectRoot 'ios/Runner/Assets.xcassets/AppIcon.appiconset'
    $catalog = Get-Content -LiteralPath (Join-Path $iosPath 'Contents.json') -Raw | ConvertFrom-Json
    foreach ($entry in ($catalog.images | Sort-Object filename -Unique)) {
        $size = [int]([double]::Parse(($entry.size -split 'x')[0], [Globalization.CultureInfo]::InvariantCulture) * [int]($entry.scale -replace 'x', ''))
        Write-IconPng $size (Join-Path $iosPath $entry.filename)
    }
    foreach ($entry in @{mdpi=48; hdpi=72; xhdpi=96; xxhdpi=144; xxxhdpi=192}.GetEnumerator()) {
        Write-IconPng $entry.Value (Join-Path $projectRoot "android/app/src/main/res/mipmap-$($entry.Key)/ic_launcher.png")
    }
    Write-IconPng 512 (Join-Path $projectRoot 'assets/branding/google-play-icon.png')
    $frames = @()
    foreach ($size in @(16, 24, 32, 48, 64, 128, 256)) {
        $bitmap = [Drawing.Bitmap]::new($size, $size)
        $graphics = [Drawing.Graphics]::FromImage($bitmap)
        $stream = [IO.MemoryStream]::new()
        try {
            $graphics.InterpolationMode = [Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
            $graphics.DrawImage($source, [Drawing.Rectangle]::new(0, 0, $size, $size))
            $bitmap.Save($stream, [Drawing.Imaging.ImageFormat]::Png)
            $frames += @{ Size=$size; Bytes=$stream.ToArray() }
        } finally { $graphics.Dispose(); $bitmap.Dispose(); $stream.Dispose() }
    }
    $file = [IO.File]::Create((Join-Path $projectRoot 'windows/runner/resources/app_icon.ico'))
    $writer = [IO.BinaryWriter]::new($file)
    try {
        $writer.Write([uint16]0); $writer.Write([uint16]1); $writer.Write([uint16]$frames.Count)
        $offset = 6 + 16 * $frames.Count
        foreach ($frame in $frames) {
            $dimension = if ($frame.Size -eq 256) { 0 } else { $frame.Size }
            $writer.Write([byte]$dimension); $writer.Write([byte]$dimension)
            $writer.Write([byte]0); $writer.Write([byte]0)
            $writer.Write([uint16]1); $writer.Write([uint16]32)
            $writer.Write([uint32]$frame.Bytes.Length); $writer.Write([uint32]$offset)
            $offset += $frame.Bytes.Length
        }
        foreach ($frame in $frames) { $writer.Write([byte[]]$frame.Bytes) }
    } finally { $writer.Dispose(); $file.Dispose() }
} finally { $source.Dispose() }
Write-Output 'Updated iOS, Android, Windows and Google Play icons.'
