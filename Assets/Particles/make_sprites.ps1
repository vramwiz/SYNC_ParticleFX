param()

# 配布へ埋め込む256pxのイラストを事前生成する。実行時の画像生成には使用しない。
# 背景透過・1素材1画像とし、形のバリエーションを自動で増やさない。
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

function New-Brush([string]$Color) {
    return [Drawing.SolidBrush]::new([Drawing.ColorTranslator]::FromHtml($Color))
}

function Save-Sprite([string]$Name, [scriptblock]$Draw) {
    # 大きい作業面から縮小し、透過輪郭のアンチエイリアスを保存する。
    $canvas = [Drawing.Bitmap]::new(1024, 1024, [Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $graphics = [Drawing.Graphics]::FromImage($canvas)
    $output = [Drawing.Bitmap]::new(256, 256, [Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $resizer = [Drawing.Graphics]::FromImage($output)
    try {
        $graphics.Clear([Drawing.Color]::Transparent)
        $graphics.SmoothingMode = [Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $graphics.ScaleTransform(4, 4)
        & $Draw $graphics
        $resizer.CompositingMode = [Drawing.Drawing2D.CompositingMode]::SourceCopy
        $resizer.InterpolationMode = [Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $resizer.PixelOffsetMode = [Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        $resizer.DrawImage($canvas, [Drawing.Rectangle]::new(0, 0, 256, 256), 0, 0, 1024, 1024, [Drawing.GraphicsUnit]::Pixel)
        $output.Save((Join-Path $PSScriptRoot $Name), [Drawing.Imaging.ImageFormat]::Png)
        Write-Output (Join-Path $PSScriptRoot $Name)
    }
    finally {
        $resizer.Dispose(); $output.Dispose(); $graphics.Dispose(); $canvas.Dispose()
    }
}

Save-Sprite 'sakura_petal.png' {
    param($g)
    $outline = [Drawing.Drawing2D.GraphicsPath]::new()
    $shade = [Drawing.Drawing2D.GraphicsPath]::new()
    $body = New-Brush '#F7B6CE'
    $shadow = New-Brush '#E68BAD'
    $light = New-Brush '#FFD8E5'
    try {
        # 上端の切れ込みと下端の細い付け根を、回転しても読める輪郭にする。
        $outline.StartFigure()
        $outline.AddBezier(128, 67, 113, 47, 107, 24, 86, 27)
        $outline.AddBezier(86, 27, 39, 35, 32, 100, 49, 143)
        $outline.AddBezier(49, 143, 63, 181, 105, 207, 128, 232)
        $outline.AddBezier(128, 232, 152, 207, 195, 179, 208, 140)
        $outline.AddBezier(208, 140, 222, 96, 212, 37, 169, 27)
        $outline.AddBezier(169, 27, 149, 23, 141, 47, 128, 67)
        $outline.CloseFigure()
        $g.FillPath($body, $outline)
        $g.SetClip($outline)
        $shade.StartFigure()
        $shade.AddBezier(128, 232, 138, 170, 192, 150, 208, 86)
        $shade.AddBezier(208, 86, 238, 176, 168, 220, 128, 232)
        $shade.CloseFigure()
        $g.FillPath($shadow, $shade)
        $g.FillEllipse($light, 61, 52, 29, 54)
        $g.ResetClip()
    }
    finally {
        $light.Dispose(); $shadow.Dispose(); $body.Dispose(); $shade.Dispose(); $outline.Dispose()
    }
}

Save-Sprite 'autumn_leaf.png' {
    param($g)
    $outline = [Drawing.Drawing2D.GraphicsPath]::new()
    $shade = [Drawing.Drawing2D.GraphicsPath]::new()
    $body = New-Brush '#D98A3F'
    $shadow = New-Brush '#B86131'
    $vein = [Drawing.Pen]::new([Drawing.ColorTranslator]::FromHtml('#F5C16B'), 3)
    $stem = [Drawing.Pen]::new([Drawing.ColorTranslator]::FromHtml('#96542F'), 5)
    try {
        $vein.StartCap = $vein.EndCap = [Drawing.Drawing2D.LineCap]::Round
        $stem.StartCap = $stem.EndCap = [Drawing.Drawing2D.LineCap]::Round
        $points = [Drawing.PointF[]]@(
            [Drawing.PointF]::new(128, 19), [Drawing.PointF]::new(111, 49),
            [Drawing.PointF]::new(96, 43), [Drawing.PointF]::new(91, 68),
            [Drawing.PointF]::new(74, 65), [Drawing.PointF]::new(75, 90),
            [Drawing.PointF]::new(57, 94), [Drawing.PointF]::new(65, 117),
            [Drawing.PointF]::new(49, 128), [Drawing.PointF]::new(65, 145),
            [Drawing.PointF]::new(57, 162), [Drawing.PointF]::new(78, 172),
            [Drawing.PointF]::new(78, 190), [Drawing.PointF]::new(101, 193),
            [Drawing.PointF]::new(128, 215), [Drawing.PointF]::new(153, 196),
            [Drawing.PointF]::new(176, 190), [Drawing.PointF]::new(177, 173),
            [Drawing.PointF]::new(199, 163), [Drawing.PointF]::new(191, 145),
            [Drawing.PointF]::new(207, 128), [Drawing.PointF]::new(191, 117),
            [Drawing.PointF]::new(199, 94), [Drawing.PointF]::new(181, 90),
            [Drawing.PointF]::new(182, 65), [Drawing.PointF]::new(165, 68),
            [Drawing.PointF]::new(160, 43), [Drawing.PointF]::new(145, 49)
        )
        $outline.AddPolygon($points)
        $g.DrawBezier($stem, 128, 203, 128, 219, 133, 230, 127, 239)
        $g.FillPath($body, $outline)
        $g.SetClip($outline)
        $shade.AddBezier(128, 19, 118, 90, 139, 160, 128, 215)
        $shade.AddLine(128, 215, 224, 207)
        $shade.AddLine(224, 207, 224, 18)
        $shade.CloseFigure()
        $g.FillPath($shadow, $shade)
        $g.DrawBezier($vein, 128, 35, 120, 104, 134, 162, 128, 211)
        foreach ($branch in @(@(126, 89, 96, 67), @(126, 118, 78, 94),
            @(128, 148, 75, 128), @(130, 178, 88, 165),
            @(126, 89, 157, 66), @(126, 118, 177, 94),
            @(128, 148, 180, 128), @(130, 178, 170, 165))) {
            $g.DrawLine($vein, $branch[0], $branch[1], $branch[2], $branch[3])
        }
        $g.ResetClip()
    }
    finally {
        $stem.Dispose(); $vein.Dispose(); $shadow.Dispose(); $body.Dispose(); $shade.Dispose(); $outline.Dispose()
    }
}
