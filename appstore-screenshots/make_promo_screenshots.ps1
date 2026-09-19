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

function MakePromo($source,$destination,[int]$w,[int]$h,[string]$index,[string]$section,[string]$headline,[string]$subhead) {
  $bg = [System.Drawing.Image]::FromFile($bgPath)
  $canvas = New-Object System.Drawing.Bitmap($w,$h,[System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
  $g = [System.Drawing.Graphics]::FromImage($canvas)
  $g.SmoothingMode = 'HighQuality'; $g.InterpolationMode = 'HighQualityBicubic'; $g.PixelOffsetMode = 'HighQuality'
  $g.DrawImage($bg,0,0,$w,$h); $bg.Dispose()
  $veil = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(112,5,8,25)); $g.FillRectangle($veil,0,0,$w,$h); $veil.Dispose()
  $m = [int]($w*0.09)
  $cyan = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(255,90,230,235)); $muted = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(255,180,192,220)); $white = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::White)
  $pen = [System.Drawing.Pen]::new([System.Drawing.Color]::FromArgb(150,90,230,235),[Math]::Max(2,[int]($w/500)))
  $small = [System.Drawing.Font]::new('Segoe UI Semibold',[Math]::Max(18,[int]($w/38))); $title = [System.Drawing.Font]::new('Segoe UI Semibold',[Math]::Max(42,[int]($w/15)),[System.Drawing.FontStyle]::Bold); $sub = [System.Drawing.Font]::new('Segoe UI',[Math]::Max(22,[int]($w/34)))
  $g.DrawString("$index  /  $section",$small,$cyan,$m,[int]($h*0.075)); $g.DrawLine($pen,$m,[int]($h*0.11),$w-$m,[int]($h*0.11))
  $y = WrappedText $g $headline $title $white ([System.Drawing.RectangleF]::new($m,[int]($h*0.14),$w-2*$m,[int]($h*0.20)))
  [void](WrappedText $g $subhead $sub $muted ([System.Drawing.RectangleF]::new($m,$y+10,$w-2*$m,[int]($h*0.10))))
  $src = [System.Drawing.Image]::FromFile($source)
  if ($w -eq 1242) { $dw=[int]($w*0.62); $dy=[int]($h*0.34); $radius=48 } else { $dw=[int]($w*0.63); $dy=[int]($h*0.335); $radius=62 }
  $dh=[int]($dw*($src.Height/$src.Width)); $dx=[int](($w-$dw)/2)
  $shadow = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(170,0,0,0)); $sp=RoundedPath ($dx+14) ($dy+20) $dw $dh $radius; $g.FillPath($shadow,$sp); $sp.Dispose(); $shadow.Dispose()
  $frame = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255,8,12,24)); $fp=RoundedPath $dx $dy $dw $dh $radius; $g.FillPath($frame,$fp); $fp.Dispose(); $frame.Dispose()
  $clip=RoundedPath ($dx+8) ($dy+8) ($dw-16) ($dh-16) ($radius-8); $g.SetClip($clip); $g.DrawImage($src,$dx+8,$dy+8,$dw-16,$dh-16); $g.ResetClip(); $clip.Dispose(); $src.Dispose()
  $footer=[System.Drawing.Font]::new('Segoe UI Semibold',[Math]::Max(17,[int]($w/52))); $g.DrawString('NEXT EPISODE TRACKER',$footer,$muted,$m,$h-[int]($h*0.045))
  $cyan.Dispose(); $muted.Dispose(); $white.Dispose(); $pen.Dispose(); $small.Dispose(); $title.Dispose(); $sub.Dispose(); $footer.Dispose(); $g.Dispose(); $canvas.Save($destination,[System.Drawing.Imaging.ImageFormat]::Jpeg); $canvas.Dispose()
}

$iphoneSrc=Join-Path $root 'iphone-6.5'; $ipadSrc=Join-Path $root 'ipad-13'
$iphoneOut=Join-Path $root 'promo-iphone'; $ipadOut=Join-Path $root 'promo-ipad'
$items=@(
  @('01','LIBRARY','Your library, at a glance','Keep every show and movie organized.','1.jpg','01-library.jpg'),
  @('02','DETAILS','Explore every detail','Episode descriptions, ratings and cast in one place.','2.jpg','02-details.jpg'),
  @('03','EPISODES','Never lose your place','Track seasons, episodes and progress in one view.','3.jpg','03-episodes.jpg'),
  @('04','DISCOVER','Discover something great','Search shows and movies and build your next watchlist.','4.jpg','04-discover.jpg'),
  @('05','WATCH LIST','Know what to watch next','Your unwatched episodes, always within reach.','5.jpg','05-watchlist.jpg'),
  @('06','CALENDAR','See what is coming','Your upcoming episodes on a clear calendar.','6.jpg','06-calendar.jpg'))
foreach($i in $items){ MakePromo (Join-Path $iphoneSrc $i[4]) (Join-Path $iphoneOut ('art-'+$i[5])) 1242 2688 $i[0] $i[1] $i[2] $i[3] }
$ipadItems=@(
  @('01','LIBRARY','Your library, at a glance','Keep every show and movie organized.','11.jpg','01-library.jpg'),
  @('02','WATCH LIST','Know what to watch next','Your unwatched episodes, always within reach.','22.jpg','02-watchlist.jpg'),
  @('03','DETAILS','Explore every detail','Episode descriptions, ratings and cast in one place.','33.jpg','03-details.jpg'),
  @('04','EPISODES','Never lose your place','Track seasons, episodes and progress in one view.','44.jpg','04-episodes.jpg'),
  @('05','DISCOVER','Discover something great','Search shows and movies and build your next watchlist.','55.jpg','05-discover.jpg'),
  @('06','CALENDAR','See what is coming','Your upcoming episodes on a clear calendar.','66.jpg','06-calendar.jpg'))
foreach($i in $ipadItems){ MakePromo (Join-Path $ipadSrc $i[4]) (Join-Path $ipadOut ('art-'+$i[5])) 2064 2752 $i[0] $i[1] $i[2] $i[3] }
