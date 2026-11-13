param([string]$PreviewDirectory, [switch]$StartupOnly)

# 実験出力の透過PNGを市松模様へ重ね、目視確認用の一覧を作る。
$ErrorActionPreference = 'Stop'
if (-not $PreviewDirectory) { $PreviewDirectory = Join-Path $PSScriptRoot '..\Win64\Experiment\Preview' }
Add-Type -AssemblyName System.Drawing
$files = @(Get-ChildItem -LiteralPath $PreviewDirectory -Filter '*.png' -File |
    Where-Object Name -notin @('contact_sheet.png', 'startup_state.png') | Sort-Object Name)
if ($StartupOnly) {
    $files = @(foreach ($kind in @('rain', 'snow', 'slime')) {
        foreach ($state in @(0, 50, 100)) {
            Get-Item -LiteralPath (Join-Path $PreviewDirectory ('startup_{0}_{1:D3}.png' -f $kind, $state))
        }
    })
}
$tileWidth = 400
$tileHeight = 225
if ($StartupOnly) { $tileWidth = 320; $tileHeight = 180 }
$headerHeight = 28
$gap = 12
$columns = 3
$rows = [int][Math]::Ceiling($files.Count / $columns)
$sheet = [Drawing.Bitmap]::new($gap + $columns * ($tileWidth + $gap), $gap + $rows * ($tileHeight + $headerHeight + $gap))
$graphics = [Drawing.Graphics]::FromImage($sheet)
$font = [Drawing.Font]::new('Consolas', 11)
$textBrush = [Drawing.SolidBrush]::new([Drawing.ColorTranslator]::FromHtml('#DFEDF5'))
$brushes = @([Drawing.SolidBrush]::new([Drawing.Color]::FromArgb(31,43,61)), [Drawing.SolidBrush]::new([Drawing.Color]::FromArgb(41,54,73)))
try {
    $graphics.Clear([Drawing.ColorTranslator]::FromHtml('#101B2B'))
    $graphics.InterpolationMode = [Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    for ($index = 0; $index -lt $files.Count; $index++) {
        $originX = $gap + ($index % $columns) * ($tileWidth + $gap)
        $originY = $gap + [Math]::Floor($index / $columns) * ($tileHeight + $headerHeight + $gap)
        $graphics.DrawString($files[$index].BaseName, $font, $textBrush, [single]($originX + 2), [single]($originY + 4))
        for ($y = 0; $y -lt $tileHeight; $y += 15) {
            for ($x = 0; $x -lt $tileWidth; $x += 16) {
                $brushIndex = ([int]($x / 16) + [int]($y / 15)) % 2
                $graphics.FillRectangle($brushes[$brushIndex], [int]($originX + $x), [int]($originY + $headerHeight + $y), 16, 15)
            }
        }
        $sourceImage = [Drawing.Image]::FromFile($files[$index].FullName)
        try { $graphics.DrawImage($sourceImage, [int]$originX, [int]($originY + $headerHeight), $tileWidth, $tileHeight) }
        finally { $sourceImage.Dispose() }
    }
    $outputName = 'contact_sheet.png'
    if ($StartupOnly) { $outputName = 'startup_state.png' }
    $outputPath = Join-Path $PreviewDirectory $outputName
    $sheet.Save($outputPath, [Drawing.Imaging.ImageFormat]::Png)
    Write-Output ([IO.Path]::GetFullPath($outputPath))
}
finally {
    foreach ($brush in $brushes) { $brush.Dispose() }
    $textBrush.Dispose()
    $font.Dispose()
    $graphics.Dispose()
    $sheet.Dispose()
}
