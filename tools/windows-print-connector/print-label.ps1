param([Parameter(Mandatory=$true)][string]$InputPath)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$job = Get-Content -LiteralPath $InputPath -Raw | ConvertFrom-Json
$image = [System.Drawing.Image]::FromFile($job.image)
$document = New-Object System.Drawing.Printing.PrintDocument
try {
  $document.PrinterSettings.PrinterName = $job.printer
  if (-not $document.PrinterSettings.IsValid) { exit 20 }
  $queue = Get-Printer | Where-Object Name -CEQ $job.printer | Select-Object -First 1
  if ($queue -and $queue.PrinterStatus -match 'Offline|Paused|NotAvailable|PaperOut') { exit 21 }
  $document.PrinterSettings.Copies = 1
  $document.DocumentName = 'D2F ' + $job.job
  $roll = $document.PrinterSettings.PaperSizes | Where-Object {
    [Math]::Abs($_.Width - 400) -le 10 -and [Math]::Abs($_.Height - 600) -le 10
  } | Select-Object -First 1
  if (-not $roll) { exit 22 }
  $document.DefaultPageSettings.PaperSize = $roll
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
