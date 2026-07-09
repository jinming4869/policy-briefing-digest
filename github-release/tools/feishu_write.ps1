# feishu_write.ps1
# 用法: powershell -NoProfile -File tools/feishu_write.ps1 -Doc "wiki-token" -HeadingId "h4-block-id" -DescFile "desc.xml" -InterpFile "interp.xml"

param(
  [Parameter(Mandatory)] [string]$Doc,
  [Parameter(Mandatory)] [string]$HeadingId,
  [string]$DescFile,
  [string]$InterpFile
)

$ErrorActionPreference = "Stop"
$LARK = "lark-cli"

function Invoke-Lark($argsStr) {
  $cmd = "$LARK $argsStr"
  Write-Host "[CMD] $cmd" -ForegroundColor DarkGray
  $result = cmd /c "$cmd 2>&1"
  $json = $result -join "`n"
  try { return ($json | ConvertFrom-Json) } catch { Write-Error "parse fail"; throw }
}

# ⚠ 关键：每次写入前必须重新 fetch block IDs（用户编辑后ID会变）
Write-Host "Fetching current block IDs..." -ForegroundColor Cyan
$section = Invoke-Lark "docs +fetch --doc $Doc --scope section --start-block-id $HeadingId --detail with-ids"
if (-not $section.ok) { throw "Fetch fail" }

$xmlContent = [xml]("<root>" + $section.data.document.content + "</root>")
$descBlockId = $null
$interpBlockId = $null

foreach ($node in $xmlContent.root.ChildNodes) {
  if ($node.Name -eq 'p' -and -not $descBlockId) { $descBlockId = $node.id }
  elseif ($node.Name -eq 'callout' -and $node.p) { $interpBlockId = $node.p.id }
}

Write-Host "  desc: $descBlockId" -ForegroundColor Gray
Write-Host "  interp: $interpBlockId" -ForegroundColor Gray

# Replace description
if ($DescFile -and (Test-Path $DescFile) -and $descBlockId) {
  Write-Host "Replacing description..." -ForegroundColor Cyan
  $r = Invoke-Lark "docs +update --doc $Doc --command block_replace --block-id $descBlockId --content @$DescFile"
  Write-Host "  result: $($r.data.result)" -ForegroundColor Green
}

# Replace interpretation
if ($InterpFile -and (Test-Path $InterpFile) -and $interpBlockId) {
  Write-Host "Replacing interpretation..." -ForegroundColor Cyan
  $r = Invoke-Lark "docs +update --doc $Doc --command block_replace --block-id $interpBlockId --content @$InterpFile"
  Write-Host "  result: $($r.data.result)" -ForegroundColor Green
}

Write-Host "Done. revision: $($section.data.document.revision_id)" -ForegroundColor Green
