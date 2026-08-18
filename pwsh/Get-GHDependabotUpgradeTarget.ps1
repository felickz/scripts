<#
.SYNOPSIS
    Reports the lowest version to upgrade each vulnerable dependency to, from open Dependabot alerts.

.DESCRIPTION
    The Dependabot alerts UI lists one alert per vulnerability, so a dependency with many CVEs
    appears as many separate rows. This groups them by package and answers the only question that
    matters when remediating: what one version do I move to?

    Dependabot alerts are already scoped to the versions the repository actually uses, so no
    advisory version-range matching is needed - group by package and take the highest
    first_patched_version.

    Check the NoFix column. If it is greater than zero, at least one alert for that package has no
    published patch, so NO upgrade clears them all and it needs a different mitigation. Taking the
    max fix version alone is blind to this and returns a confident-looking version that still
    leaves an alert open.

    All the logic lives in the jq filter below, which is portable. To run it directly in bash, zsh,
    git-bash or pwsh without this script, see the one-liner in .NOTES.

.PARAMETER Repo
    Repository in OWNER/REPO format.

.PARAMETER State
    Alert state to report on. Defaults to open.

.EXAMPLE
    ./Get-GHDependabotUpgradeTarget.ps1 -Repo octo-org/octo-repo

.EXAMPLE
    ./Get-GHDependabotUpgradeTarget.ps1 -Repo octo-org/octo-repo | Export-Csv upgrades.csv -NoTypeInformation

.NOTES
    Requires the jq CLI (winget install jqlang.jq / brew install jq / sudo apt install jq).

    Equivalent portable one-liner - identical output, no PowerShell required:

    gh api --paginate '/repos/OWNER/REPO/dependabot/alerts?state=open&per_page=100' | jq -rs 'flatten | group_by(.dependency.package.name) | map({pkg:.[0].dependency.package.name, eco:.[0].dependency.package.ecosystem, alerts:length, nofix:([.[]|select(.security_vulnerability.first_patched_version==null)]|length), fix:([.[].security_vulnerability.first_patched_version.identifier|select(.)]|map({v:.,k:[splits("[.+-]")|select(test("^[0-9]+$"))|tonumber]})|sort_by(.k)|last.v)}) | sort_by(-.alerts) | (["PACKAGE","ECOSYSTEM","ALERTS","NOFIX","UPGRADE_TO"], (.[] | [.pkg,.eco,.alerts,.nofix,.fix])) | @tsv'

    If gh api returns 404, the token needs the security_events scope:
    gh auth refresh -h github.com -s security_events
#>
param(
    [Parameter(Mandatory = $true)]
    [string]$Repo,

    [ValidateSet('open', 'fixed', 'dismissed', 'auto_dismissed')]
    [string]$State = 'open'
)

if (-not (Get-Command jq -ErrorAction SilentlyContinue)) {
    throw "jq is required but was not found on PATH. Install it with 'winget install jqlang.jq', 'brew install jq' or 'sudo apt install jq'."
}

# -s slurps gh's per-page arrays into one array and flatten merges them, so grouping sees every
# page. Grouping inside --jq instead would silently produce per-page results on any repo with more
# than 100 alerts, and gh rejects --slurp when it is combined with --jq.
$filter = @'
flatten
| group_by(.dependency.package.name)
| map({
    Package:   .[0].dependency.package.name,
    Ecosystem: .[0].dependency.package.ecosystem,
    Alerts:    length,
    Severity:  ([.[].security_advisory.severity] | group_by(.) | sort_by(-length)
                 | map("\(.[0])=\(length)") | join(" ")),
    NoFix:     ([.[] | select(.security_vulnerability.first_patched_version == null)] | length),

    # Sort on the numeric segments, never the raw string: "1.4.9" sorts above "1.4.21"
    # lexicographically. Splitting on [.+-] also keeps build suffixes like 1.4.14-java7
    # from corrupting the key.
    UpgradeTo: ([.[].security_vulnerability.first_patched_version.identifier | select(.)]
                 | map({ v: ., k: [splits("[.+-]") | select(test("^[0-9]+$")) | tonumber] })
                 | sort_by(.k) | last | .v)
  })
| sort_by(-.Alerts)
'@

$results = gh api --paginate "/repos/$Repo/dependabot/alerts?state=$State&per_page=100" |
    jq -s $filter |
    ConvertFrom-Json

if (-not $results) {
    Write-Host "`n✓ No $State Dependabot alerts in $Repo" -ForegroundColor Green
    return
}

$results | Format-Table Package, Ecosystem, Alerts, Severity, NoFix, UpgradeTo -AutoSize | Out-Host

$blocked = @($results | Where-Object { $_.NoFix -gt 0 })
if ($blocked) {
    Write-Host "⚠️  $($blocked.Count) package(s) have alerts with no published fix - no upgrade clears them all:" -ForegroundColor Yellow
    $blocked | ForEach-Object { Write-Host "   $($_.Package) - $($_.NoFix) of $($_.Alerts) alert(s)" }
    Write-Host ''
}

$results
