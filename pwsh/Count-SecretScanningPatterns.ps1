# Parameters
param(
    [switch]$SkipPost = $false
)

# Track errors globally
$script:hasErrors = $false

# Install the PowerShell-yaml module if not already installed
if (-not (Get-Module -Name PowerShell-yaml -ListAvailable)) {
    Install-Module -Name PowerShell-yaml -Scope CurrentUser
}

# GitHub - Read the YAML file from https://github.com/github/docs/blob/main/src/secret-scanning/data/pattern-docs/ghec/public-docs.yml
$url = 'https://raw.githubusercontent.com/github/docs/main/src/secret-scanning/data/pattern-docs/ghec/public-docs.yml'
try {
    $data = Invoke-RestMethod -Uri $url | ConvertFrom-Yaml
} catch {
    Write-Error "Failed to fetch GitHub GHEC data from $url : $_"
    $script:hasErrors = $true
    $data = @()
}

$inventory = @()
foreach ($node in $data) {
    $inventory += New-Object PSObject -Property @{
        'Provider'          = $node.provider
        'SecretType'        = $node.secretType
        'HasPushProtection' = $node.hasPushProtection
        'HasValidityCheck'  = $node.hasValidityCheck.ToString() -ne 'False'
        'HasVariants'       = $node.isduplicate
        'Base64Supported'   = $node.base64Supported
    }
}

#$inventory | Format-Table -AutoSize
$Providers = $inventory | Select-Object -Property Provider -Unique
$Push = $inventory | Where-Object { $_.HasPushProtection -eq $true }  | Measure-Object | Select-Object -Property Count
$Validity = $inventory | Where-Object { $_.HasValidityCheck -eq $true }  | Measure-Object | Select-Object -Property Count
$Variants = $inventory | Where-Object { $_.HasVariants -eq $true }  | Measure-Object | Select-Object -Property Count
$Base64Supported = $inventory | Where-Object { $_.Base64Supported -eq $true }  | Measure-Object | Select-Object -Property Count

