$org = 'octodemo'
Write-Host "Detecting repos with GHAS enabled in the $org organization 🕵️‍♂️"

# type=member is private+internal
$repos = gh api "/orgs/$org/repos?type=member&sort=full_name" --paginate --jq '.[] | select(.security_and_analysis.advanced_security.status == "enabled" and ((.language // "") | ascii_downcase | test("^(javascript|typescript|java|kotlin|ruby|c|c\\+\\+|python|swift|c\\#)$"; "i"))) | .name'
$totalRepos = $repos.Count
$currentRepo = 0

Write-Host "Number of Repos Found: $totalRepos 📦 $( $totalRepos -gt 20 ? '.  This might take a while...' : '' )"

$repos | ForEach-Object {
    $currentRepo++
    $slug = "$org/$_"

    Write-Progress -Activity "Processing Repositories" -Status "$currentRepo of $totalRepos" -PercentComplete (($currentRepo / $totalRepos) * 100)

    # dependabot[bot] = 49699333
    $prNumbers = gh api "/repos/$slug/pulls" --paginate --jq '.[] | select(.updated_at > "2023-11-01T00:00:00Z" and .user.id != 49699333) | .number'

    Write-Debug "❓ Checking for non 'dependabot[bot]' PRs with Comments since 11/2023: https://github.com/$slug/pulls - $($prNumbers.Count) PRs"

    #Confirmed Fixed if GHAS bot co-authored: commit.message that contains "62310815+github-advanced-security[bot]@users.noreply.github.com"
    $prCommits = gh api "/repos/$slug/pulls/$prNumbers/commits" --paginate --jq '.[] | select(.commit.message | test("62310815\\+github-advanced-security\\[bot\\]@users.noreply.github.com")) | .sha'
    $isFixed = $prCommits.Count -gt 0


    $prNumbers | ForEach-Object {
        $prComments = gh api "/repos/$slug/pulls/$_/comments?since=2023-11-01T00:00:00Z" --paginate --jq '.[] | select(.user.id == 62310815 )' | ConvertFrom-Json
        Write-Debug "🔍 #$($prComments.Count) comments -  PR https://github.com/$slug/pull/$_"
        $prComments | ForEach-Object {
            # Fixed - Undocumented ... when FIXING an autofix it sets line and position to "null" (PS JSON "null" -> $null)
            # Issues
            # - also present in condition: "Unable to commit as this autofix suggestion is now outdated"

            # OPEN Issues
            # - Autofixes with an error also show up: Copilot could not generate an autofix suggestion for this alert. Try pushing a new commit or if the problem persists contact support.
            # - Autofixes without supported query also show up: Rule js/hardcoded-credentials is not supported by autofix

            Write-Host "🔧 $($isFixed ? "FIXED": $($_.line -eq $null -and $_.position -eq $null ? "Potentially FIXED" : " Potentially OPEN")) Autofix: $($_.body.Substring(2,$_.body.IndexOf("`n`n")-2)) - $($_._links.html.href)"
        }
    }
}

Write-Progress -Activity "Processing Repositories" -Status "Completed" -Completed