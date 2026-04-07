<#
.SYNOPSIS
    Get the secret scanning scan history progress for repos across an enterprise, org, or single repo.
.DESCRIPTION
    Calls GET /repos/{owner}/{repo}/secret-scanning/scan-history for each repo and outputs a
    markdown table summarizing backfill scan status. Supports cascading:
      - Enterprise → Orgs → Repos
      - Org → Repos
      - Single repo via owner/repo NWO

    https://docs.github.com/en/enterprise-cloud@latest/rest/secret-scanning/secret-scanning?apiVersion=2022-11-28#get-secret-scanning-scan-history-for-a-repository
.NOTES
    Performance: API calls are parallelized (10 concurrent). An org with ~4000 repos takes ~9 minutes.
    Enterprise mode requires the read:enterprise scope: gh auth refresh --scopes read:enterprise
.PARAMETER Enterprise
    GitHub Enterprise slug. Lists all orgs, then all repos per org.
.PARAMETER Org
    GitHub Organization name. Lists all repos in the org.
.PARAMETER Repo
    A single repository in owner/repo (NWO) format.
.PARAMETER Detailed
    Show the full markdown table with per-repo scan details instead of summary progress bars.
.EXAMPLE
    gh auth login
    .\Get-GHSecretScanningHistoryProgress.ps1 -Org octofelickz
.EXAMPLE
    gh auth login
    .\Get-GHSecretScanningHistoryProgress.ps1 -Repo octofelickz/openpilot
.EXAMPLE
    gh auth login --scopes read:enterprise
    .\Get-GHSecretScanningHistoryProgress.ps1 -Enterprise felickz-inc

     .\pwsh\Get-GHSecretScanningHistoryProgress.ps1 -Enterprise "felickz-inc"
            Fetching orgs for enterprise 'felickz-inc'...
            Found 4 org(s)
            Fetching repos for org 'DunderMifflinPaperCompany'...
            Found 11 repo(s) in 'DunderMifflinPaperCompany'
            Fetching repos for org 'felickz-inc-org'...
            Found 9 repo(s) in 'felickz-inc-org'
            Fetching repos for org 'felickz-inc-org-no-actions'...
            Found 1 repo(s) in 'felickz-inc-org-no-actions'
            Fetching repos for org 'no-ghas-all-breaks'...
            Found 1 repo(s) in 'no-ghas-all-breaks'

            Querying scan history for 22 repo(s) (10 concurrent)...


            Secret Scanning History Progress (18/22 repos reporting)
            ======================================================================

            BACKFILL
                discussions      [==============================] 100%  (18/18 done, last: 2025-12-15)
                git              [==============================] 100%  (18/18 done, last: 2025-12-15)
                issues           [==============================] 100%  (18/18 done, last: 2025-12-15)
                pull-requests    [==============================] 100%  (18/18 done, last: 2025-12-15)

            INCREMENTAL
                git              [==============================] 100%  (14/14 done, 4 n/a, last: 2026-03-26)

            PATTERN_UPDATE
                git              [==============================] 100%  (18/18 done, last: 2026-03-08)
                issues           [==============================] 100%  (13/13 done, 5 n/a, last: 2025-11-28)

            Repos with errors (4):
            felickz-inc-org/a-repo: Secret scanning is disabled on this repository.
            felickz-inc-org/no-ghas-yet: Secret scanning is disabled on this repository.
            felickz-inc-org-no-actions/a-repo: Secret scanning is disabled on this repository.
            no-ghas-all-breaks/lets-add-some-commits: Secret scanning is disabled on this repository.
#>

param(
    [Parameter(ParameterSetName = "Enterprise")]
    [string]$Enterprise,

    [Parameter(ParameterSetName = "Org")]
    [string]$Org,

    [Parameter(ParameterSetName = "Repo")]
    [string]$Repo,

    [Parameter()]
    [switch]$Detailed
)

