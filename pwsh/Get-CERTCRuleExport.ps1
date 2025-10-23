# Define the URL
$url = "https://wiki.sei.cmu.edu/confluence/display/c/2+Rules"

# Create a hashtable with rule categories and their abbreviations
$ruleCategories = @{
    "Rule 01. Preprocessor (PRE)" = "PRE"
    "Rule 02. Declarations and Initialization (DCL)" = "DCL"
    "Rule 03. Expressions (EXP)" = "EXP"
    "Rule 04. Integers (INT)" = "INT"
    "Rule 05. Floating Point (FLP)" = "FLP"
    "Rule 06. Arrays (ARR)" = "ARR"
    "Rule 07. Characters and Strings (STR)" = "STR"
    "Rule 08. Memory Management (MEM)" = "MEM"
    "Rule 09. Input Output (FIO)" = "FIO"
    "Rule 10. Environment (ENV)" = "ENV"
    "Rule 11. Signals (SIG)" = "SIG"
    "Rule 12. Error Handling (ERR)" = "ERR"
    "Rule 13. Application Programming Interfaces (API)" = "API"
    "Rule 14. Concurrency (CON)" = "CON"
    "Rule 48. Miscellaneous (MSC)" = "MSC"
    "Rule 50. POSIX (POS)" = "POS"
    "Rule 51. Microsoft Windows (WIN)" = "WIN"
}

# Define direct category URLs for better reliability
$categoryUrls = @{
    "PRE" = "https://wiki.sei.cmu.edu/confluence/display/c/1.+Preprocessor+%28PRE%29"
    "DCL" = "https://wiki.sei.cmu.edu/confluence/display/c/2.+Declarations+and+Initialization+%28DCL%29"
    "EXP" = "https://wiki.sei.cmu.edu/confluence/display/c/3.+Expressions+%28EXP%29"
    "INT" = "https://wiki.sei.cmu.edu/confluence/display/c/4.+Integers+%28INT%29"
    "FLP" = "https://wiki.sei.cmu.edu/confluence/display/c/5.+Floating+Point+%28FLP%29"
    "ARR" = "https://wiki.sei.cmu.edu/confluence/display/c/6.+Arrays+%28ARR%29"
    "STR" = "https://wiki.sei.cmu.edu/confluence/display/c/7.+Characters+and+Strings+%28STR%29"
    "MEM" = "https://wiki.sei.cmu.edu/confluence/display/c/8.+Memory+Management+%28MEM%29"
    "FIO" = "https://wiki.sei.cmu.edu/confluence/display/c/9.+Input%2Foutput+%28FIO%29"
    "ENV" = "https://wiki.sei.cmu.edu/confluence/display/c/10.+Environment+%28ENV%29"
    "SIG" = "https://wiki.sei.cmu.edu/confluence/display/c/11.+Signals+%28SIG%29"
    "ERR" = "https://wiki.sei.cmu.edu/confluence/display/c/12.+Error+Handling+%28ERR%29"
    "API" = "https://wiki.sei.cmu.edu/confluence/display/c/13.+Application+Programming+Interfaces+%28API%29"
    "CON" = "https://wiki.sei.cmu.edu/confluence/display/c/14.+Concurrency+%28CON%29"
    "MSC" = "https://wiki.sei.cmu.edu/confluence/display/c/48.+Miscellaneous+%28MSC%29"
    "POS" = "https://wiki.sei.cmu.edu/confluence/display/c/50.+POSIX+%28POS%29"
    "WIN" = "https://wiki.sei.cmu.edu/confluence/display/c/51.+Microsoft+Windows+%28WIN%29"
}

# Create an array to store all rules
$allRules = @()

# Function to extract the risk assessment summary from a rule page
function Get-RiskAssessmentSummary {
    param (
        [string]$RulePageContent
    )

    $riskAssessment = @{}

    # Use regex to find the Risk Assessment table
    if ($RulePageContent -match '(?s)Risk Assessment.*?<table.*?>(.*?)</table>') {
        $tableContent = $matches[1]

        # Extract severity
        if ($tableContent -match '(?s)Severity.*?<td.*?>(.*?)</td>') {
            $riskAssessment.Severity = $matches[1] -replace '<.*?>', '' -replace '&nbsp;', ' ' -replace '^\s+|\s+$', ''
        }

        # Extract likelihood
        if ($tableContent -match '(?s)Likelihood.*?<td.*?>(.*?)</td>') {
            $riskAssessment.Likelihood = $matches[1] -replace '<.*?>', '' -replace '&nbsp;', ' ' -replace '^\s+|\s+$', ''
        }

        # Extract remediation cost
        if ($tableContent -match '(?s)Remediation Cost.*?<td.*?>(.*?)</td>') {
            $riskAssessment.RemediationCost = $matches[1] -replace '<.*?>', '' -replace '&nbsp;', ' ' -replace '^\s+|\s+$', ''
        }

        # Extract priority
        if ($tableContent -match '(?s)Priority.*?<td.*?>(.*?)</td>') {
            $riskAssessment.Priority = $matches[1] -replace '<.*?>', '' -replace '&nbsp;', ' ' -replace '^\s+|\s+$', ''
        }

        # Extract level
        if ($tableContent -match '(?s)Level.*?<td.*?>(.*?)</td>') {
            $riskAssessment.Level = $matches[1] -replace '<.*?>', '' -replace '&nbsp;', ' ' -replace '^\s+|\s+$', ''
        }
    }

    return $riskAssessment
}

