# Categorize-GhasBotComments.ps1
# Enriches the output of Find-GhasBotComments.ps1 with the resolution state
# of each underlying code-scanning alert and PR review thread.
#
# Categories:
#   fixed       - code-scanning alert most_recent_instance.state == 'fixed'
#   dismissed   - alert state == 'dismissed' (false positive / won't fix / used in tests)
#   commented   - human (non-bot) replied in the review thread
#   resolved    - thread marked resolved on GitHub (but not fixed/dismissed via alert)
#   ignored     - no reply, not resolved, alert still open
#
# Usage:
#   ./Categorize-GhasBotComments.ps1 -Repo curl/curl -InJson curl-ghas-comments.json -OutJson curl-ghas-categorized.json
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Repo,
    [Parameter(Mandatory = $true)][string]$InJson,
    [string]$OutJson,
    [string]$BotLogin = 'github-advanced-security'
)
$ErrorActionPreference = 'Stop'

$comments = Get-Content $InJson -Raw | ConvertFrom-Json
Write-Host "Loaded $($comments.Count) bot comments." -ForegroundColor Cyan

# Group by PR so we make one GraphQL call per PR for review threads.
$byPr = $comments | Group-Object pr

# Cache alert lookups so we don't refetch the same alert.
$alertCache = @{}

function Get-AlertState {
    param([string]$repo, [int]$num)
    $key = "$repo#$num"
    if ($alertCache.ContainsKey($key)) { return $alertCache[$key] }
    try {
        $raw = gh api "repos/$repo/code-scanning/alerts/$num" 2>$null
        if ($LASTEXITCODE -ne 0 -or -not $raw) { $alertCache[$key] = $null; return $null }
        $a = $raw | ConvertFrom-Json
        $state = if ($a.most_recent_instance.state) { $a.most_recent_instance.state } else { $a.state }
        $info = [pscustomobject]@{
            number           = $a.number
            state            = $state
            top_state        = $a.state
            dismissed_reason = $a.dismissed_reason
            rule             = $a.rule.id
            severity         = $a.rule.security_severity_level
        }
        $alertCache[$key] = $info
        return $info
    } catch {
        $alertCache[$key] = $null
        return $null
    }
}

$results = New-Object System.Collections.Generic.List[object]
$prIdx = 0
foreach ($g in $byPr) {
    $prIdx++
    $prNum = [int]$g.Name
    Write-Progress -Activity "Categorizing" -Status "PR #$prNum ($prIdx/$($byPr.Count))" `
        -PercentComplete (($prIdx / $byPr.Count) * 100)

    # GraphQL: get review threads with replies + resolution state.
    $q = @"
query(`$owner:String!,`$name:String!,`$num:Int!) {
  repository(owner:`$owner,name:`$name) {
    pullRequest(number:`$num) {
      reviewThreads(first:100) {
        nodes {
          isResolved
          isOutdated
          comments(first:50) {
            nodes { databaseId author { login } }
          }
        }
      }
    }
  }
}
"@
    $owner, $name = $Repo.Split('/')
    $threadsRaw = gh api graphql -f query=$q -F owner=$owner -F name=$name -F num=$prNum 2>$null
    $threadMap = @{}   # databaseId of first comment -> thread info
    if ($LASTEXITCODE -eq 0 -and $threadsRaw) {
        $threads = ($threadsRaw | ConvertFrom-Json).data.repository.pullRequest.reviewThreads.nodes
        foreach ($t in $threads) {
            $cs = $t.comments.nodes
            if (-not $cs -or $cs.Count -eq 0) { continue }
            $firstId = $cs[0].databaseId
            $hasHumanReply = $false
            for ($i = 1; $i -lt $cs.Count; $i++) {
                if ($cs[$i].author.login -and $cs[$i].author.login -ne $BotLogin) {
                    $hasHumanReply = $true; break
                }
            }
            $threadMap[$firstId] = [pscustomobject]@{
                isResolved    = $t.isResolved
                isOutdated    = $t.isOutdated
                replyCount    = [Math]::Max($cs.Count - 1, 0)
                hasHumanReply = $hasHumanReply
            }
        }
    }

    foreach ($c in $g.Group) {
        # Extract the comment's REST id from comment_url (#discussion_r<id>)
        $commentId = 0L
        if ($c.comment_url -match 'discussion_r(\d+)') { $commentId = [int64]$matches[1] }

        $thread = $threadMap[$commentId]

        # Parse alert number from body_preview (or full body in JSON).
        $alertNum = 0
        if ($c.body_preview -match 'code-scanning/(\d+)') { $alertNum = [int]$matches[1] }
        $alert = if ($alertNum) { Get-AlertState -repo $Repo -num $alertNum } else { $null }

        # Decide category, priority: dismissed > fixed > commented > resolved > ignored
        $category = 'ignored'
        $reason = ''
        if ($alert -and $alert.state -eq 'dismissed') {
            $category = 'dismissed'
            $reason = $alert.dismissed_reason
        } elseif ($alert -and $alert.state -eq 'fixed') {
            $category = 'fixed'
        } elseif ($thread -and $thread.hasHumanReply) {
            $category = 'commented'
        } elseif ($thread -and $thread.isResolved) {
            $category = 'resolved'
        } elseif ($thread -and $thread.isOutdated) {
            # Code changed but alert not marked fixed (e.g. PR closed without merge).
            $category = 'outdated'
        }

        $results.Add([pscustomobject]@{
            pr               = $c.pr
            pr_url           = $c.pr_url
            pr_state         = $c.state
            path             = $c.path
            line             = $c.line
            comment_url      = $c.comment_url
            alert_number     = $alertNum
            alert_state      = if ($alert) { $alert.state } else { $null }
            rule             = if ($alert) { $alert.rule } else { $null }
            severity         = if ($alert) { $alert.severity } else { $null }
            dismissed_reason = if ($alert) { $alert.dismissed_reason } else { $null }
            thread_resolved  = if ($thread) { $thread.isResolved } else { $null }
            thread_outdated  = if ($thread) { $thread.isOutdated } else { $null }
            human_replies    = if ($thread) { $thread.replyCount } else { 0 }
            category         = $category
            category_reason  = $reason
            body_preview     = $c.body_preview
        })
    }
}
Write-Progress -Activity "Categorizing" -Completed

if ($OutJson) {
    $results | ConvertTo-Json -Depth 5 | Set-Content -Path $OutJson -Encoding UTF8
    Write-Host "Wrote $OutJson" -ForegroundColor Green
}

Write-Host ""
Write-Host "=== Category counts ===" -ForegroundColor Cyan
$results | Group-Object category | Sort-Object Count -Descending | Select-Object Name, Count | Format-Table -AutoSize

$results
