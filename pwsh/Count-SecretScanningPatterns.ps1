# Install the PowerShell-yaml module if not already installed
if (-not (Get-Module -Name PowerShell-yaml -ListAvailable)) {
    Install-Module -Name PowerShell-yaml -Scope CurrentUser
}

# Read the YAML file from https://github.com/github/docs/blob/main/data/secret-scanning.yml
$url = 'https://raw.githubusercontent.com/github/docs/main/data/secret-scanning.yml'
$data = Invoke-RestMethod -Uri $url | ConvertFrom-Yaml

$inventory = @()
foreach ($node in $data) {
    $inventory += New-Object PSObject -Property @{
        'Provider'           = $node.provider
        'SecretType'        = $node.secretType
        'HasPushProtection' = $node.hasPushProtection
        #'OrigHasValidityCheck' = $node.hasValidityCheck
        'HasValidityCheck'  = $node.hasValidityCheck.ToString() -ne 'False'
    }

}

#$inventory | Format-Table -AutoSize

$Providers = $inventory | Select-Object -Property Provider -Unique
$Push = $inventory | Where-Object { $_.HasPushProtection -eq $true }  | Measure-Object | Select-Object -Property Count
$Validity = $inventory | Where-Object { $_.HasValidityCheck -eq $true }  | Measure-Object | Select-Object -Property Count

Write-Host "Secret Scanning Inventory  $($(Get-Date -AsUTC).ToString('u'))"
Write-Host "Number of Secret Types: $($inventory.Count)"
Write-Host "Number of Unique Providers: $($Providers.Count)"
Write-Host "Number of Secret Types with Push Protection: $($Push.Count)"
Write-Host "Number of Secret Types with Validity Check: $($Validity.Count)"
Write-Host "Non-Partner Patterns: [8](https://docs.github.com/en/enterprise-cloud@latest/code-security/secret-scanning/secret-scanning-patterns#non-provider-patterns)"
Write-Host "See: [Inventory Commit History](https://github.com/github/docs/commits/main/data/secret-scanning.yml) and [Secret Scanning Changelog](https://github.blog/changelog/label/secret-scanning)"