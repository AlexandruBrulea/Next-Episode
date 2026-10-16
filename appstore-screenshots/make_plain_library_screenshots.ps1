# Plain screenshots: preserve the supplied UI, with no device frame or copy.
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

function ExportPlainScreenshot([string]$source, [string]$destination, [int]$width, [int]$height) {
  $capture = [System.Drawing.Bitmap]::FromFile($source)
  $canvas = New-Object System.Drawing.Bitmap($width, $height, [System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
  $graphics = [System.Drawing.Graphics]::FromImage($canvas)
  try {
    # Letterbox mismatched aspect ratios rather than distort or crop the UI.
    $graphics.Clear($capture.GetPixel(0, 0))
    $graphics.InterpolationMode = 'HighQualityBicubic'
    $graphics.PixelOffsetMode = 'HighQuality'
    $scale = [Math]::Min($width / [double]$capture.Width, $height / [double]$capture.Height)
    $drawWidth = [int][Math]::Round($capture.Width * $scale)
    $drawHeight = [int][Math]::Round($capture.Height * $scale)
    $x = [int](($width - $drawWidth) / 2)
    $y = [int](($height - $drawHeight) / 2)
    $graphics.DrawImage($capture, $x, $y, $drawWidth, $drawHeight)
    $encoder = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object MimeType -eq 'image/jpeg'
    $parameters = New-Object System.Drawing.Imaging.EncoderParameters(1)
    try {
      $parameters.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter([System.Drawing.Imaging.Encoder]::Quality, [long]95)
      $canvas.Save($destination, $encoder, $parameters)
    } finally { $parameters.Dispose() }
  } finally {
    $graphics.Dispose()
    $canvas.Dispose()
    $capture.Dispose()
  }
}

ExportPlainScreenshot (Join-Path $PSScriptRoot 'sources-2026-10-16/iphone-library.png') (Join-Path $PSScriptRoot 'iphone-6.5/01-library-v2.jpg') 1242 2688
ExportPlainScreenshot (Join-Path $PSScriptRoot 'sources-2026-10-16/ipad-library.png') (Join-Path $PSScriptRoot 'ipad-13/01-library-v2.jpg') 2064 2752