# Resolve the list of NWO repos to query
function Get-RepoList {
    if ($Repo) {
        return @($Repo)
    }

    $orgs = @()
    if ($Enterprise) {
        Write-Host "Fetching orgs for enterprise '$Enterprise'..." -ForegroundColor Cyan
        $hasNext = $true
        $cursor = $null
        while ($hasNext) {
            $gqlQuery = 'query($slug: String!, $cursor: String) { enterprise(slug: $slug) { organizations(first: 100, after: $cursor) { pageInfo { hasNextPage endCursor } nodes { login } } } }'
            $gqlArgs = @('-f', "slug=$Enterprise", '-F', "cursor=$cursor", '-f', "query=$gqlQuery")
            $raw = gh api graphql @gqlArgs 2>&1
            if ($LASTEXITCODE -ne 0) {
                Write-Error "Failed to list orgs for enterprise '$Enterprise': $raw"
                Write-Warning "Ensure your token has the read:enterprise scope: gh auth refresh --scopes read:enterprise"
                return @()
            }
            $result = $raw | ConvertFrom-Json
            $orgs += $result.data.enterprise.organizations.nodes | ForEach-Object { $_.login }
            $hasNext = $result.data.enterprise.organizations.pageInfo.hasNextPage
            $cursor = $result.data.enterprise.organizations.pageInfo.endCursor
        }
        $orgs = $orgs | Where-Object { $_ }
        Write-Host "Found $($orgs.Count) org(s)" -ForegroundColor Cyan
    }
    elseif ($Org) {
        $orgs = @($Org)
    }

    $repos = @()
    foreach ($o in $orgs) {
        Write-Host "Fetching repos for org '$o'..." -ForegroundColor Cyan
        $orgRepos = gh api "/orgs/$o/repos?per_page=100&type=all" --paginate --jq '.[].full_name' 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Warning "Failed to list repos for org '$o': $orgRepos"
            continue
        }
        $orgRepos = $orgRepos | Where-Object { $_ }
        Write-Host "  Found $($orgRepos.Count) repo(s) in '$o'" -ForegroundColor Cyan
        $repos += $orgRepos
    }

    return $repos
}

# Flatten scan categories into a simple per-type status summary
function Get-ScanSummary {
    param([object]$History, [string]$RepoName)

    $rows = @()

    # Backfill scans are the primary indicator of history scan progress
    if ($History.backfill_scans) {
        foreach ($scan in $History.backfill_scans) {
            $rows += [PSCustomObject]@{
                Repo        = $RepoName
                Category    = "backfill"
                Type        = $scan.type
                Status      = $scan.status
                StartedAt   = $scan.started_at
                CompletedAt = $scan.completed_at
            }
        }
    }

    # Incremental scans
    if ($History.incremental_scans) {
        foreach ($scan in $History.incremental_scans) {
            $rows += [PSCustomObject]@{
                Repo        = $RepoName
                Category    = "incremental"
                Type        = $scan.type
                Status      = $scan.status
                StartedAt   = $scan.started_at
                CompletedAt = $scan.completed_at
            }
        }
    }

    # Pattern update scans
    if ($History.pattern_update_scans) {
        foreach ($scan in $History.pattern_update_scans) {
            $rows += [PSCustomObject]@{
                Repo        = $RepoName
                Category    = "pattern_update"
                Type        = $scan.type
                Status      = $scan.status
                StartedAt   = $scan.started_at
                CompletedAt = $scan.completed_at
            }
        }
    }

    # Custom pattern backfill scans
    if ($History.custom_pattern_backfill_scans) {
        foreach ($scan in $History.custom_pattern_backfill_scans) {
            $rows += [PSCustomObject]@{
                Repo        = $RepoName
                Category    = "custom_pattern ($($scan.pattern_slug))"
                Type        = $scan.type
                Status      = $scan.status
                StartedAt   = $scan.started_at
                CompletedAt = $scan.completed_at
            }
        }
    }

    return $rows
}

# --- Main ---

$repoList = Get-RepoList
if ($repoList.Count -eq 0) {
    Write-Error "No repos resolved. Provide -Enterprise, -Org, or -Repo."
    exit 1
}