# Function to attempt web requests with retries
function Invoke-WebRequestWithRetry {
    param (
        [string]$Uri,
        [int]$MaxRetries = 3,
        [int]$RetryDelaySeconds = 2
    )

    $retryCount = 0
    $success = $false
    $result = $null

    while (-not $success -and $retryCount -lt $MaxRetries) {
        try {
            $result = Invoke-WebRequest -Uri $Uri -UseBasicParsing -TimeoutSec 30
            $success = $true
        }
        catch {
            $retryCount++
            if ($retryCount -lt $MaxRetries) {
                Write-Warning "Failed to download $Uri, retrying in $RetryDelaySeconds seconds... (Attempt $retryCount of $MaxRetries)"
                Start-Sleep -Seconds $RetryDelaySeconds
                # Increase delay for next retry
                $RetryDelaySeconds *= 2
            }
            else {
                Write-Error "Failed to download $Uri after $MaxRetries attempts: $_"
                throw
            }
        }
    }

    return $result
}

# Function to clean up URLs
function Get-CleanUrl {
    param (
        [string]$RawUrl
    )

    # Replace encoded characters
    $cleanUrl = [System.Web.HttpUtility]::UrlDecode($RawUrl)

    # Ensure URL starts with https://wiki.sei.cmu.edu
    if (-not $cleanUrl.StartsWith("https://")) {
        if ($cleanUrl.StartsWith("/")) {
            $cleanUrl = "https://wiki.sei.cmu.edu" + $cleanUrl
        }
        else {
            $cleanUrl = "https://wiki.sei.cmu.edu/" + $cleanUrl
        }
    }

    return $cleanUrl
}

# Add required assembly for HttpUtility
Add-Type -AssemblyName System.Web

try {
    # Loop through each rule category
    foreach ($category in $ruleCategories.Keys) {
        $categoryAbbr = $ruleCategories[$category]
        Write-Host "Processing $category ($categoryAbbr)..."

        # Use predefined category URL
        $categoryUrl = $categoryUrls[$categoryAbbr]

        if ($categoryUrl) {
            try {
                Write-Host "  Downloading category page: $categoryUrl"
                $categoryPageContent = Invoke-WebRequestWithRetry -Uri $categoryUrl

                # Find all rule links on the category page
                # Look for links with the pattern [CATEGORY]##-C in the URL or text
                $rulePattern = "href=[\""]([^\""]*(($categoryAbbr)\d+\-C)[^\""]*)[\""']"
                $ruleMatches = [regex]::Matches($categoryPageContent.Content, $rulePattern)

                # Create a hashtable to track processed rules
                $processedRules = @{}

                foreach ($match in $ruleMatches) {
                    $ruleUrlRaw = $match.Groups[1].Value
                    $ruleId = $match.Groups[2].Value

                    # Skip if we've already processed this rule
                    if ($processedRules.ContainsKey($ruleId)) {
                        continue
                    }

                    # Mark as processed
                    $processedRules[$ruleId] = $true

                    # Clean up the URL
                    $ruleUrl = Get-CleanUrl -RawUrl $ruleUrlRaw

                    try {
                        Write-Host "    Processing rule: $ruleId - $ruleUrl"
                        $rulePageContent = Invoke-WebRequestWithRetry -Uri $ruleUrl

                        # Extract rule name
                        $ruleName = ""
                        if ($rulePageContent.Content -match "<title>([^<]*)</title>") {
                            $ruleName = $matches[1] -replace " - SEI CERT C Coding Standard - Confluence", ""
                        }

                        # Get risk assessment summary
                        $riskAssessment = Get-RiskAssessmentSummary -RulePageContent $rulePageContent.Content

                        # Create rule object
                        $rule = @{
                            Id = $ruleId
                            Name = $ruleName
                            Category = $category
                            CategoryAbbreviation = $categoryAbbr
                            URL = $ruleUrl
                            RiskAssessment = $riskAssessment
                        }

                        # Add to collection
                        $allRules += $rule

                        # Add a small delay to avoid hammering the server
                        Start-Sleep -Milliseconds 500
                    }
                    catch {
                        Write-Warning "Failed to process rule $ruleId. Error: $_"
                    }
                }

                # Check if we found any rules
                if ($processedRules.Count -eq 0) {
                    Write-Warning "No rules found for category $category. Check the regex pattern or the URL."
                }
                else {
                    Write-Host "  Found $($processedRules.Count) rules for category $category"
                }
            }
            catch {
                Write-Warning "Failed to download category page $categoryUrl. Error: $_"
            }
        }
        else {
            Write-Warning "No URL defined for category $category ($categoryAbbr)"
        }
    }

    # Convert to JSON and save to file
    $outputPath = Join-Path -Path $PSScriptRoot -ChildPath "..\certc_rules.json"
    $allRules | ConvertTo-Json -Depth 4 | Out-File -FilePath $outputPath -Encoding UTF8

    Write-Host "Successfully exported $($allRules.Count) rules to $outputPath"
}
catch {
    Write-Error "Failed to complete the export process: $_"
}
