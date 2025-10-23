# This script is intended to report on the users who are fixing code scanning alerts in a GitHub repository - including the number of alerts they have closed as fixed.

#$nwo = "octodemo/old-vulnerable-node"
$nwo = "felickz/codeql-fixer-report"
$state = "fixed" # NOTE - fixed means alert was not present in a subsequent scan - which might introduce noise if a code scanning config was removed
$alerts = gh api "/repos/$nwo/code-scanning/alerts?state=$state&tool_name=CodeQL" --paginate | ConvertFrom-Json

# Loop through each alert and build a list of users who fixed them and keep a count
$commitCache = @{}
$fixers = @{}
foreach ($alert in $alerts) {    
    # Get the commit details from cache or API
    $sha = $alert.most_recent_instance.commit_sha
    if (-not $commitCache.ContainsKey($sha)) {
        $commitCache[$sha] = gh api "/repos/$nwo/git/commits/$sha" | ConvertFrom-Json
    }

    $commit = $commitCache[$sha]
    $author = $commit.author.name
    #Write-Host "#$($alert.number) - $($alert.state) RULE:$($alert.rule.id) SHA:$sha Author: $($commit.author.name) Date:$($commit.author.date)"

    if ($fixers.ContainsKey($author)) {
        $fixers[$author]++
    }
    else {
        $fixers[$author] = 1
    }
}


# Print out the report of fixers in markdown format
$markdown = @"
# Code Scanning Alert Fixers Report
| Author | Fixes |
|--------|-------|

"@
foreach ($fixer in $fixers.GetEnumerator() | Sort-Object -Property Value -Descending) {
    $markdown += "| $($fixer.Key) | $($fixer.Value) |`n"
}

Write-Host $markdown
$markdown | Out-File -FilePath "CodeScanningAlertFixersReport.md" -Encoding utf8
