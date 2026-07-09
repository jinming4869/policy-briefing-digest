# gov_search.ps1
# gov.cn 政策文件库搜索 — 用于精确检索政府官方政策文件
# 用法: powershell -NoProfile -File tools/gov_search.ps1 -Keywords "数据出境" [-MaxResults 10]
# 输出: JSON 格式的搜索结果列表

param(
  [Parameter(Mandatory)] [string]$Keywords,
  [int]$MaxResults = 10,
  [string]$OutputFile
)

$ErrorActionPreference = "Stop"

# URL-encode keywords
Add-Type -AssemblyName System.Web
$encoded = [System.Web.HttpUtility]::UrlEncode($Keywords)

# Search endpoint (zcwjk = 政策文件库)
$searchUrl = "https://sousuo.www.gov.cn/sousuo/search.shtml?code=17fcd1cb8c&dataTypeId=107&sign=440b2d4e-7a2f-4600-a5b5-2e3c1e9a8f6d&searchWord=$encoded"

Write-Host "搜索: $Keywords" -ForegroundColor Cyan
Write-Host "URL: $searchUrl" -ForegroundColor DarkGray

try {
  # Use .NET WebClient for better encoding control
  $wc = New-Object System.Net.WebClient
  $wc.Encoding = [System.Text.Encoding]::UTF8
  $wc.Headers.Add("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36")
  $html = $wc.DownloadString($searchUrl)

  # Parse results — search for the result list pattern
  $results = @()
  $idx = 0

  # Pattern: <h3 class="result-title"><a href="...">title</a></h3>
  # followed by <span class="result-date">date</span>
  # followed by <span class="result-source">source</span>

  $titleRegex = '<h3[^>]*class="[^"]*result-title[^"]*"[^>]*>\s*<a[^>]*href="([^"]+)"[^>]*>(.+?)</a>'
  $dateRegex = '<span[^>]*class="[^"]*result-date[^"]*"[^>]*>([^<]+)</span>'
  $sourceRegex = '<span[^>]*class="[^"]*result-source[^"]*"[^>]*>([^<]+)</span>'
  $descRegex = '<p[^>]*class="[^"]*result-desc[^"]*"[^>]*>(.+?)</p>'

  $titleMatches = [regex]::Matches($html, $titleRegex)
  $dateMatches = [regex]::Matches($html, $dateRegex)
  $sourceMatches = [regex]::Matches($html, $sourceRegex)
  $descMatches = [regex]::Matches($html, $descRegex)

  $count = [Math]::Min($MaxResults, $titleMatches.Count)
  for ($i = 0; $i -lt $count; $i++) {
    $title = $titleMatches[$i].Groups[2].Value -replace '<[^>]+>','' -replace '\s+',' ' | ForEach-Object { $_.Trim() }
    $url = $titleMatches[$i].Groups[1].Value
    # Ensure URL is absolute
    if ($url -notmatch '^https?://') {
      if ($url.StartsWith('/')) { $url = "https://www.gov.cn$url" }
      else { $url = "https://www.gov.cn/$url" }
    }

    $date = if ($i -lt $dateMatches.Count) { $dateMatches[$i].Groups[1].Value.Trim() } else { "" }
    $source = if ($i -lt $sourceMatches.Count) { $sourceMatches[$i].Groups[1].Value.Trim() } else { "" }
    $desc = if ($i -lt $descMatches.Count) { $descMatches[$i].Groups[1].Value -replace '<[^>]+>','' -replace '\s+',' ' | ForEach-Object { $_.Trim() } } else { "" }

    $results += [PSCustomObject]@{
      Index = $i + 1
      Title = $title
      URL = $url
      Date = $date
      Source = $source
      Description = $desc
    }
  }

  if ($results.Count -eq 0) {
    throw "页面可访问，但没有解析到结构化搜索结果。"
  }

} catch {
  Write-Warning "HTTP 请求失败: $_"
  Write-Warning "自动检索不可用，可能是页面结构变化、Cookie 要求或反爬限制。"
  Write-Warning "手动搜索地址: https://sousuo.www.gov.cn/zcwjk/"
  Write-Warning "请在官方页面输入关键词，并将结果交给 Agent 继续核验。"

  # Fallback: output manual search instructions
  $results = @([PSCustomObject]@{
    Index = 1
    Title = "[需手动搜索]"
    URL = "https://sousuo.www.gov.cn/zcwjk/?q=$encoded"
    Date = ""
    Source = "中国政府网 政策文件库"
    Description = "自动搜索未返回结果。请打开链接手动搜索后，将结果粘贴给 Agent。"
  })
}

# Output
$json = $results | ConvertTo-Json -Depth 2
if ($OutputFile) {
  $outPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputFile)
  [System.IO.File]::WriteAllText($outPath, $json, [System.Text.UTF8Encoding]::new($false))
  Write-Host "结果已写入: $outPath" -ForegroundColor Green
}

Write-Host "找到 $($results.Count) 条结果" -ForegroundColor Cyan
Write-Host $json
