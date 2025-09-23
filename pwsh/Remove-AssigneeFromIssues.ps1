# Remove a specific GitHub user from issue assignees
# Usage: .\Remove-AssigneeFromIssues.ps1 -Repository "owner/repo" -Username "username" [-AuditOnly] [-State "open"]
# Or:    .\Remove-AssigneeFromIssues.ps1 -Organization "orgname" -Username "username" [-AuditOnly] [-State "open"]
# NOTE: this will fail for archived repositories or if you do not have permission to edit issues in the repo

param(

    # [Parameter(Mandatory = $true)]
    [string]$Repository,

    # [Parameter(Mandatory = $true)]
    [string]$Organization

    [Parameter(Mandatory = $true)]
    [string]$Username ,

    [switch]$AuditOnly = $false,

    [ValidateSet("open", "closed", "all")]
    [string]$State = "open"
)

# Validate GitHub CLI is authenticated
try {
    $auth = & gh auth token
    if (-not $auth) {
        Write-Error "❌ GitHub CLI authentication required. Please run 'gh auth login' first."
        exit 1
    }
}
catch {
    Write-Error "❌ GitHub CLI not found or not authenticated. Please install GitHub CLI and run 'gh auth login'."
    exit 1
}

# Validate parameters
if (-not $Repository -and -not $Organization) {
    Write-Error "❌ Either -Repository or -Organization parameter must be provided."
    exit 1
}

if ($Repository -and $Organization) {
    Write-Error "❌ Cannot specify both -Repository and -Organization parameters. Choose one."
    exit 1
}

# Get list of repositories to process
$repositories = @()
if ($Organization) {
    Write-Host "🏢 Fetching repositories from organization '$Organization'..." -ForegroundColor Yellow
    try {
        $orgRepos = gh api "/orgs/$Organization/repos" --paginate | ConvertFrom-Json
        $repositories = $orgRepos | ForEach-Object { "$Organization/$($_.name)" }
        Write-Host "📊 Found $($repositories.Count) repositories in organization '$Organization'" -ForegroundColor Cyan
    }
    catch {
        Write-Error "❌ Failed to fetch repositories from organization '$Organization'. Please check organization name and permissions."
        exit 1
    }
}
else {
    $repositories = @($Repository)
}

Write-Host "🔍 Searching for issues assigned to '$Username'..." -ForegroundColor Yellow
Write-Host "Mode: $(if ($AuditOnly) { "AUDIT ONLY" } else { "REMOVE ASSIGNEES" })" -ForegroundColor $(if ($AuditOnly) { "Green" } else { "Red" })
Write-Host ""

# Initialize results collection
$allResults = @()
$totalIssuesFound = 0

