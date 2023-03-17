<#
.SYNOPSIS
    Get a list of secret scanning alerts across the enterprise grouped by secret type and secret value
.DESCRIPTION

    This script will get a list of secret scanning alerts grouped by secret type and secret value.  This is useful for identifying secrets that are being used in multiple places in your enterprise.  This script will also mask the secret value in the output (first 4 chars are shown of secret).
.PARAMETER apiKey
    The GitHub API key to use for authentication.  (sample uses gh cli to get token)
.PARAMETER enterprise_name
    The name of the GitHub Enterprise instance to query.  (sample uses octodemo)
.EXAMPLE
    .\Get-SecretScanningGroupedAlerts.ps1 -apiKey $apiKey -enterprise_name $enterprise_name
#>

param (
    [Parameter]
    [string]$apiKey,
    [Parameter]
    [string]$enterprise_name
)

#only set if parameter is null
if (!$apiKey) {
    $apiKey = gh auth token
}
if (!$enterprise_name) {
    $enterprise_name = "octodemo"
}

#Mask the secret value in the output (first 4 chars are shown of secret)
Function Mask-String {
    param (
        [string]$inputString
    )

    $CommaIndex = $InputString.IndexOf(',')

    if($CommaIndex -eq -1) {
        return $InputString
    }

    $FirstPart = $InputString.Substring(0, $CommaIndex + 6)
    $LastPart = '*' * 5
    $OutputString = "$FirstPart$LastPart"

    return $OutputString
}

# Handle `Untrusted repository` prompt
Set-PSRepository PSGallery -InstallationPolicy Trusted

#check if GitHubActions module is installed
if (Get-Module -ListAvailable -Name GitHubActions -ErrorAction SilentlyContinue) {
    Write-ActionDebug "GitHubActions module is installed"
}
else {
    #directly to output here before module loaded to support Write-ActionInfo
    Write-Output "GitHubActions module is not installed.  Installing from Gallery..."
    Install-Module -Name GitHubActions
}

#GH Api Auth
$secureString = ($apiKey | ConvertTo-SecureString -AsPlainText -Force)
$cred = New-Object System.Management.Automation.PSCredential "username is ignored", $secureString
Set-GitHubAuthentication -Credential $cred
$secureString = $null # clear this out now that it's no longer needed
$cred = $null # clear this out now that it's no longer needed
$apiKey = $null # clear this out now that it's no longer needed

$alertsResponse = Invoke-GHRestMethod  -Method GET -Uri "https://api.github.com/enterprises/$enterprise_name/secret-scanning/alerts?per_page=100" -ExtendedResult $true
$alerts = $alertsResponse.result
while ($alertsResponse.nextLink) {
    $alertsResponse = Invoke-GHRestMethod -Method GET -Uri $alertsResponse.nextLink -ExtendedResult $true
    $alerts += $alertsResponse.result
}

$grouped = $alerts | group-object -property "secret_type", "secret" -NoElement 

# if only care about multiple alerts: | Where-Object { $_.Count -gt 1 }
Write-Output $grouped | Sort-Object -Property Count -Descending | Select-Object -Property Count, @{name="Name";expression={ Mask-String $_.Name }}


