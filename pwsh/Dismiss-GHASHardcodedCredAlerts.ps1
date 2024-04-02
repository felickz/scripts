# Description: This gh cli script will dismiss all open CodeQL alerts for hardcoded credentials that match a specific value and name.
# Supports csharp and javascript currently
# - go/hardcoded-credentials does not output secret value in alert - "Hard-coded secret."
# - py/hardcoded-credentials does not output secret value in alert - "This hardcoded value is used as credentials."
# - rb/hardcoded-credentials does not output secret value in alert - "This hardcoded value is used as credentials."
# - java/hardcoded-credential-api-call does not output secret value - "Hard-coded value flows to sensitive API call."
# usage: pwsh Dismiss-GHASHardcodedCredAlerts.ps1 -Organization "myorg" -Repository "myrepo" -Name "Username" -Value "test"
param (
    [string]$Organization = "octodemo",
    [string]$Repository = "ldennington-ghas",
    [string]$Name = "Username",
    [string]$Value = "test"
)

gh api --method GET /repos/$Organization/$Repository/code-scanning/alerts --paginate --jq '.[] | select(.state == "open" and .tool.name == "CodeQL" and .rule.id == "cs/hardcoded-credentials")' `
| ForEach-Object {
    $alert = $_ | ConvertFrom-Json
    $text = $alert.most_recent_instance.message.text

    $regex = 'The hard-coded value "(?<valueGroup>.*?)" flows to the setter call argument in (?<nameGroup>\w+)\.'
    if ($text -match $regex -and $matches['valueGroup'] -like $Value -and $matches['nameGroup'] -like $Name) {
        "Dismissed #$($alert.number) - $text ($($alert.html_url))" | Write-Host
        $null = gh api --method PATCH $alert.url -f state=dismissed -f dismissed_reason='false positive' -f dismissed_comment="Automated dismissal for hardcoded credential $Name/$Value."
    }
}

# usage: pwsh Dismiss-GHASHardcodedCredAlerts.ps1 -Repository "ldennington-ghas" -Name "user name" -Value "dbuser"
#js/hardcoded-credential - The hard-coded value "dbuser" is used as user name.
# type exs: 'user name', 'password', 'credentials', 'token', 'key', 'authorization header'
gh api --method GET /repos/$Organization/$Repository/code-scanning/alerts --paginate --jq '.[] | select(.state == "open" and .tool.name == "CodeQL" and .rule.id == "js/hardcoded-credentials")' `
| ForEach-Object {
    $alert = $_ | ConvertFrom-Json
    $text = $alert.most_recent_instance.message.text
    $regex = 'The hard-coded value "(?<valueGroup>.*?)" is used as (?<nameGroup>[\w\s]+)\.'
    if ($text -match $regex -and $matches['valueGroup'] -like $Value -and $matches['nameGroup'] -like $Name) {
        "Dismissed #$($alert.number) - $text ($($alert.html_url))" | Write-Host
        $null = gh api --method PATCH $alert.url -f state=dismissed -f dismissed_reason='false positive' -f dismissed_comment="Automated dismissal for hardcoded credential $Name/$Value."
    }
}