# Get GHES versions from the pattern-docs folder structure
$GHESInventory = @()
try {
    $ghesVersionsResponse = gh api /repos/github/docs/contents/src/secret-scanning/data/pattern-docs --jq '.[].name' 2>&1
    $ghesVersions = $ghesVersionsResponse | Where-Object { $_ -match '^ghes-\d+\.\d+$' } | ForEach-Object { $_ -replace 'ghes-', '' } | Sort-Object { [version]$_ }

    foreach ($ghesVer in $ghesVersions) {
        $ghesUrl = "https://raw.githubusercontent.com/github/docs/main/src/secret-scanning/data/pattern-docs/ghes-$ghesVer/public-docs.yml"
        try {
            $ghesData = Invoke-RestMethod -Uri $ghesUrl | ConvertFrom-Yaml
            $GHESInventory += New-Object PSObject -Property @{
                'GHESVersion' = $ghesVer
                'Count'       = $ghesData.Count
            }
        } catch {
            Write-Warning "Failed to fetch GHES $ghesVer data: $_"
        }
    }
} catch {
    Write-Error "Failed to get GHES versions list: $_"
    $script:hasErrors = $true
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


## GITHUB NON PROVIDER PATTERNS
# - https://raw.githubusercontent.com/github/docs/refs/heads/main/content/code-security/reference/secret-security/supported-secret-scanning-patterns.md
$GHNonProviderMarkdown = $null
try {
    $GHNonProviderMarkdown = Invoke-RestMethod -Uri 'https://raw.githubusercontent.com/github/docs/refs/heads/main/content/code-security/reference/secret-security/supported-secret-scanning-patterns.md' | Out-String
} catch {
    Write-Error "Failed to fetch GitHub non-provider patterns markdown: $_"
    $script:hasErrors = $true
}

# Parse the markdown to extract non-provider patterns
$GHNonProviderPatterns = @()
$GHCopilotPatterns = @()

if ($GHNonProviderMarkdown) {
    $inNonProviderSection = $false
    $inCopilotSection = $false
    $lines = $GHNonProviderMarkdown -split "`n"

    foreach ($line in $lines) {
        $trimmedLine = $line.Trim()

        # Detect the start of the Non-provider patterns section
        if ($trimmedLine -match '^###\s+Non-provider patterns') {
            $inNonProviderSection = $true
            $inCopilotSection = $false
            continue
        }

        # Detect the start of the Copilot secret scanning section (using data variable reference)
        if ($trimmedLine -match '^\{\%\s*data variables\.secret-scanning\.copilot-secret-scanning' -or $trimmedLine -match '^###.*copilot.*secret.*scanning') {
            $inCopilotSection = $true
            $inNonProviderSection = $false
            continue
        }

        # Exit when we hit the next main section
        if (($inNonProviderSection -or $inCopilotSection) -and $trimmedLine -match '^###\s+' -and $trimmedLine -notmatch 'copilot') {
            $inNonProviderSection = $false
            $inCopilotSection = $false
        }

        # Parse table rows in the non-provider section
        if ($inNonProviderSection -and $trimmedLine -match '^\|\s*Generic\s*\|\s*([^|]+?)\s*\|') {
            $tokenName = $matches[1].Trim()
            if ($tokenName -and $tokenName -ne 'Token') {
                $GHNonProviderPatterns += $tokenName
            }
        }

        # Parse table rows in the Copilot section
        if ($inCopilotSection -and $trimmedLine -match '^\|\s*(Generic)?\s*\|\s*([^|]+?)\s*\|') {
            $tokenName = $matches[2].Trim()
            if ($tokenName -and $tokenName -ne 'Token' -and $tokenName -ne 'Provider') {
                $GHCopilotPatterns += $tokenName
            }
        }
    }
}

# Use unique counts because the markdown contains separate tables for GHEC and GHES with the same patterns listed.
# This is NOT the same as "variants" (multiple versions of the same pattern format) - those are tracked separately
# in the main inventory. Here we're just deduplicating patterns that appear in both platform-specific tables.
$GHNonProviderCount = ($GHNonProviderPatterns | Select-Object -Unique).Count
$GHCopilotCount = ($GHCopilotPatterns | Select-Object -Unique).Count


$comment = @"
# GitHub

| Secret Protection Inventory |$($(Get-Date -AsUTC).ToString('u')) |
| --- | --- |
| Number of Partner Secret Types | $($inventory.Count) ($($Variants.Count) with variants) |
| Number of Unique Partner Providers | $($Providers.Count) |
| Number of Secret Types with Push Protection | $($Push.Count) |
| Number of Secret Types with Validity Check | $($Validity.Count) |
| Number of Secret Types with Base64 Support | $($Base64Supported.Count) |
| Non-Partner Patterns | [$($GHNonProviderCount)](https://docs.github.com/en/enterprise-cloud@latest/code-security/secret-scanning/secret-scanning-patterns#non-provider-patterns) (0 with validity checks) |
| Copilot Secret Scanning Patterns | [$($GHCopilotCount)](https://docs.github.com/en/enterprise-cloud@latest/code-security/secret-scanning/introduction/supported-secret-scanning-patterns#copilot-secret-scanning) |
| Inventory Commit History | [Docs](https://github.com/github/docs/blob/main/src/secret-scanning/data/pattern-docs/ghec/public-docs.yml)
| Secret Scanning Changelog | [Changelog](https://github.blog/changelog/?label=application-security) |

<details><summary>GHES Versions / Count</summary>
<p>

| GHES Version | Count |
| --- | --- |
$($GHESInventory | ForEach-Object { "| $($_.GHESVersion) | $($_.Count) |" } | Out-String)

</p>
</details>

# Azure DevOps
| Secret Scanning Inventory |$($(Get-Date -AsUTC).ToString('u')) |
| --- | --- |
| Number of Partner Secret Types | [$($ADOProviders.Count)](https://learn.microsoft.com/en-us/azure/devops/repos/security/github-advanced-security-secret-scan-patterns?view=azure-devops#partner-provider-patterns) |
| Number of Secret Types with Push Protection | $($ADOProvidersPush.Count + $ADONonProvidersPush.Count) |
| Number of Secret Types with Validity Check | $($ADOProvidersValidity.Count + $ADONonProvidersValidity.Count) |
| Non-Partner Patterns | [$($ADONonProviders.Count)](https://learn.microsoft.com/en-us/azure/devops/repos/security/github-advanced-security-secret-scan-patterns?view=azure-devops#non-provider-patterns) ( $($ADONonProvidersValidity.Count) with validity checks) |
| Copilot Secret Scanning Patterns | 0 |
| Inventory Commit History | [Docs](https://raw.githubusercontent.com/MicrosoftDocs/azure-devops-docs/refs/heads/main/docs/repos/security/includes/provider-table.md) [Docs NonPartner](https://raw.githubusercontent.com/MicrosoftDocs/azure-devops-docs/refs/heads/main/docs/repos/security/includes/non-provider-table.md)
| Secret Scanning Changes | [Commits](https://github.com/MicrosoftDocs/azure-devops-docs/commits/main/docs/repos/security/includes/provider-table.md) [Commits Non-Partner](https://github.com/MicrosoftDocs/azure-devops-docs/commits/main/docs/repos/security/includes/non-provider-table.md)|
"@

Write-Host $comment


## Use the GH CLI api to post a new comment to the gist: https://gist.github.com/felickz/9688dd0f5182cab22386efecfa41eb74
if (-not $SkipPost) {
    if ($script:hasErrors) {
        Write-Error "Skipping gist upload due to errors encountered during data collection."
        exit 1
    }
    gh api /gists/9688dd0f5182cab22386efecfa41eb74/comments -f "body=$comment"
}