$throttleLimit = 10
Write-Host "`nQuerying scan history for $($repoList.Count) repo(s) ($throttleLimit concurrent)...`n" -ForegroundColor Cyan

$results = $repoList | ForEach-Object -ThrottleLimit $throttleLimit -Parallel {
    $nwo = $_
    $raw = gh api "/repos/$nwo/secret-scanning/scan-history" 2>&1
    if ($LASTEXITCODE -ne 0) {
        [PSCustomObject]@{
            IsError = $true
            Repo    = $nwo
            Error   = ($raw -join " ")
            Rows    = $null
        }
    }
    else {
        $history = $raw | ConvertFrom-Json
        $rows = @()

        if ($history.backfill_scans) {
            foreach ($scan in $history.backfill_scans) {
                $rows += [PSCustomObject]@{ Repo = $nwo; Category = "backfill"; Type = $scan.type; Status = $scan.status; StartedAt = $scan.started_at; CompletedAt = $scan.completed_at }
            }
        }
        if ($history.incremental_scans) {
            foreach ($scan in $history.incremental_scans) {
                $rows += [PSCustomObject]@{ Repo = $nwo; Category = "incremental"; Type = $scan.type; Status = $scan.status; StartedAt = $scan.started_at; CompletedAt = $scan.completed_at }
            }
        }
        if ($history.pattern_update_scans) {
            foreach ($scan in $history.pattern_update_scans) {
                $rows += [PSCustomObject]@{ Repo = $nwo; Category = "pattern_update"; Type = $scan.type; Status = $scan.status; StartedAt = $scan.started_at; CompletedAt = $scan.completed_at }
            }
        }
        if ($history.custom_pattern_backfill_scans) {
            foreach ($scan in $history.custom_pattern_backfill_scans) {
                $rows += [PSCustomObject]@{ Repo = $nwo; Category = "custom_pattern ($($scan.pattern_slug))"; Type = $scan.type; Status = $scan.status; StartedAt = $scan.started_at; CompletedAt = $scan.completed_at }
            }
        }

        if ($rows.Count -eq 0) {
            $rows += [PSCustomObject]@{ Repo = $nwo; Category = "-"; Type = "-"; Status = "no scan data"; StartedAt = "-"; CompletedAt = "-" }
        }

        [PSCustomObject]@{
            IsError = $false
            Repo    = $nwo
            Error   = $null
            Rows    = $rows
        }
    }
}

$allRows = @()
$errors = @()
foreach ($r in $results) {
    if ($r.IsError) { $errors += $r }
    else { $allRows += $r.Rows }
}

# --- Output ---

if ($Detailed) {
    # Full markdown table
    $header    = "| Repo | Category | Type | Status | Started | Completed |"
    $separator = "| --- | --- | --- | --- | --- | --- |"

    Write-Output ""
    Write-Output $header
    Write-Output $separator

    foreach ($row in $allRows) {
        $started   = if ($row.StartedAt)   { $row.StartedAt }   else { "-" }
        $completed = if ($row.CompletedAt) { $row.CompletedAt } else { "-" }
        Write-Output "| $($row.Repo) | $($row.Category) | $($row.Type) | $($row.Status) | $started | $completed |"
    }
}

# Summary progress bars (always shown)
$totalRepos = $repoList.Count
$successRepos = $totalRepos - $errors.Count
$barWidth = 30

Write-Host ""
Write-Host "Secret Scanning History Progress ($successRepos/$totalRepos repos reporting)" -ForegroundColor White
Write-Host ("=" * 70) -ForegroundColor DarkGray

# Group rows by category + type, compute % completed
$scanRows = $allRows | Where-Object { $_.Category -ne "-" }
$groups = $scanRows | Group-Object -Property Category, Type

# Sort categories in a logical order
$categoryOrder = @{ "backfill" = 0; "incremental" = 1; "pattern_update" = 2 }
$sorted = $groups | Sort-Object {
    $cat = ($_.Name -split ', ')[0]
    if ($categoryOrder.ContainsKey($cat)) { $categoryOrder[$cat] } else { 3 }
}, { ($_.Name -split ', ')[1] }

