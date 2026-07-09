# doc_convert.ps1
# 旧格式文档转换器: .doc → .docx / .txt
# 用法: powershell -NoProfile -File tools/doc_convert.ps1 -Input "file.doc" [-Output "file.docx"] [-Format docx|txt]
# 依赖: Microsoft Word (COM)

param(
  [Parameter(Mandatory)] [string]$Input,
  [string]$Output,
  [ValidateSet("docx","txt")] [string]$Format = "docx"
)

$ErrorActionPreference = "Stop"

# Resolve input path
$inputPath = Resolve-Path $Input -ErrorAction Stop
if (-not (Test-Path $inputPath)) { Write-Error "文件不存在: $inputPath"; exit 1 }

# Resolve output path
if (-not $Output) {
  $ext = if ($Format -eq "docx") { ".docx" } else { ".txt" }
  $Output = [System.IO.Path]::ChangeExtension($inputPath, $ext)
}
$outputPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Output)
$outputDir = Split-Path $outputPath -Parent
if (-not (Test-Path $outputDir)) { New-Item -ItemType Directory -Path $outputDir -Force | Out-Null }

Write-Host "输入: $inputPath" -ForegroundColor Cyan
Write-Host "输出: $outputPath" -ForegroundColor Cyan
Write-Host "格式: $Format" -ForegroundColor DarkGray

# Method 1: Word COM
try {
  Write-Host "尝试 Word COM 转换……" -ForegroundColor Yellow
  $word = New-Object -ComObject Word.Application
  $word.Visible = $false
  $word.DisplayAlerts = 0  # wdAlertsNone

  $doc = $word.Documents.Open($inputPath, $false, $true, $false)

  if ($Format -eq "docx") {
    $saveFormat = 16  # wdFormatXMLDocument (.docx)
    $doc.SaveAs([ref]$outputPath, [ref]$saveFormat)
  } else {
    $saveFormat = 7   # wdFormatText (.txt)
    $doc.SaveAs([ref]$outputPath, [ref]$saveFormat)
  }

  $doc.Close()
  $word.Quit()
  [System.Runtime.Interopservices.Marshal]::ReleaseComObject($doc) | Out-Null
  [System.Runtime.Interopservices.Marshal]::ReleaseComObject($word) | Out-Null

  if (Test-Path $outputPath) {
    $size = (Get-Item $outputPath).Length
    Write-Host "✅ 转换成功 ($([math]::Round($size/1024,1)) KB)" -ForegroundColor Green
    Write-Host "   $outputPath"
    exit 0
  }
} catch {
  Write-Warning "Word COM 失败: $_"
  if ($word) {
    try { $word.Quit() } catch {}
    [System.Runtime.Interopservices.Marshal]::ReleaseComObject($word) | Out-Null
  }
}

# Method 2: Fallback — try basic text extraction
Write-Host "尝试纯文本提取……" -ForegroundColor Yellow
try {
  # .doc files are OLE compound documents — try to extract raw text
  $bytes = [System.IO.File]::ReadAllBytes($inputPath)
  $text = [System.Text.Encoding]::GetEncoding(936).GetString($bytes)
  # Filter to printable Chinese + ASCII range
  $filtered = -join ($text.ToCharArray() | Where-Object {
    ($_ -ge '一' -and $_ -le '龥') -or
    ($_ -ge ' ' -and $_ -le '~') -or
    ($_ -eq "`r") -or ($_ -eq "`n") -or ($_ -eq "`t")
  })
  if ($filtered.Length -gt 100) {
    [System.IO.File]::WriteAllText($outputPath, $filtered, [System.Text.Encoding]::UTF8)
    Write-Host "⚠ 纯文本提取完成 ($($filtered.Length) 字符，可能含噪音)" -ForegroundColor Yellow
    Write-Host "   $outputPath"
    exit 0
  }
} catch {
  Write-Warning "纯文本提取也失败了"
}

Write-Error "所有转换方式均失败。请手动将 .doc 另存为 .docx 后重试。"
exit 1
