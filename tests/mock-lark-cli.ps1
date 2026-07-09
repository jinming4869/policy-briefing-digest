# Minimal lark-cli fixture used by tests/validate.ps1.

$ErrorActionPreference = "Stop"
$script:CliArgs = [object[]]$args

function Get-OptionValue {
  param([string]$Name)

  $index = [Array]::IndexOf($script:CliArgs, $Name)
  if ($index -lt 0 -or $index + 1 -ge $script:CliArgs.Count) {
    return $null
  }
  return "$($script:CliArgs[$index + 1])"
}

if (-not $env:MOCK_LARK_STATE) {
  throw "MOCK_LARK_STATE is required."
}

$state = if (Test-Path -LiteralPath $env:MOCK_LARK_STATE) {
  [System.IO.File]::ReadAllText($env:MOCK_LARK_STATE, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
} else {
  [PSCustomObject]@{
    Updates = 0
    Desc = ""
    Interp = ""
  }
}

$operation = if ($script:CliArgs.Count -ge 2) { "$($script:CliArgs[1])" } else { "" }

if ($operation -eq "+fetch") {
  $verifiedContent = "$($state.Desc)$($state.Interp)"
  $useVerified = $state.Updates -gt 0 -and $env:MOCK_LARK_FAIL_VERIFY -ne "1"
  $content = if ($useVerified) {
    $verifiedContent
  } else {
    '<p id="desc-1">旧描述</p><callout><p id="interp-1">旧解读</p></callout>'
  }
  $revision = if ($useVerified) { 11 } else { 10 }

  [PSCustomObject]@{
    ok = $true
    data = @{
      document = @{
        revision_id = $revision
        content = $content
      }
    }
  } | ConvertTo-Json -Depth 6 -Compress
  exit 0
}

if ($operation -eq "+update") {
  $blockId = Get-OptionValue -Name "--block-id"
  $contentArg = Get-OptionValue -Name "--content"
  if (-not $contentArg -or -not $contentArg.StartsWith("@")) {
    throw "Mock expected --content @file."
  }

  $contentPath = $contentArg.Substring(1)
  $content = [System.IO.File]::ReadAllText($contentPath, [System.Text.Encoding]::UTF8)
  if ($blockId -eq "desc-1") {
    $state.Desc = $content
  } elseif ($blockId -eq "interp-1") {
    $state.Interp = $content
  } else {
    throw "Unexpected block id: $blockId"
  }

  $state.Updates = [int]$state.Updates + 1
  [System.IO.File]::WriteAllText(
    $env:MOCK_LARK_STATE,
    ($state | ConvertTo-Json -Depth 4),
    [System.Text.UTF8Encoding]::new($false)
  )

  [PSCustomObject]@{
    ok = $true
    data = @{
      result = "success"
      revision_id = 11
    }
  } | ConvertTo-Json -Depth 4 -Compress
  exit 0
}

throw "Unsupported mock operation: $($script:CliArgs -join ' ')"
