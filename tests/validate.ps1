# Release validation for Windows PowerShell 5.1.

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot

function Assert-True {
  param(
    [bool]$Condition,
    [string]$Message
  )
  if (-not $Condition) { throw $Message }
}

Write-Host "Checking repository layout..." -ForegroundColor Cyan
Assert-True (-not (Test-Path -LiteralPath (Join-Path $root "github-release"))) "github-release/ must not exist at repository root."
Assert-True (Test-Path -LiteralPath (Join-Path $root "configs\feishu_targets.template.yaml")) "Missing Feishu config template."
Assert-True (-not (Test-Path -LiteralPath (Join-Path $root "configs\feishu_targets.yaml"))) "Real Feishu config must not be committed."

Write-Host "Checking skill frontmatter..." -ForegroundColor Cyan
$skill = [System.IO.File]::ReadAllText((Join-Path $root "SKILL.md"), [System.Text.Encoding]::UTF8)
Assert-True ($skill -match '\A---\r?\nname:\s*policy-briefing-digest\r?\ndescription:') "SKILL.md frontmatter is missing or invalid."

Write-Host "Scanning for local paths and credentials..." -ForegroundColor Cyan
$textFiles = Get-ChildItem -LiteralPath $root -Recurse -File | Where-Object {
  $_.Extension -in @(".md", ".ps1", ".yaml", ".yml", ".html", ".json") -or $_.Name -in @(".gitignore", ".editorconfig")
}
$blockedPatterns = @(
  'C:\\Users\\',
  ('happy' + 'elements'),
  '(?i)(client_secret|app_secret|tenant_access_token)\s*[:=]\s*["''][^"'']+',
  'https://(?!xxxxx)[^/\s]+\.feishu\.cn/'
)
foreach ($file in $textFiles) {
  $content = [System.IO.File]::ReadAllText($file.FullName, [System.Text.Encoding]::UTF8)
  foreach ($pattern in $blockedPatterns) {
    Assert-True (-not [regex]::IsMatch($content, $pattern)) "Blocked value found in $($file.FullName): $pattern"
  }
}

Write-Host "Parsing PowerShell scripts..." -ForegroundColor Cyan
foreach ($file in Get-ChildItem -LiteralPath $root -Recurse -Filter "*.ps1" -File) {
  $tokens = $null
  $errors = $null
  [void][System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$errors)
  Assert-True ($errors.Count -eq 0) "PowerShell parse failure in $($file.FullName): $($errors.Message -join '; ')"
}

Write-Host "Checking Workbench JavaScript contract..." -ForegroundColor Cyan
$node = Get-Command node -ErrorAction SilentlyContinue
Assert-True ($null -ne $node) "Node.js is required for the Workbench contract test."
$workbenchOutput = & $node.Source (Join-Path $root "tests\validate-workbench.js") 2>&1
Assert-True ($LASTEXITCODE -eq 0) "Workbench contract test failed: $($workbenchOutput -join [Environment]::NewLine)"

$tempRoot = Join-Path $env:TEMP ("policy-briefing-digest-test-" + [Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $tempRoot | Out-Null

try {
  $descFile = Join-Path $tempRoot "desc.xml"
  $interpFile = Join-Path $tempRoot "interp.xml"
  [System.IO.File]::WriteAllText($descFile, "<p>新政策描述</p>", [System.Text.UTF8Encoding]::new($false))
  [System.IO.File]::WriteAllText($interpFile, "<p>新政策解读</p>", [System.Text.UTF8Encoding]::new($false))

  Write-Host "Testing Feishu writeback success path..." -ForegroundColor Cyan
  $env:MOCK_LARK_STATE = Join-Path $tempRoot "success-state.json"
  $env:MOCK_LARK_FAIL_VERIFY = ""
  $successOutput = & "$PSHOME\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root "tools\feishu_write.ps1") `
    -Doc "mock-doc" `
    -HeadingId "mock-heading" `
    -DescFile $descFile `
    -InterpFile $interpFile `
    -LarkCli (Join-Path $root "tests\mock-lark-cli.cmd") 2>&1
  Assert-True ($LASTEXITCODE -eq 0) "Feishu success-path test failed: $($successOutput -join [Environment]::NewLine)"
  Assert-True (($successOutput -join "`n") -match 'revision:\s*11') "Feishu success-path did not report the verified revision."

  Write-Host "Testing Feishu verification failure..." -ForegroundColor Cyan
  $env:MOCK_LARK_STATE = Join-Path $tempRoot "failure-state.json"
  $env:MOCK_LARK_FAIL_VERIFY = "1"
  $previousErrorAction = $ErrorActionPreference
  $ErrorActionPreference = "Continue"
  $failureOutput = & "$PSHOME\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root "tools\feishu_write.ps1") `
    -Doc "mock-doc" `
    -HeadingId "mock-heading" `
    -DescFile $descFile `
    -InterpFile $interpFile `
    -LarkCli (Join-Path $root "tests\mock-lark-cli.cmd") 2>&1
  $failureExitCode = $LASTEXITCODE
  $ErrorActionPreference = $previousErrorAction
  Assert-True ($failureExitCode -ne 0) "Feishu verification-failure test unexpectedly succeeded."
  Assert-True (($failureOutput -join "`n") -match '回读校验失败') "Feishu verification failure did not explain the mismatch."
} finally {
  Remove-Item Env:\MOCK_LARK_STATE -ErrorAction SilentlyContinue
  Remove-Item Env:\MOCK_LARK_FAIL_VERIFY -ErrorAction SilentlyContinue
  Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "All release checks passed." -ForegroundColor Green
exit 0
