$root = 'E:\WORK\Next-Episode\appstore-screenshots'
$bgPath = Join-Path $root 'promo-background.png'
Add-Type -AssemblyName System.Drawing

function RoundedPath([float]$x,[float]$y,[float]$w,[float]$h,[float]$r) {
  $p = New-Object System.Drawing.Drawing2D.GraphicsPath
  $d = $r * 2
  $p.AddArc($x,$y,$d,$d,180,90); $p.AddArc($x+$w-$d,$y,$d,$d,270,90)
  $p.AddArc($x+$w-$d,$y+$h-$d,$d,$d,0,90); $p.AddArc($x,$y+$h-$d,$d,$d,90,90)
  $p.CloseFigure(); return $p
}

function WrappedText($g,[string]$text,$font,$brush,[System.Drawing.RectangleF]$rect) {
  $lines = New-Object System.Collections.Generic.List[string]; $line = ''
  foreach ($word in $text.Split(' ')) {
    $candidate = if ($line) { "$line $word" } else { $word }
    if ($g.MeasureString($candidate,$font).Width -le $rect.Width) { $line = $candidate }
    else { if ($line) { $lines.Add($line) }; $line = $word }
  }
  if ($line) { $lines.Add($line) }
  $y = $rect.Y; $lh = $font.GetHeight($g) * 1.08
  foreach ($l in $lines) { $g.DrawString($l,$font,$brush,$rect.X,$y); $y += $lh }
  return $y
}

function DrawDevice($g,$src,[int]$canvasW,[int]$canvasH,[int]$deviceY,[bool]$isIphone) {
  # Reserve the lower part of the canvas for the device, so it can never cover the copy.
  $regionBottom = [int]($canvasH * 0.945)
  $bezel = if ($isIphone) { [int]($canvasW * 0.014) } else { [int]($canvasW * 0.018) }
  $maxHeight = $regionBottom - $deviceY
  $aspect = $src.Width / [double]$src.Height
  $heightRatio = 0.56
  if ($isIphone) { $heightRatio = 0.585 }
  $outerH = [int]([Math]::Min($maxHeight, $canvasH * $heightRatio))
  $outerW = [int]($outerH * $aspect + (2 * $bezel))
  $widthRatio = 0.76
  if ($isIphone) { $widthRatio = 0.66 }
  $maxW = [int]($canvasW * $widthRatio)
  if ($outerW -gt $maxW) {
    $outerW = $maxW
    $outerH = [int](($outerW - (2 * $bezel)) / $aspect)
  }
  $deviceX = [int](($canvasW - $outerW) / 2)
  $radius = if ($isIphone) { [int]($outerW * 0.14) } else { [int]($outerW * 0.07) }

  $shadow = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(190,0,0,0))
  $shadowPath = RoundedPath ($deviceX+18) ($deviceY+26) $outerW $outerH $radius
  $g.FillPath($shadow,$shadowPath); $shadowPath.Dispose(); $shadow.Dispose()

  $body = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255,7,10,18))
  $bodyPath = RoundedPath $deviceX $deviceY $outerW $outerH $radius
  $g.FillPath($body,$bodyPath)
  $border = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(185,105,123,168),[Math]::Max(2,[int]($canvasW/430)))
  $g.DrawPath($border,$bodyPath)
  $bodyPath.Dispose(); $body.Dispose(); $border.Dispose()

  $innerX = $deviceX + $bezel; $innerY = $deviceY + $bezel
  $innerW = $outerW - 2*$bezel; $innerH = $outerH - 2*$bezel
  $innerRadius = [Math]::Max(8,$radius-$bezel)
  $clip = RoundedPath $innerX $innerY $innerW $innerH $innerRadius
  $g.SetClip($clip); $g.DrawImage($src,$innerX,$innerY,$innerW,$innerH); $g.ResetClip(); $clip.Dispose()

  # A simple hardware treatment makes the frame read as a device while leaving the screenshot pixel-perfect.
  $hardware = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(230,2,3,7))
  if ($isIphone) {
    $pillW = [int]($outerW*0.25); $pillH = [int]($bezel*0.82)
    $pillX = $deviceX + [int](($outerW-$pillW)/2); $pillY = $deviceY + [int]($bezel*0.28)
    $pill = RoundedPath $pillX $pillY $pillW $pillH ([int]($pillH/2)); $g.FillPath($hardware,$pill); $pill.Dispose()
    $buttonW = [int]($canvasW*0.012); $buttonH = [int]($canvasH*0.075)
    $bp = RoundedPath ($deviceX+$outerW-2) ($deviceY+[int]($outerH*0.28)) $buttonW $buttonH 5; $g.FillPath($hardware,$bp); $bp.Dispose()
  } else {
    $dot = [int]($bezel*0.28); $cx = $deviceX + [int]($outerW/2); $cy = $deviceY + [int]($bezel*0.52)
    $g.FillEllipse($hardware,$cx-$dot,$cy-$dot,$dot*2,$dot*2)
  }
  $hardware.Dispose()
  return ($deviceY + $outerH)
}

