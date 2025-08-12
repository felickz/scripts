# Parameters
param(
    [switch]$SkipPost = $false
)

# Install the PowerShell-yaml module if not already installed
if (-not (Get-Module -Name PowerShell-yaml -ListAvailable)) {
    Install-Module -Name PowerShell-yaml -Scope CurrentUser
}

# Ex: 3.15 > 3.5
function Compare-Version {
    param (
        [string]$leftVersion,
        [string]$rightVersion
    )

    $leftParts = $leftVersion -split '\.'
    $rightParts = $rightVersion -split '\.'

    for ($i = 0; $i -lt [math]::Max($leftParts.Length, $rightParts.Length); $i++) {
        $leftPart = if ($i -lt $leftParts.Length) { [int]$leftParts[$i] } else { 0 }
        $rightPart = if ($i -lt $rightParts.Length) { [int]$rightParts[$i] } else { 0 }

        if ($leftPart -gt $rightPart) { return 1 }
        if ($leftPart -lt $rightPart) { return -1 }
    }

    return 0
}


function ConvertAndEvaluateFormula {
    param (
        [string]$formula
    )

    # if formula contains "*", return true
    if ($formula -match '\*') { return $true }

    # Convert from standard comparison operators to PowerShell equivalents
    $convertedFormula = $formula -replace '>=', '-ge'
    $convertedFormula = $convertedFormula -replace '<=', '-le'
    $convertedFormula = $convertedFormula -replace '>', '-gt'
    $convertedFormula = $convertedFormula -replace '<', '-lt'
    $convertedFormula = $convertedFormula -replace '==', '-eq'
    $convertedFormula = $convertedFormula -replace '!=', '-ne'

    # Evaluate the formula safely
    $result = $false
    if ($convertedFormula -match '(.+?)\s*(-ge|-le|-gt|-lt|-eq|-ne)\s*(.+)') {
        $leftOperand = $matches[1]
        $operator = $matches[2]
        $rightOperand = $matches[3]

        switch ($operator) {
            '-ge' { $result = (Compare-Version $leftOperand $rightOperand) -ge 0 }
            '-le' { $result = (Compare-Version $leftOperand $rightOperand) -le 0 }
            '-gt' { $result = (Compare-Version $leftOperand $rightOperand) -gt 0 }
            '-lt' { $result = (Compare-Version $leftOperand $rightOperand) -lt 0 }
            '-eq' { $result = (Compare-Version $leftOperand $rightOperand) -eq 0 }
            '-ne' { $result = (Compare-Version $leftOperand $rightOperand) -ne 0 }
        }

    }

    # Return the result as a boolean
    return [bool]$result
}

# GitHub - Read the YAML file from https://github.com/github/docs/blob/main/src/secret-scanning/data/public-docs.yml
$url = 'https://raw.githubusercontent.com/github/docs/main/src/secret-scanning/data/public-docs.yml'
$data = Invoke-RestMethod -Uri $url | ConvertFrom-Yaml

$inventory = @()
foreach ($node in $data) {
    $inventory += New-Object PSObject -Property @{
        'Provider'          = $node.provider
        'SecretType'        = $node.secretType
        'HasPushProtection' = $node.hasPushProtection
        #'OrigHasValidityCheck' = $node.hasValidityCheck
        'HasValidityCheck'  = $node.hasValidityCheck.ToString() -ne 'False'
        'HasVariants'       = $node.isduplicate
        'Versions' = $node.versions
    }

}

#$inventory | Format-Table -AutoSize
$Providers = $inventory | Select-Object -Property Provider -Unique
$Push = $inventory | Where-Object { $_.HasPushProtection -eq $true }  | Measure-Object | Select-Object -Property Count
$Validity = $inventory | Where-Object { $_.HasValidityCheck -eq $true }  | Measure-Object | Select-Object -Property Count
$Variants = $inventory | Where-Object { $_.HasVariants -eq $true }  | Measure-Object | Select-Object -Property Count

