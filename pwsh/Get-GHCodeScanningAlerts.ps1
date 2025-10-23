# https://docs.github.com/en/rest/code-scanning/code-scanning?apiVersion=2022-11-28#list-code-scanning-alerts-for-a-repository
# ex: ref=refs/tags/v23
$json = gh api "/repos/vulna-felickz/juice-shop/code-scanning/alerts?tool_name=CodeQL&ref=refs/tags/v23" --paginate -q '.[] | select(.rule.security_severity_level | IN("critical", "high", "medium")) | {name: .rule.name, severity: .rule.security_severity_level, created_at: .created_at, number: .number}'

# Parse the JSON data
$alerts = $json | ConvertFrom-Json

#SLA
$severityDays = @{
    "critical" = 7
    "high"     = 30
    "medium"   = 90
    "low"      = 180
    #Quality Severities and SARIF integrations (not supported here, need to pull in `severity` and normalize)
    "error"    = 30
    "warning"  = 90
    "note"     = 180
}

# "SLA Days"         = $severityDays[$alert.severity]
# "Days overdue"     = $alert.state -ne "active" ? 0 : [Math]::Max([int]((Get-Date).ToUniversalTime().AddDays(-$severityDays[$alert.severity]) - ($alert.firstSeenDate)).TotalDays, 0)

#loop through all alerts and check if any are overdue to meet sla
$slaMet = $true
foreach($alert in $alerts) {
    # "Days overdue"
    $daysOverdue = [Math]::Max([int]((Get-Date).ToUniversalTime().AddDays(-$severityDays[$alert.severity]) - ($alert.created_at)).TotalDays, 0)

    if($daysOverdue -gt 0) {
        $slaMet = $false
        Write-Warning "⚠️  $daysOverdue days overdue (Alert #$($alert.number) created $($alert.created_at) - $($alert.severity) SLA: $($severityDays[$($alert.severity)]) days)"
    }
}

if(!$slaMet)
{
    Write-Error "❌ SLA has been breached for one or more alerts"
    exit 1
}
else
{
    Write-Host "✅ SLA has been met for all alerts"
}