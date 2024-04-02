# Description: This gh cli script will dismiss all open CodeQL alerts for hardcoded credentials that match a specific value and name.
# - limited to cs/hardcoded-credentials currently
# usage: pwsh Dismiss-GHASHardcodedCredAlerts.ps1 -Name "Username" -Value "test"
param (
    [string]$Name = "Username",
    [string]$Value = "test"
)

gh api --method GET /repos/octodemo/ocelot/code-scanning/alerts --paginate --jq '.[] | select(.state == "open" and .tool.name == "CodeQL" and .rule.id == "cs/hardcoded-credentials")' `
| ForEach-Object {
    $alert = $_ | ConvertFrom-Json
    $text = $alert.most_recent_instance.message.text

    $regex = 'The hard-coded value "(?<valueGroup>.*?)" flows to the setter call argument in (?<nameGroup>\w+)\.'
    if ($text -match $regex -and $matches['valueGroup'] -like $Value -and $matches['nameGroup'] -like $Name) {
        "Dismissed #$($alert.number) - $text ($($alert.html_url))" | Write-Host
        $null = gh api --method PATCH $alert.url -f state=dismissed -f dismissed_reason='false positive' -f dismissed_comment="Automated dismissal for hardcoded credential $Name/$Value."
    }
}