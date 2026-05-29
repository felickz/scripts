param(
    [Parameter(Mandatory = $true)]
    [string]$Enterprise,

    [Parameter(Mandatory = $true)]
    [string]$RunnerGroupName,

    [switch]$WhatIf
)

$ErrorActionPreference = "Stop"

function Invoke-GitHubApiJson {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Args
    )

    $output = & gh api @Args
    if ($LASTEXITCODE -ne 0) {
        throw "gh api failed: gh api $($Args -join ' ')"
    }

    if ([string]::IsNullOrWhiteSpace($output)) {
        return $null
    }

    return $output | ConvertFrom-Json
}

Write-Host "Enterprise: $Enterprise"
Write-Host "Runner group name: $RunnerGroupName"
Write-Host ""

# For Enterprise Cloud, this GraphQL query gets all org logins in the enterprise.
# gh api graphql automatically handles auth with your gh login/token.
$orgs = @()
$cursor = $null

do {
    $query = @'
query($enterprise: String!, $cursor: String) {
  enterprise(slug: $enterprise) {
    organizations(first: 100, after: $cursor) {
      nodes {
        login
      }
      pageInfo {
        hasNextPage
        endCursor
      }
    }
  }
}
'@

    $graphqlArgs = @(
        "graphql",
        "-f", "query=$query",
        "-f", "enterprise=$Enterprise"
    )

    if ($cursor) {
        $graphqlArgs += @(
            "-f", "cursor=$cursor"
        )
    }

    $result = Invoke-GitHubApiJson -Args $graphqlArgs

    if (-not $result.data.enterprise) {
        throw "Could not read enterprise '$Enterprise'. Check the enterprise slug and your permissions."
    }

    $pageOrgs = $result.data.enterprise.organizations.nodes.login
    if ($pageOrgs) {
        $orgs += $pageOrgs
    }

    $hasNextPage = $result.data.enterprise.organizations.pageInfo.hasNextPage
    $cursor = $result.data.enterprise.organizations.pageInfo.endCursor
}
while ($hasNextPage)

if (-not $orgs -or $orgs.Count -eq 0) {
    throw "No organizations found in enterprise '$Enterprise'."
}

Write-Host "Found $($orgs.Count) organization(s)." -ForegroundColor Green
Write-Host ""

$results = New-Object System.Collections.Generic.List[object]

foreach ($org in $orgs) {
    try {
        Write-Host "Processing org: $org" -ForegroundColor Cyan

        # List runner groups visible in the org, including inherited enterprise groups.
        $groups = Invoke-GitHubApiJson -Args @(
            "/orgs/$org/actions/runner-groups",
            "--paginate"
        )

        # gh api may return a single object with runner_groups.
        $runnerGroups = @()
        if ($groups.runner_groups) {
            $runnerGroups = @($groups.runner_groups)
        }
        elseif ($groups -is [System.Array]) {
            foreach ($g in $groups) {
                if ($g.runner_groups) {
                    $runnerGroups += @($g.runner_groups)
                }
            }
        }

        $group = $runnerGroups | Where-Object { $_.name -eq $RunnerGroupName } | Select-Object -First 1

        if (-not $group) {
            Write-Warning "Runner group '$RunnerGroupName' not found in org '$org'. Skipping."
            $results.Add([pscustomobject]@{
                org    = $org
                status = "not-found"
                id     = $null
                before = $null
                after  = $null
            })
            continue
        }

        $groupId = $group.id
        $beforeVisibility = $group.visibility

        Write-Host "  Found runner group id=$groupId visibility=$beforeVisibility inherited=$($group.inherited)" -ForegroundColor Yellow

        if ($beforeVisibility -eq "all") {
            Write-Host "  Already set to all repositories." -ForegroundColor Green
            $results.Add([pscustomobject]@{
                org    = $org
                status = "unchanged"
                id     = $groupId
                before = $beforeVisibility
                after  = "all"
            })
            continue
        }

        if ($WhatIf) {
            Write-Host "  WHATIF: would set visibility=all" -ForegroundColor Magenta
            $results.Add([pscustomobject]@{
                org    = $org
                status = "whatif"
                id     = $groupId
                before = $beforeVisibility
                after  = "all"
            })
            continue
        }

        # Update organization runner group repository access to all repos.
        # This is the key call.
        $updated = Invoke-GitHubApiJson -Args @(
            "--method", "PATCH",
            "/orgs/$org/actions/runner-groups/$groupId",
            "-f", "visibility=all"
        )

        Write-Host "  Updated visibility: $($updated.visibility)" -ForegroundColor Green

        $results.Add([pscustomobject]@{
            org    = $org
            status = "updated"
            id     = $groupId
            before = $beforeVisibility
            after  = $updated.visibility
        })
    }
    catch {
        Write-Warning "Failed for org '$org': $($_.Exception.Message)"
        $results.Add([pscustomobject]@{
            org    = $org
            status = "error"
            id     = $null
            before = $null
            after  = $null
        })
    }

    Write-Host ""
}

Write-Host "Summary:" -ForegroundColor Cyan
$results | Format-Table -AutoSize