# Find current GHES by splitting $inventory.Versions['ghes'] on '.' and finding the largest minor version (on [1])
$currentGHES = "3.$($inventory | ForEach-Object { $_.Versions["ghes"] -split '\.' | Where-Object { $_ -match '^\d+$' } | Select-Object -Last 1 } | Sort-Object { [int]$_ } -Descending | Select-Object -First 1)"
# build a list of ghes strings that are 3.4 and greater and ends with currentGHES
$GHESList = 4 .. ($currentGHES -split '\.')[1]
$GHESMajorVer = ($currentGHES -split '\.')[0]

# $inventory[0].Versions["ghes"] is in format ">=3.5" ... use that formula to compare with $currentGHES
$GHESInventory = @()
$GHESList | ForEach-Object {
    $GHESMinorVer = "$_"
    $count = $inventory | Where-Object { ConvertAndEvaluateFormula -formula "$GHESMajorVer.$GHESMinorVer$($_.Versions['ghes'])" } | Measure-Object | Select-Object -Property Count
    $GHESInventory += New-Object PSObject -Property @{
        'GHESVersion' = "$GHESMajorVer.$GHESMinorVer"
        'Count'       = $count.Count
    }
}


# Azure DevOps - provider table parsing
# Source: provider-table.md (markdown table => | Rule ID | Token Name | Push Protection | User Alerts | Validity Checking |)
function ConvertFrom-AdoProviderMarkdown {
    param(
        [string]$Markdown
    )
    $results = @()
    $lines = $Markdown -split "`n"
    foreach ($raw in $lines) {
        $line = $raw.Trim()
        if (-not $line.StartsWith('|')) { continue }
        if ($line -match '^\|\s*-+\s*\|') { continue } # separator

        # Try provider (5-column) format first: RuleID | TokenName | Push | User | Validity
        $matched = $false
        if (-not $matched -and $line -match '^\|\s*([^|]+?)\s*\|\s*([^|]+?)\s*\|\s*([^|]*)\|\s*([^|]*)\|\s*([^|]*)\|$') {
            $rule   = ($matches[1]).Trim()
            $token  = ($matches[2]).Trim()
            $push   = ($matches[3]).Trim()
            $user   = ($matches[4]).Trim()
            $valid  = ($matches[5]).Trim()
            $matched = $true
            $isNonProvider = $false
        }
        # Non-provider (4-column) format: RuleID | TokenName | User | Validity (no Push column)
        if (-not $matched -and $line -match '^\|\s*([^|]+?)\s*\|\s*([^|]+?)\s*\|\s*([^|]*)\|\s*([^|]*)\|$') {
            $rule   = ($matches[1]).Trim()
            $token  = ($matches[2]).Trim()
            $push   = ''  # absent
            $user   = ($matches[3]).Trim()
            $valid  = ($matches[4]).Trim()
            $matched = $true
            $isNonProvider = $true
        }

        if ($matched) {
            if ($rule -eq 'Rule ID') { continue }
            if (-not $rule) { continue }

            $test = { param($v) if (-not $v) { return $false } return $v -match '(?i)green|checkmark|true|yes' }
            $results += [pscustomobject]@{
                RuleID           = $rule
                TokenName        = $token
                PushProtection   = $(if ($isNonProvider) { $false } else { & $test $push })
                UserAlerts       = (& $test $user)
                ValidityChecking = (& $test $valid)
                IsNonProvider    = $isNonProvider
            }
        }
    }
    return $results
}

$ADOProviderTable = Invoke-RestMethod -Uri 'https://raw.githubusercontent.com/MicrosoftDocs/azure-devops-docs/refs/heads/main/docs/repos/security/includes/provider-table.md' | Out-String
$ADOProviders = ConvertFrom-AdoProviderMarkdown -Markdown $ADOProviderTable
$ADOProvidersPush = $ADOProviders | Where-Object { $_.PushProtection }
$ADOProvidersValidity = $ADOProviders | Where-Object { $_.ValidityChecking }