$lastCategory = ""
foreach ($g in $sorted) {
    $parts = $g.Name -split ', '
    $cat  = $parts[0]
    $type = $parts[1]

    if ($cat -ne $lastCategory) {
        Write-Host ""
        Write-Host "  $($cat.ToUpper())" -ForegroundColor Yellow
        $lastCategory = $cat
    }

    $completedCount = ($g.Group | Where-Object { $_.Status -eq "completed" }).Count
    $inProgressCount = ($g.Group | Where-Object { $_.Status -eq "in_progress" }).Count
    $total = $g.Group.Count
    $pct = if ($total -gt 0) { [math]::Min([math]::Round(($completedCount / $total) * 100), 100) } else { 0 }
    $missingCount = [math]::Max($successRepos - $total, 0)

    # Find the most recent completed timestamp
    $lastCompleted = $g.Group | Where-Object { $_.Status -eq "completed" -and $_.CompletedAt -and $_.CompletedAt -ne "-" } |
        ForEach-Object { [datetime]$_.CompletedAt } |
        Sort-Object -Descending | Select-Object -First 1
    $lastCompletedStr = if ($lastCompleted) { $lastCompleted.ToString("yyyy-MM-dd") } else { "-" }

    $filledLen = [math]::Min([math]::Floor($barWidth * $completedCount / $total), $barWidth)
    $progressLen = [math]::Min([math]::Floor($barWidth * $inProgressCount / $total), $barWidth - $filledLen)
    $emptyLen  = $barWidth - $filledLen - $progressLen

    $bar      = "=" * $filledLen
    $progress = ">" * $progressLen
    $empty    = " " * $emptyLen

    $label = "{0,-16}" -f $type
    $stats = "$completedCount/$total done"
    if ($inProgressCount -gt 0) { $stats += ", $inProgressCount in progress" }
    if ($missingCount -gt 0) { $stats += ", $missingCount n/a" }
    $stats += ", last: $lastCompletedStr"

    Write-Host "    $label [" -NoNewline
    Write-Host $bar -NoNewline -ForegroundColor Green
    Write-Host $progress -NoNewline -ForegroundColor Yellow
    Write-Host $empty -NoNewline
    Write-Host "] " -NoNewline
    $pctColor = if ($pct -eq 100) { "Green" } elseif ($pct -ge 50) { "Yellow" } else { "Red" }
    Write-Host ("{0,3}%" -f $pct) -NoNewline -ForegroundColor $pctColor
    Write-Host "  ($stats)"
}

Write-Host ""

# Repos not yet completed — any scan with a non-completed status
$scanRows = $allRows | Where-Object { $_.Category -ne "-" }
$pendingRows = $scanRows | Where-Object { $_.Status -ne "completed" }

if ($pendingRows.Count -gt 0) {
    Write-Output "### Repos not yet completed ($($pendingRows.Count))"
    Write-Output ""
    Write-Output "| Repo | Category | Type | Status | Started | Completed |"
    Write-Output "| --- | --- | --- | --- | --- | --- |"
    foreach ($row in $pendingRows | Sort-Object Repo, Category, Type) {
        $started   = if ($row.StartedAt)   { $row.StartedAt }   else { "-" }
        $completed = if ($row.CompletedAt) { $row.CompletedAt } else { "-" }
        Write-Output "| $($row.Repo) | $($row.Category) | $($row.Type) | $($row.Status) | $started | $completed |"
    }
    Write-Output ""
}

# Print errors summary
if ($errors.Count -gt 0) {
    Write-Host "Repos with errors ($($errors.Count)):" -ForegroundColor Red
    foreach ($e in $errors) {
        Write-Host "  $($e.Repo): " -NoNewline -ForegroundColor DarkGray
        # Extract short reason from error message
        if ($e.Error -match '"message":"([^"]+)"') { Write-Host $Matches[1] -ForegroundColor DarkGray }
        else { Write-Host $e.Error -ForegroundColor DarkGray }
    }
    Write-Host ""
}