function MakeFramedPromo($source,$destination,[int]$w,[int]$h,[string]$index,[string]$section,[string]$headline,[string]$subhead,[bool]$isIphone) {
  $bg = [System.Drawing.Image]::FromFile($bgPath)
  $canvas = New-Object System.Drawing.Bitmap($w,$h,[System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
  $g = [System.Drawing.Graphics]::FromImage($canvas)
  $g.SmoothingMode = 'HighQuality'; $g.InterpolationMode = 'HighQualityBicubic'; $g.PixelOffsetMode = 'HighQuality'
  $g.DrawImage($bg,0,0,$w,$h); $bg.Dispose()
  $veil = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(120,4,7,20)); $g.FillRectangle($veil,0,0,$w,$h); $veil.Dispose()

  $m = [int]($w*0.09)
  $cyan = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255,90,230,235))
  $muted = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255,185,196,220))
  $white = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::White)
  $rule = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(170,90,230,235),[Math]::Max(2,[int]($w/500)))
  $small = New-Object System.Drawing.Font('Segoe UI Semibold',[Math]::Max(18,[int]($w/38)))
  $title = New-Object System.Drawing.Font('Segoe UI Semibold',[Math]::Max(42,[int]($w/15)),[System.Drawing.FontStyle]::Bold)
  $sub = New-Object System.Drawing.Font('Segoe UI',[Math]::Max(22,[int]($w/34)))
  $g.DrawString("$index  /  $section",$small,$cyan,$m,[int]($h*0.075))
  $g.DrawLine($rule,$m,[int]($h*0.11),$w-$m,[int]($h*0.11))
  $titleBottom = WrappedText $g $headline $title $white ([System.Drawing.RectangleF]::new($m,[int]($h*0.14),$w-2*$m,[int]($h*0.17)))
  $subBottom = WrappedText $g $subhead $sub $muted ([System.Drawing.RectangleF]::new($m,$titleBottom+12,$w-2*$m,[int]($h*0.10)))
  $deviceY = [int]([Math]::Max($h*0.39, $subBottom + $h*0.035))
  $src = [System.Drawing.Image]::FromFile($source)
  [void](DrawDevice $g $src $w $h $deviceY $isIphone)
  $src.Dispose()
  $footer = New-Object System.Drawing.Font('Segoe UI Semibold',[Math]::Max(17,[int]($w/52)))
  $g.DrawString('NEXT EPISODE TRACKER',$footer,$muted,$m,$h-[int]($h*0.036))
  $cyan.Dispose(); $muted.Dispose(); $white.Dispose(); $rule.Dispose(); $small.Dispose(); $title.Dispose(); $sub.Dispose(); $footer.Dispose(); $g.Dispose()
  $canvas.Save($destination,[System.Drawing.Imaging.ImageFormat]::Jpeg); $canvas.Dispose()
}

$iphoneSrc=Join-Path $root 'iphone-6.5'; $ipadSrc=Join-Path $root 'ipad-13'
$iphoneOut=Join-Path $root 'promo-iphone-framed'; $ipadOut=Join-Path $root 'promo-ipad-framed'
New-Item -ItemType Directory -Force -Path $iphoneOut,$ipadOut | Out-Null
$iphoneItems=@(
  @('01','LIBRARY','Your library, at a glance','Keep every show and movie organized.','1.jpg','01-library.jpg'),
  @('02','DETAILS','Explore every detail','Episode descriptions, ratings and cast in one place.','2.jpg','02-details.jpg'),
  @('03','EPISODES','Never lose your place','Track seasons, episodes and progress in one view.','3.jpg','03-episodes.jpg'),
  @('04','DISCOVER','Discover something great','Search shows and movies and build your next watchlist.','4.jpg','04-discover.jpg'),
  @('05','WATCH LIST','Know what to watch next','Your unwatched episodes, always within reach.','5.jpg','05-watchlist.jpg'),
  @('06','CALENDAR','See what is coming','Your upcoming episodes on a clear calendar.','6.jpg','06-calendar.jpg'))
foreach($i in $iphoneItems){ MakeFramedPromo (Join-Path $iphoneSrc $i[4]) (Join-Path $iphoneOut ('art-'+$i[5])) 1242 2688 $i[0] $i[1] $i[2] $i[3] $true }
$ipadItems=@(
  @('01','LIBRARY','Your library, at a glance','Keep every show and movie organized.','11.jpg','01-library.jpg'),
  @('02','WATCH LIST','Know what to watch next','Your unwatched episodes, always within reach.','22.jpg','02-watchlist.jpg'),
  @('03','DETAILS','Explore every detail','Episode descriptions, ratings and cast in one place.','33.jpg','03-details.jpg'),
  @('04','EPISODES','Never lose your place','Track seasons, episodes and progress in one view.','44.jpg','04-episodes.jpg'),
  @('05','DISCOVER','Discover something great','Search shows and movies and build your next watchlist.','55.jpg','05-discover.jpg'),
  @('06','CALENDAR','See what is coming','Your upcoming episodes on a clear calendar.','66.jpg','06-calendar.jpg'))
foreach($i in $ipadItems){ MakeFramedPromo (Join-Path $ipadSrc $i[4]) (Join-Path $ipadOut ('art-'+$i[5])) 2064 2752 $i[0] $i[1] $i[2] $i[3] $false }