foreach ($repo in $repositories) {
    Write-Host "🔎 Processing repository: $repo" -ForegroundColor Cyan

    # Get all issues assigned to the specified user
    try {
        $issues = gh api "/repos/$repo/issues?assignee=$Username&state=$State" --paginate | ConvertFrom-Json
    }
    catch {
        Write-Warning "❌ Failed to fetch issues from repository '$repo'. Skipping..."
        continue
    }

    if ($issues.Count -eq 0) {
        Write-Host "  ✅ No issues found assigned to '$Username'" -ForegroundColor Green
        continue
    }

    Write-Host "  📊 Found $($issues.Count) issue$(if ($issues.Count -ne 1) { "s" }) assigned to '$Username'" -ForegroundColor Yellow
    $totalIssuesFound += $issues.Count

    foreach ($issue in $issues) {
        $beforeAssignees = $issue.assignees | ForEach-Object { $_.login }
        $afterAssignees = @($beforeAssignees | Where-Object { $_ -ne $Username })

        # Create issue URL
        $issueUrl = $issue.html_url

        # Create result object
        $result = [PSCustomObject]@{
            Repository = $repo
            Issue = "#$($issue.number): $($issue.title)"
            IssueUrl = $issueUrl
            BeforeAssignees = ($beforeAssignees -join ", ")
            AfterAssignees = ($afterAssignees -join ", ")
            Status = ""
        }

        if (-not $AuditOnly) {
            # Actually remove the assignee
            try {
                # Ensure we always have an array for the API call
                $assigneePayload = @{
                    assignees = @($afterAssignees)
                } | ConvertTo-Json -Depth 2

                Write-Host "    🔄 Updating issue #$($issue.number) - Removing '$Username'..." -ForegroundColor Yellow
                Write-Host "       Before: $($beforeAssignees -join ', ')" -ForegroundColor Gray
                Write-Host "       After:  $($afterAssignees -join ', ')" -ForegroundColor Gray

                # Use temporary file to avoid PowerShell pipeline issues
                $tempFile = [System.IO.Path]::GetTempFileName()
                $assigneePayload | Out-File -FilePath $tempFile -Encoding UTF8

                $apiResult = gh api "/repos/$repo/issues/$($issue.number)" -X PATCH --input $tempFile 2>&1
                Remove-Item -Path $tempFile -Force

                if ($LASTEXITCODE -eq 0) {
                    $result.Status = "✅ Removed"
                    Write-Host "    ✅ Successfully removed '$Username' from issue #$($issue.number)" -ForegroundColor Green
                } else {
                    $result.Status = "❌ Failed"
                    Write-Warning "    ❌ Failed to remove '$Username' from issue #$($issue.number)"
                    Write-Warning "       GitHub API Error: $apiResult"
                }
            }
            catch {
                $result.Status = "❌ Failed"
                Write-Warning "    ❌ Failed to remove '$Username' from issue #$($issue.number)"
                Write-Warning "       Exception: $($_.Exception.Message)"
                if ($_.Exception.InnerException) {
                    Write-Warning "       Inner Exception: $($_.Exception.InnerException.Message)"
                }
            }
        }
        else {
            $result.Status = "📋 Would remove"
            Write-Host "    📋 Would remove '$Username' from issue #$($issue.number)" -ForegroundColor Cyan
            Write-Host "       Before: $($beforeAssignees -join ', ')" -ForegroundColor Gray
            Write-Host "       After:  $($afterAssignees -join ', ')" -ForegroundColor Gray
        }

        $allResults += $result
    }
}

# Check if any issues were found across all repositories
if ($totalIssuesFound -eq 0) {
    Write-Host "✅ No issues found assigned to '$Username' across all repositories" -ForegroundColor Green
    exit 0
}

# Display summary table
Write-Host ""
Write-Host "📈 Summary Report:" -ForegroundColor Cyan
Write-Host ""

$allResults | Format-Table -Property Repository, Issue, BeforeAssignees, AfterAssignees, Status -Wrap -AutoSize

# Display clickable links
Write-Host ""
Write-Host "🔗 Issue Links:" -ForegroundColor Cyan
foreach ($result in $allResults) {
    Write-Host "  $($result.Issue): $($result.IssueUrl)"
}

# Final summary
Write-Host ""
if ($AuditOnly) {
    Write-Host "📋 AUDIT COMPLETE: Found $($allResults.Count) issue$(if ($allResults.Count -ne 1) { "s" }) across $($repositories.Count) repositor$(if ($repositories.Count -ne 1) { "ies" } else { "y" }) that would have '$Username' removed as assignee" -ForegroundColor Yellow
    Write-Host "💡 Run without -AuditOnly flag to actually remove assignees" -ForegroundColor Yellow
}
else {
    $successCount = ($allResults | Where-Object { $_.Status -eq "✅ Removed" }).Count
    $failCount = ($allResults | Where-Object { $_.Status -eq "❌ Failed" }).Count

    Write-Host "✅ REMOVAL COMPLETE: Successfully removed '$Username' from $successCount issue$(if ($successCount -ne 1) { "s" }) across $($repositories.Count) repositor$(if ($repositories.Count -ne 1) { "ies" } else { "y" })" -ForegroundColor Green
    if ($failCount -gt 0) {
        Write-Host "❌ Failed to remove from $failCount issue$(if ($failCount -ne 1) { "s" })" -ForegroundColor Red
    }
}