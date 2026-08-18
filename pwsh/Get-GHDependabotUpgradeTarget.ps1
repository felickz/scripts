<#
.SYNOPSIS
    Reports the minimum version to upgrade each vulnerable dependency to, from open Dependabot alerts.

.DESCRIPTION
    Dependabot alerts are already scoped to the versions the repository actually uses, so no
    advisory version-range math is needed here. Group the open alerts by package and take the
    highest first_patched_version - that is the lowest version clearing every alert for it.

    Check the NoFix column. If it is greater than zero, at least one alert for that package has
    no published patch, so NO upgrade clears them all and the finding needs another mitigation.

    The padded SortKey exists because version identifiers must not be compared as plain strings:
    "1.4.9" sorts above "1.4.21" lexicographically. jq emits a zero-padded numeric key instead.

    Note: --jq is applied per page, so the filter below is deliberately element-wise and the
    grouping happens in PowerShell. Grouping inside jq would silently produce per-page results
    on any repository with more than 100 open alerts (--slurp is not supported with --jq).

.PARAMETER Repo
    Repository in OWNER/REPO format.

.EXAMPLE
    ./Get-GHDependabotUpgradeTarget.ps1 -Repo octo-org/octo-repo

.EXAMPLE
    ./Get-GHDependabotUpgradeTarget.ps1 -Repo octo-org/octo-repo | Export-Csv upgrades.csv -NoTypeInformation
#>
param(
    [Parameter(Mandatory = $true)]
    [string]$Repo
)

$jq = '.[] | {
    Package: .dependency.package.name,
    Ecosystem: .dependency.package.ecosystem,
    Severity: .security_advisory.severity,
    Fix: .security_vulnerability.first_patched_version.identifier,
    SortKey: ([(.security_vulnerability.first_patched_version.identifier // "")
               | splits("[.+-]") | select(test("^[0-9]+$")) | ("00000" + .)[-6:]] | join("."))
}'

$alerts = gh api --paginate "/repos/$Repo/dependabot/alerts?state=open&per_page=100" --jq $jq |
    ForEach-Object { $_ | ConvertFrom-Json }

if (-not $alerts) {
    Write-Host "`n✓ No open Dependabot alerts in $Repo" -ForegroundColor Green
    return
}

$results = $alerts | Group-Object Package | ForEach-Object {
    $fixable = @($_.Group | Where-Object { $_.Fix })
    [PSCustomObject]@{
        Package   = $_.Name
        Ecosystem = $_.Group[0].Ecosystem
        Alerts    = $_.Count
        Severity  = (($_.Group | Group-Object Severity | Sort-Object Count -Descending |
                      ForEach-Object { "$($_.Name)=$($_.Count)" }) -join ' ')
        NoFix     = $_.Count - $fixable.Count
        UpgradeTo = ($fixable | Sort-Object SortKey | Select-Object -Last 1).Fix
    }
} | Sort-Object Alerts -Descending

$results | Format-Table Package, Ecosystem, Alerts, Severity, NoFix, UpgradeTo -AutoSize | Out-Host

$blocked = @($results | Where-Object { $_.NoFix -gt 0 })
if ($blocked) {
    Write-Host "⚠️  $($blocked.Count) package(s) have alerts with no published fix - no upgrade clears them all:" -ForegroundColor Yellow
    $blocked | ForEach-Object { Write-Host "   $($_.Package) - $($_.NoFix) of $($_.Alerts) alert(s)" }
    Write-Host ''
}

$results