## NON PROVIDER ADO
# - https://raw.githubusercontent.com/MicrosoftDocs/azure-devops-docs/refs/heads/main/docs/repos/security/includes/non-provider-table.md
$ADONonProviderTable = Invoke-RestMethod -Uri 'https://raw.githubusercontent.com/MicrosoftDocs/azure-devops-docs/refs/heads/main/docs/repos/security/includes/non-provider-table.md' | Out-String
$ADONonProviders = ConvertFrom-AdoProviderMarkdown -Markdown $ADONonProviderTable
$ADONonProvidersPush = $ADONonProviders | Where-Object { $_.PushProtection }
$ADONonProvidersValidity = $ADONonProviders | Where-Object { $_.ValidityChecking }


$comment = @"
# GitHub

| GHAS Secret Scanning Inventory |$($(Get-Date -AsUTC).ToString('u')) |
| --- | --- |
| Number of Partner Secret Types | $($inventory.Count) ($($Variants.Count) with variants) |
| Number of Unique Partner Providers | $($Providers.Count) |
| Number of Secret Types with Push Protection | $($Push.Count) |
| Number of Secret Types with Validity Check | $($Validity.Count) |
| Non-Partner Patterns | [8](https://docs.github.com/en/enterprise-cloud@latest/code-security/secret-scanning/secret-scanning-patterns#non-provider-patterns) (0 with validity checks) |
| Inventory Commit History | [Docs](https://github.com/github/docs/blob/main/src/secret-scanning/data/public-docs.yml)
| Secret Scanning Changelog | [Changelog](https://github.blog/changelog/label/secret-scanning) |

| GHES Version | Count |
| --- | --- |
$($GHESInventory | ForEach-Object { "| $($_.GHESVersion) | $($_.Count) |" } | Out-String)

# Azure DevOps
| GHAzDO Secret Scanning Inventory |$($(Get-Date -AsUTC).ToString('u')) |
| --- | --- |
| Number of Partner Secret Types | [$($ADOProviders.Count)](https://learn.microsoft.com/en-us/azure/devops/repos/security/github-advanced-security-secret-scan-patterns?view=azure-devops#partner-provider-patterns) |
| Number of Secret Types with Push Protection | $($ADOProvidersPush.Count + $ADONonProvidersPush.Count) |
| Number of Secret Types with Validity Check | $($ADOProvidersValidity.Count + $ADONonProvidersValidity.Count) |
| Non-Partner Patterns | [$($ADONonProviders.Count)](https://learn.microsoft.com/en-us/azure/devops/repos/security/github-advanced-security-secret-scan-patterns?view=azure-devops#non-provider-patterns) ( $($ADONonProvidersValidity.Count) with validity checks) |
| Inventory Commit History | [Docs](https://raw.githubusercontent.com/MicrosoftDocs/azure-devops-docs/refs/heads/main/docs/repos/security/includes/provider-table.md) [Docs NonPartner](https://raw.githubusercontent.com/MicrosoftDocs/azure-devops-docs/refs/heads/main/docs/repos/security/includes/non-provider-table.md)
| Secret Scanning Changes | [Commits](https://github.com/MicrosoftDocs/azure-devops-docs/commits/main/docs/repos/security/includes/provider-table.md) [Commits Non-Partner](https://github.com/MicrosoftDocs/azure-devops-docs/commits/main/docs/repos/security/includes/non-provider-table.md)|
"@

Write-Host $comment


## Use the GH CLI api to post a new comment to the gist: https://gist.github.com/felickz/9688dd0f5182cab22386efecfa41eb74
if (-not $SkipPost) {
    gh api /gists/9688dd0f5182cab22386efecfa41eb74/comments -f "body=$comment"
}
