param([string]$SourcePath,[string]$Destination,[int]$Cells=4,[switch]$Item,[switch]$Pumpkin,[int]$Width=128,[int]$Height=64)
Add-Type -AssemblyName System.Drawing
$src=[System.Drawing.Bitmap]::new($SourcePath)

if($Item){$height=64;$Width=64;$Cells=1}
$dst=[System.Drawing.Bitmap]::new($Width,$height,[System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$g=[System.Drawing.Graphics]::FromImage($dst)
$g.InterpolationMode=[System.Drawing.Drawing2D.InterpolationMode]::NearestNeighbor
$g.PixelOffsetMode=[System.Drawing.Drawing2D.PixelOffsetMode]::Half
$g.CompositingMode=[System.Drawing.Drawing2D.CompositingMode]::SourceCopy
$boxes=@()
for($i=0;$i -lt $Cells;$i++){
 $left=[int]($i*$src.Width/$Cells);$right=[int](($i+1)*$src.Width/$Cells)
 if($Pumpkin){$cuts=@(0,0.186,0.372,0.643,1);$left=[int]($cuts[$i]*$src.Width);$right=[int]($cuts[$i+1]*$src.Width)}
 $x0=$right;$x1=$left;$y0=$src.Height;$y1=0
 for($y=0;$y -lt $src.Height;$y++){for($x=$left;$x -lt $right;$x++){if($src.GetPixel($x,$y).A -gt 128){$x0=[Math]::Min($x0,$x);$x1=[Math]::Max($x1,$x);$y0=[Math]::Min($y0,$y);$y1=[Math]::Max($y1,$y)}}}
 $boxes+=,[System.Drawing.Rectangle]::new($x0,$y0,$x1-$x0+1,$y1-$y0+1)
}
$scale=100.0
foreach($b in $boxes){$scale=[Math]::Min($scale,[Math]::Min(($Width/$Cells-2)/$b.Width,($height-2)/$b.Height))}
for($i=0;$i -lt $Cells;$i++){
 $b=$boxes[$i];$w=[Math]::Max(1,[int]($b.Width*$scale));$h=[Math]::Max(1,[int]($b.Height*$scale))
 $x=[int]($i*$Width/$Cells+($Width/$Cells-$w)/2);$y=$height-1-$h
 $g.DrawImage($src,[System.Drawing.Rectangle]::new($x,$y,$w,$h),$b,[System.Drawing.GraphicsUnit]::Pixel)
}
$g.Dispose();$src.Dispose();$dst.Save($Destination,[System.Drawing.Imaging.ImageFormat]::Png);$dst.Dispose()

