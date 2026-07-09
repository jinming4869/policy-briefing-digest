# feishu_write.ps1
# 用法:
# powershell -NoProfile -File tools/feishu_write.ps1 `
#   -Doc "wiki-token" -HeadingId "h4-block-id" `
#   -DescFile "desc.xml" -InterpFile "interp.xml"

param(
  [Parameter(Mandatory)] [string]$Doc,
  [Parameter(Mandatory)] [string]$HeadingId,
  [string]$DescFile,
  [string]$InterpFile,
  [string]$LarkCli = "lark-cli.cmd"
)

$ErrorActionPreference = "Stop"

function Resolve-LarkCli {
  param([string]$Command)

  if (Test-Path -LiteralPath $Command) {
    return (Resolve-Path -LiteralPath $Command).Path
  }

  $resolved = Get-Command $Command -ErrorAction SilentlyContinue
  if (-not $resolved) {
    throw "找不到飞书 CLI：$Command。请先运行 npx @larksuite/cli@latest install，或通过 -LarkCli 指定路径。"
  }
  return $resolved.Source
}

function Resolve-ContentFile {
  param([string]$Path)

  if (-not $Path) { return $null }
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    throw "内容文件不存在：$Path"
  }
  return (Resolve-Path -LiteralPath $Path).Path
}

function Invoke-Lark {
  param([string[]]$Arguments)

  Write-Host ("[LARK] " + ($Arguments -join " ")) -ForegroundColor DarkGray
  $raw = & $script:LarkCliPath @Arguments 2>&1
  $exitCode = $LASTEXITCODE
  $text = ($raw | ForEach-Object { "$_" }) -join "`n"

  if ($exitCode -ne 0) {
    throw "飞书 CLI 执行失败（exit $exitCode）：$text"
  }

  try {
    $result = $text | ConvertFrom-Json
  } catch {
    throw "飞书 CLI 未返回有效 JSON：$text"
  }

  if (-not $result.ok) {
    $message = if ($result.error.message) { $result.error.message } else { $text }
    throw "飞书 CLI 返回失败：$message"
  }
  return $result
}

function Get-NormalizedXmlText {
  param([string]$Fragment)

  if ([string]::IsNullOrWhiteSpace($Fragment)) { return "" }
  try {
    $xml = [xml]("<root>$Fragment</root>")
  } catch {
    throw "内容不是有效的 XML 片段：$($_.Exception.Message)"
  }
  return (($xml.root.InnerText -replace "\s+", " ").Trim())
}

function Fetch-Section {
  Invoke-Lark -Arguments @(
    "docs", "+fetch",
    "--doc", $Doc,
    "--scope", "section",
    "--start-block-id", $HeadingId,
    "--detail", "with-ids",
    "--format", "json"
  )
}

if (-not $DescFile -and -not $InterpFile) {
  throw "至少提供 -DescFile 或 -InterpFile 其中一个。"
}

$script:LarkCliPath = Resolve-LarkCli -Command $LarkCli
$descPath = Resolve-ContentFile -Path $DescFile
$interpPath = Resolve-ContentFile -Path $InterpFile
$descContent = if ($descPath) { [System.IO.File]::ReadAllText($descPath, [System.Text.Encoding]::UTF8) } else { $null }
$interpContent = if ($interpPath) { [System.IO.File]::ReadAllText($interpPath, [System.Text.Encoding]::UTF8) } else { $null }
$expectedDesc = Get-NormalizedXmlText -Fragment $descContent
$expectedInterp = Get-NormalizedXmlText -Fragment $interpContent

Write-Host "读取目标栏目和最新 block IDs..." -ForegroundColor Cyan
$before = Fetch-Section
$beforeContent = $before.data.document.content
if ([string]::IsNullOrWhiteSpace($beforeContent)) {
  throw "目标栏目没有返回可编辑内容。"
}

try {
  $sectionXml = [xml]("<root>$beforeContent</root>")
} catch {
  throw "无法解析目标栏目的 XML：$($_.Exception.Message)"
}

$descBlockId = $null
$interpBlockId = $null
foreach ($node in $sectionXml.root.ChildNodes) {
  if ($node.Name -eq "p" -and -not $descBlockId) {
    $descBlockId = $node.id
  } elseif ($node.Name -eq "callout" -and $node.p -and -not $interpBlockId) {
    $interpBlockId = $node.p.id
  }
}

if ($descPath -and -not $descBlockId) {
  throw "未找到政策描述段落 block ID。"
}
if ($interpPath -and -not $interpBlockId) {
  throw "未找到政策解读 callout 段落 block ID。"
}

if ($descPath) {
  Write-Host "写入政策描述..." -ForegroundColor Cyan
  [void](Invoke-Lark -Arguments @(
    "docs", "+update",
    "--doc", $Doc,
    "--command", "block_replace",
    "--block-id", "$descBlockId",
    "--content", "@$descPath",
    "--format", "json"
  ))
}

if ($interpPath) {
  Write-Host "写入政策解读..." -ForegroundColor Cyan
  [void](Invoke-Lark -Arguments @(
    "docs", "+update",
    "--doc", $Doc,
    "--command", "block_replace",
    "--block-id", "$interpBlockId",
    "--content", "@$interpPath",
    "--format", "json"
  ))
}

Write-Host "回读并核对写入结果..." -ForegroundColor Cyan
$after = Fetch-Section
$afterText = Get-NormalizedXmlText -Fragment $after.data.document.content

if ($descPath -and -not $afterText.Contains($expectedDesc)) {
  throw "回读校验失败：政策描述未出现在目标栏目中。"
}
if ($interpPath -and -not $afterText.Contains($expectedInterp)) {
  throw "回读校验失败：政策解读未出现在目标栏目中。"
}

$revision = $after.data.document.revision_id
Write-Host "写入并校验完成。revision: $revision" -ForegroundColor Green
