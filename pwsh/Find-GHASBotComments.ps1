# Find-GhasBotComments.ps1
# Scans a GitHub repo's PRs for review comments authored by the
# github-advanced-security[bot] (GitHub Advanced Security / Copilot Autofix /
# code scanning PR alerts).
#
# Requires: gh CLI authenticated (`gh auth status`).
#
# Usage:
#   ./Find-GhasBotComments.ps1 -Repo owner/name [-State open|closed|all] [-Limit 200]
#
# Outputs an array of objects: pr, title, url, path, line, comment_url, body_preview.
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Repo,

    [ValidateSet('open', 'closed', 'all')]
    [string]$State = 'all',

    [int]$Limit = 100,

    [string]$BotLogin = 'github-advanced-security[bot]',

    [string]$OutJson,

    # When set, use GitHub search to find only PRs the bot has commented on.
    # Much faster than scanning every PR. Recommended for large repos.
    [switch]$SearchOnly,

    # Comment kind filter:
    #   All     - return everything (default)
    #   AIOnly  - only AI-detection comments (Copilot security review / AI scanning)
    #   CodeQL  - only CodeQL/code-scanning alert comments
    [ValidateSet('All', 'AIOnly', 'CodeQL')]
    [string]$Kind = 'All'
)

$ErrorActionPreference = 'Stop'

if ($SearchOnly) {
    Write-Host "Searching $Repo for PRs with comments by $BotLogin..." -ForegroundColor Cyan
    $stateQ = if ($State -eq 'all') { '' } else { " state:$State" }
    $q = "repo:$Repo is:pr commenter:app/github-advanced-security$stateQ"
    $searchJson = gh api --paginate -X GET search/issues -f q="$q" -f per_page=100 --jq '.items[] | {number, title, html_url, state}'
    if ($LASTEXITCODE -ne 0) { throw "gh search failed" }
    # --jq emits one JSON object per line
    $items = $searchJson | Where-Object { $_.Trim() } | ForEach-Object { $_ | ConvertFrom-Json }
    $prs = $items | Select-Object -First $Limit | ForEach-Object {
        [pscustomobject]@{
            number = $_.number
            title  = $_.title
            url    = $_.html_url
            state  = $_.state
        }
    }
} else {
    Write-Host "Listing PRs from $Repo (state=$State, limit=$Limit)..." -ForegroundColor Cyan
    $prsJson = gh pr list --repo $Repo --state $State --limit $Limit `
        --json number,title,url,state,updatedAt
    if ($LASTEXITCODE -ne 0) { throw "gh pr list failed" }
    $prs = $prsJson | ConvertFrom-Json
}

Write-Host "Found $($prs.Count) PRs. Scanning review comments..." -ForegroundColor Cyan

$results = New-Object System.Collections.Generic.List[object]
$i = 0
foreach ($pr in $prs) {
    $i++
    Write-Progress -Activity "Scanning PRs" -Status "PR #$($pr.number) ($i/$($prs.Count))" `
        -PercentComplete (($i / [Math]::Max($prs.Count,1)) * 100)

    # Paginated fetch of review comments for this PR; emit one obj per line.
    $raw = gh api --paginate "repos/$Repo/pulls/$($pr.number)/comments?per_page=100" --jq '.[]' 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $raw) { continue }
    $all = $raw | Where-Object { $_.Trim() } | ForEach-Object { $_ | ConvertFrom-Json }
    $comments = $all | Where-Object { $_.user.login -eq $BotLogin }

    foreach ($c in $comments) {
        # Classify the comment kind. CodeQL/code-scanning comments link to
        # /security/code-scanning/<id>; AI-detection comments do not.
        $isCodeQL = $c.body -match 'security/code-scanning/\d+'
        $commentKind = if ($isCodeQL) { 'codeql' } else { 'ai' }
        if ($Kind -eq 'AIOnly' -and $commentKind -ne 'ai')     { continue }
        if ($Kind -eq 'CodeQL' -and $commentKind -ne 'codeql') { continue }

        $preview = ($c.body -replace '\s+', ' ').Trim()
        if ($preview.Length -gt 160) { $preview = $preview.Substring(0, 160) + '...' }
        $results.Add([pscustomobject]@{
            pr           = $pr.number
            title        = $pr.title
            pr_url       = $pr.url
            state        = $pr.state
            kind         = $commentKind
            path         = $c.path
            line         = $c.line
            comment_url  = $c.html_url
            body_preview = $preview
        })
    }
}
Write-Progress -Activity "Scanning PRs" -Completed

Write-Host ""
Write-Host "Found $($results.Count) GHAS bot comments across $(($results | Select-Object -Unique pr).Count) PRs." -ForegroundColor Green

if ($OutJson) {
    $results | ConvertTo-Json -Depth 5 | Set-Content -Path $OutJson -Encoding UTF8
    Write-Host "Wrote results to $OutJson" -ForegroundColor Green
}

$results
