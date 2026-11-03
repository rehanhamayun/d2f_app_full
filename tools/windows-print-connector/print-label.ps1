param([Parameter(Mandatory=$true)][string]$InputPath)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$job = Get-Content -LiteralPath $InputPath -Raw | ConvertFrom-Json
$image = [System.Drawing.Image]::FromFile($job.image)
$document = New-Object System.Drawing.Printing.PrintDocument
try {
  $document.PrinterSettings.PrinterName = $job.printer
  if (-not $document.PrinterSettings.IsValid) { throw 'Printer queue is invalid.' }
  $document.PrinterSettings.Copies = 1
  $document.DocumentName = 'D2F ' + $job.job
  $document.DefaultPageSettings.PaperSize = New-Object System.Drawing.Printing.PaperSize('D2F 4x6', 400, 600)
  $document.DefaultPageSettings.Margins = New-Object System.Drawing.Printing.Margins(0, 0, 0, 0)
  $document.DefaultPageSettings.Landscape = $false
  $document.PrintController = New-Object System.Drawing.Printing.StandardPrintController
  $document.add_PrintPage({
    param($sender, $e)
    $e.Graphics.TranslateTransform(-$e.PageSettings.HardMarginX, -$e.PageSettings.HardMarginY)
    $e.Graphics.DrawImage($image, [System.Drawing.RectangleF]::new(0, 0, 400, 600))
    $e.HasMorePages = $false
  })
  $document.Print()
} finally {
  $document.Dispose()
  $image.Dispose()
}
