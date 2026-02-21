<#
.SYNOPSIS
    Manages GitHub org custom properties derived from Microsoft Application Inspector tags.

.DESCRIPTION
    This script bridges Microsoft Application Inspector (https://github.com/microsoft/ApplicationInspector)
    with GitHub organization custom properties. It exports the full set of AppInspector tags, groups them
    into logical categories, and publishes them as multi_select custom properties on a GitHub org.

    Tags are grouped by their first dot-segment (e.g., Cryptography.Cipher.AES → AppInspector-Cryptography)
    with a merge table that consolidates related segments (Framework.Testing.* → AppInspector-Testing,
    Platform.* → AppInspector-OS, etc.). This avoids the issues with AppInspector's upstream
    tagreportgroups.json which has overlapping regex patterns, gaps, and typos.

    Three modes of operation:
    - OrgApply:    Creates/updates org-level property schemas from the full AppInspector tag catalog
    - OrgCleanup:  Removes all AppInspector-* properties from the org
    - RepoAssign:  Analyzes a repo's source code and assigns detected tags as property values

.PARAMETER Mode
    Operation mode: OrgApply (default), OrgCleanup, or RepoAssign.

.PARAMETER RepoNWO
    (RepoAssign mode) Target repository in name-with-owner format (e.g., "octofelickz/juice-shop").

.PARAMETER AnalyzeOutput
    (RepoAssign mode) Path to an AppInspector analyze JSON output file.
    Generate with: appinspector analyze -s <source> -f json -o results.json --no-show-progress -g "**/node_modules/**"
    See: https://github.com/microsoft/ApplicationInspector/wiki/1.-CLI-Usage

.EXAMPLE
    # Create/update all AppInspector custom properties on the org
    .\Publish-AppInspectorCustomProperties.ps1 -Mode OrgApply

.EXAMPLE
    # Remove all AppInspector-* custom properties from the org
    .\Publish-AppInspectorCustomProperties.ps1 -Mode OrgCleanup

.EXAMPLE
    # Analyze a repo's source and assign detected tags as property values
    # Step 1: Run appinspector analyze (with exclusions for large dirs like node_modules)
    #   appinspector analyze -s "C:\repos\octofelickz\juice-shop-felickz" -f json -o .\juice-shop-results.json --no-show-progress -g "**/node_modules/**"
    # Step 2: Assign the results to the repo
    .\Publish-AppInspectorCustomProperties.ps1 -Mode RepoAssign -RepoNWO "octofelickz/juice-shop" -AnalyzeOutput ".\juice-shop-results.json"

.NOTES
    Prerequisites:
    - gh CLI authenticated with admin:org scope (gh auth refresh -h github.com -s admin:org)
    - dotnet tool: Microsoft.CST.ApplicationInspector.CLI (dotnet tool install -g Microsoft.CST.ApplicationInspector.CLI)

    Known issues:
    - AppInspector exporttags --output-file-format json is broken (only outputs appVersion)
      Bug: https://github.com/microsoft/ApplicationInspector/issues/641
      Workaround: Uses text format export and parses tags manually.

    Upstream reference:
    - Tag report groups: https://github.com/microsoft/ApplicationInspector/blob/main/AppInspector.CLI/preferences/tagreportgroups.json
    - CLI usage wiki: https://github.com/microsoft/ApplicationInspector/wiki/1.-CLI-Usage
#>
param(
    [ValidateSet('OrgApply', 'OrgCleanup', 'RepoAssign')]
    [string]$Mode = 'OrgApply',

    # ----- RepoAssign mode parameters -----
    # Target repo in name-with-owner format (e.g., "octofelickz/juice-shop")
    [string]$RepoNWO,

    # Path to an AppInspector analyze JSON output file.
    # Generate with: appinspector analyze -s <source> -f json -o results.json --no-show-progress -g "**/node_modules/**"
    # See: https://github.com/microsoft/ApplicationInspector/wiki/1.-CLI-Usage
    [string]$AnalyzeOutput
)

$org = 'octofelickz'
$prefix = 'AppInspector'
# Surrogate pair encoding for supplementary Unicode emoji (outside BMP)
$descriptionPrefix = "`u{1FA9F}Microsoft`u{1F5A5}Application`u{1F575}Inspector"

# ============================================================
# Functions
# ============================================================

function Get-OrgProperties {
    param (
        [Parameter(Mandatory)]
        [String]$Organization
    )
    $props = gh api /orgs/$Organization/properties/schema | ConvertFrom-Json
    return $props
}

function Set-OrgProperties {
    param (
        [Parameter(Mandatory)]
        [String]$Organization,

        [Parameter(Mandatory)]
        [PSCustomObject[]]$Properties
    )

    # GitHub API: PATCH /orgs/{org}/properties/schema
    # https://docs.github.com/en/rest/orgs/custom-properties#create-or-update-custom-properties-for-an-organization
    $propertiesPayload = @()
    foreach ($prop in $Properties) {
        $propObj = @{
            property_name      = $prop.PropertyName
            value_type         = $prop.ValueType
            description        = $prop.Description
            allowed_values     = $prop.AllowedValues
            values_editable_by = 'org_and_repo_actors'
        }
        $propertiesPayload += $propObj
    }

    $payload = @{ properties = $propertiesPayload } | ConvertTo-Json -Depth 10

    Write-Host "`nPATCHing $($Properties.Count) custom properties to org '$Organization'..." -ForegroundColor Cyan
    $payload | gh api "/orgs/$Organization/properties/schema" `
        --method PATCH `
        --header "X-GitHub-Api-Version: 2022-11-28" `
        --input -

    if ($LASTEXITCODE -eq 0) {
        Write-Host "Successfully updated custom properties for $Organization" -ForegroundColor Green
    } else {
        Write-Error "Failed to update custom properties for $Organization"
    }
}

function Remove-OrgAppInspectorProperties {
    param (
        [Parameter(Mandatory)]
        [String]$Organization,

        [String]$Prefix = 'AppInspector'
    )

    Write-Host "`n=== Cleanup Mode: Removing $Prefix-* properties ===" -ForegroundColor Yellow
    $currentProps = Get-OrgProperties -Organization $Organization
    $toRemove = $currentProps | Where-Object { $_.property_name -like "$Prefix-*" }

    if (-not $toRemove) {
        Write-Host "  No $Prefix-* properties found to remove." -ForegroundColor DarkGray
        return
    }

    Write-Host "  Found $($toRemove.Count) properties to remove:" -ForegroundColor Yellow
    foreach ($prop in $toRemove) {
        Write-Host "    Removing: $($prop.property_name)" -ForegroundColor Red
        # GitHub API: DELETE /orgs/{org}/properties/schema/{custom_property_name}
        # Retry up to 3 times for transient network errors (TLS timeouts, etc.)
        $retries = 3
        $deleted = $false
        for ($i = 1; $i -le $retries; $i++) {
            gh api "/orgs/$Organization/properties/schema/$($prop.property_name)" `
                --method DELETE `
                --header "X-GitHub-Api-Version: 2022-11-28" `
                --silent

            if ($LASTEXITCODE -eq 0) {
                Write-Host "      Deleted." -ForegroundColor Green
                $deleted = $true
                break
            }
            if ($i -lt $retries) {
                Write-Host "      Retry $i/$retries..." -ForegroundColor DarkYellow
                Start-Sleep -Seconds 2
            }
        }
        if (-not $deleted) {
            Write-Error "      Failed to delete $($prop.property_name) after $retries attempts"
        }
    }

    Write-Host "`n  Cleanup complete." -ForegroundColor Green
}

# Shared merge table: maps tag prefixes → consolidated property name
# More specific prefixes (two-segment) are checked first, then first-segment fallbacks.
# Segments not listed here become their own property (e.g., AI → AI)
# This is used by both Apply and Assign modes.
$mergeTable = [ordered]@{
    # Two-segment overrides (checked first)
    'Framework.Testing'     = 'Testing'       # Framework.Testing.* → separate group (125 tags)
    'Framework.Development' = 'Development'   # Framework.Development.* (85 tags)
    'Framework.CMS'         = 'Development'   # Framework.CMS.* (4 tags)
    # First-segment fallbacks
    'Development'           = 'Development'   # Development.Build.* (11 tags)
    'Hardware'              = 'Miscellaneous'  # Hardware.Accessory.*, Hardware.ReferenceDesign
    'Component'             = 'Miscellaneous'  # Component.Executable.*
    'Dependency'            = 'Miscellaneous'  # Dependency.SourceInclude
    'Metric'                = 'Miscellaneous'  # Metric.Code.*
    'Platform'              = 'OS'             # Platform.OS.*, Platform.Device.*, Platform.Microsoft.*
}

function Get-TagPropertyName {
    <#
    .SYNOPSIS
        Maps an AppInspector tag to its consolidated property name.
    .DESCRIPTION
        Uses the merge table to resolve a tag (e.g., "Framework.Testing.Jest")
        to its property name (e.g., "AppInspector-Testing").
    #>
    param (
        [Parameter(Mandatory)]
        [string]$Tag,

        [string]$Prefix = 'AppInspector'
    )

    $segments = $Tag.Split('.')
    $firstSegment = $segments[0]
    $twoSegment = if ($segments.Count -ge 2) { "$($segments[0]).$($segments[1])" } else { $firstSegment }

    $groupName = if ($mergeTable.Contains($twoSegment)) {
        $mergeTable[$twoSegment]
    } elseif ($mergeTable.Contains($firstSegment)) {
        $mergeTable[$firstSegment]
    } else {
        $firstSegment
    }

    return "$Prefix-$groupName"
}

function Set-RepoProperties {
    <#
    .SYNOPSIS
        Sets custom property values on a specific repository.
    .DESCRIPTION
        Calls PATCH /repos/{owner}/{repo}/properties/values to assign
        the detected AppInspector tags as multi_select property values.
    #>
    param (
        [Parameter(Mandatory)]
        [string]$RepoNWO,  # name-with-owner format (e.g., "octofelickz/my-app")

        [Parameter(Mandatory)]
        [hashtable]$PropertyValues  # @{ "AppInspector-Cryptography" = @("Cryptography.Cipher.AES", ...) }
    )

    # GitHub API: PATCH /repos/{owner}/{repo}/properties/values
    # https://docs.github.com/en/rest/repos/custom-properties#create-or-update-custom-property-values-for-a-repository
    $propertiesPayload = @()
    foreach ($entry in $PropertyValues.GetEnumerator()) {
        $propertiesPayload += @{
            property_name = $entry.Key
            value         = @($entry.Value)
        }
    }

    $payload = @{ properties = $propertiesPayload } | ConvertTo-Json -Depth 10

    Write-Host "`nPATCHing $($PropertyValues.Count) property values on repo '$RepoNWO'..." -ForegroundColor Cyan
    $payload | gh api "/repos/$RepoNWO/properties/values" `
        --method PATCH `
        --header "X-GitHub-Api-Version: 2022-11-28" `
        --input -

    if ($LASTEXITCODE -eq 0) {
        Write-Host "Successfully assigned properties to $RepoNWO" -ForegroundColor Green
    } else {
        Write-Error "Failed to assign properties to $RepoNWO"
    }
}

# ============================================================
# OrgCleanup Mode
# ============================================================
if ($Mode -eq 'OrgCleanup') {
    Remove-OrgAppInspectorProperties -Organization $org -Prefix $prefix

    Write-Host "`n=== Remaining Org Properties ===" -ForegroundColor Magenta
    $remaining = Get-OrgProperties -Organization $org
    if ($remaining) {
        $remaining | ForEach-Object { Write-Host "  $($_.property_name) ($($_.value_type))" }
    } else {
        Write-Host "  (none)" -ForegroundColor DarkGray
    }
    return
}

# ============================================================
# RepoAssign Mode
# ============================================================
# Analyzes a repo's source code (or uses existing output), maps detected tags
# to consolidated property names, and assigns them as repo custom property values.
#
# Usage:
#   appinspector analyze -s "C:\repos\octofelickz\juice-shop-felickz" -f json -o .\juice-shop-results.json --no-show-progress -g "**/node_modules/**"
#   .\Publish-AppInspectorCustomProperties.ps1 -Mode RepoAssign -RepoNWO "octofelickz/juice-shop" -AnalyzeOutput ".\juice-shop-results.json"
#
# See: https://github.com/microsoft/ApplicationInspector/wiki/1.-CLI-Usage
if ($Mode -eq 'RepoAssign') {
    if (-not $RepoNWO) {
        Write-Error "RepoAssign mode requires -RepoNWO parameter (e.g., -RepoNWO 'octofelickz/juice-shop')"
        return
    }

    if (-not $AnalyzeOutput) {
        Write-Error "RepoAssign mode requires -AnalyzeOutput parameter. Generate with: appinspector analyze -s <source> -f json -o results.json --no-show-progress -g '**/node_modules/**'"
        return
    }

    if (-not (Test-Path $AnalyzeOutput)) {
        Write-Error "Analyze output file not found: $AnalyzeOutput"
        return
    }

    Write-Host "Using analyze output: $AnalyzeOutput" -ForegroundColor Cyan

    # Parse the analyze JSON and extract unique tags
    Write-Host "Parsing analyze results..." -ForegroundColor Cyan
    $analyzeResults = Get-Content -Path $AnalyzeOutput -Raw | ConvertFrom-Json
    $detectedTags = @()

    # AppInspector analyze JSON structure:
    #   metaData.uniqueTags: string[] of unique tag names (e.g., ["Cryptography.Cipher.AES", ...])
    #   metaData.detailedMatchList[].tags[]: per-match tag arrays (fallback)
    if ($analyzeResults.metaData -and $analyzeResults.metaData.uniqueTags) {
        $detectedTags = @($analyzeResults.metaData.uniqueTags)
    } elseif ($analyzeResults.metaData -and $analyzeResults.metaData.detailedMatchList) {
        # Fallback: extract tags from individual matches
        $detectedTags = $analyzeResults.metaData.detailedMatchList | ForEach-Object { $_.tags } | Sort-Object -Unique
        $detectedTags = $analyzeResults.matchList | ForEach-Object { $_.tags } | Sort-Object -Unique
    } else {
        Write-Error "Could not find tags in analyze output. Ensure the file is a valid AppInspector analyze JSON result."
        return
    }

    $detectedTags = @($detectedTags | Sort-Object -Unique)
    Write-Host "Found $($detectedTags.Count) unique tags in repo" -ForegroundColor Cyan

    # Map tags to property names
    $propertyValues = @{}
    foreach ($tag in $detectedTags) {
        $propName = Get-TagPropertyName -Tag $tag -Prefix $prefix
        if (-not $propertyValues.ContainsKey($propName)) {
            $propertyValues[$propName] = [System.Collections.Generic.List[string]]::new()
        }
        $propertyValues[$propName].Add($tag)
    }

    # Display the mapping
    Write-Host "`n=== Tag → Property Mapping ===" -ForegroundColor Green
    foreach ($entry in ($propertyValues.GetEnumerator() | Sort-Object Key)) {
        Write-Host "  $($entry.Key) ($($entry.Value.Count) tags):" -ForegroundColor White
        foreach ($tag in $entry.Value) {
            Write-Host "    $tag" -ForegroundColor DarkGray
        }
    }

    # Assign to the repo
    Write-Host "`n=== Assigning to $RepoNWO ===" -ForegroundColor Magenta
    Set-RepoProperties -RepoNWO $RepoNWO -PropertyValues $propertyValues

    return
}

# ============================================================
# OrgApply Mode
# ============================================================

# 1. Export tags from Application Inspector
# JSON export is broken (only outputs appVersion, no tags)
# Bug: https://github.com/microsoft/ApplicationInspector/issues/641
appinspector exporttags --output-file-format text --output-file-path .\tags.txt
$tags = Get-Content -Path '.\tags.txt' | Where-Object { $_ -ne 'Results' -and $_.Trim() -ne '' }
Write-Host "Exported $($tags.Count) tags from Application Inspector" -ForegroundColor Cyan

# 2. Download tagreportgroups.json from upstream for description enrichment
# Source: https://github.com/microsoft/ApplicationInspector/blob/main/AppInspector.CLI/preferences/tagreportgroups.json
Write-Host "Downloading tagreportgroups.json from microsoft/ApplicationInspector..." -ForegroundColor Cyan
$groupsJsonRaw = gh api /repos/microsoft/ApplicationInspector/contents/AppInspector.CLI/preferences/tagreportgroups.json `
    --header "Accept: application/vnd.github.raw+json"
$groupsJson = $groupsJsonRaw | ConvertFrom-Json
$reportGroups = $groupsJson[0].groups
Write-Host "Found $($reportGroups.Count) upstream report groups (for reference)" -ForegroundColor Cyan

# 3. Group tags using the shared merge table
#
# The upstream tagreportgroups.json is designed for HTML report visualization
# with overlapping regex patterns, gaps, and typos (e.g., "Miscellenous").
# For custom properties, we group by first segment and merge related ones
# using the shared $mergeTable defined above.
#
# Why not use upstream regex directly:
#   - "Select Features" mixes Auth + Crypto + AI + Deserialization (too broad)
#   - "General Features" mixes OS ops + parsing + logging (too broad)
#   - OS Integration vs OS System Changes is artificial (values are self-describing)
#   - WebApp split into 4 groups (Cookies/Headers/Features/auto) is too granular
#   - ~50+ tags fall through with no match at all
#   - "Miscellenous" typo creates duplicate with auto-generated "Miscellaneous"

# Human-readable descriptions for each consolidated group
$groupDescriptions = @{
    'AI'              = 'AI & Machine Learning'
    'Application'     = 'Application types & containers'
    'Authentication'  = 'Authentication mechanisms'
    'Authorization'   = 'Authorization & access control'
    'CloudServices'   = 'Cloud services & hosting'
    'Cryptography'    = 'Cryptography & encryption'
    'Data'            = 'Data storage, parsing & sensitive data'
    'Development'     = 'Development frameworks & build tools'
    'Device'          = 'Device permissions'
    'Infrastructure'  = 'Infrastructure as Code'
    'Metadata'        = 'Application metadata'
    'Miscellaneous'   = 'Miscellaneous (components, metrics, hardware)'
    'OS'              = 'OS integration, system changes & platform'
    'Pipeline'        = 'Pipeline & static analysis tools'
    'Testing'         = 'Testing frameworks'
    'WebApp'          = 'Web application (cookies, headers, storage)'
}

# Build consolidated groups using the shared Get-TagPropertyName function
$consolidatedGroups = [ordered]@{}

foreach ($tag in $tags) {
    $propName = Get-TagPropertyName -Tag $tag -Prefix $prefix
    # Strip prefix to get the group name for the ordered dict
    $groupName = $propName -replace "^$prefix-", ''
    if (-not $consolidatedGroups.Contains($groupName)) {
        $consolidatedGroups[$groupName] = [System.Collections.Generic.List[string]]::new()
    }
    $consolidatedGroups[$groupName].Add($tag)
}

# 4. Build property definitions
Write-Host "`n=== Custom Property Definitions ===" -ForegroundColor Green
$propertyDefinitions = @()

foreach ($entry in $consolidatedGroups.GetEnumerator()) {
    $groupName = $entry.Key
    $groupTags = $entry.Value
    $propertyName = "$prefix-$groupName"
    $desc = if ($groupDescriptions.ContainsKey($groupName)) { $groupDescriptions[$groupName] } else { $groupName }
    $description = "$descriptionPrefix - $desc"
    $allowedValues = $groupTags | Sort-Object -Unique

    # GitHub custom properties have a max of 200 allowed values
    if ($allowedValues.Count -gt 200) {
        Write-Warning "Property '$propertyName' has $($allowedValues.Count) values - truncating to 200"
        $allowedValues = $allowedValues | Select-Object -First 200
    }

    # Truncate description to 255 chars (GitHub limit)
    if ($description.Length -gt 255) {
        $description = $description.Substring(0, 252) + '...'
    }

    $propDef = [PSCustomObject]@{
        PropertyName  = $propertyName
        Description   = $description
        ValueType     = 'multi_select'
        AllowedValues = @($allowedValues)
        Count         = $allowedValues.Count
    }
    $propertyDefinitions += $propDef

    Write-Host "  $propertyName ($($allowedValues.Count) values) - $desc" -ForegroundColor White
}

Write-Host "`nTotal properties to create: $($propertyDefinitions.Count)" -ForegroundColor Green

# 5. Show current state and apply
Write-Host "`n=== Current Org Properties ===" -ForegroundColor Magenta
$currentProps = Get-OrgProperties -Organization $org
if ($currentProps) {
    $currentProps | ForEach-Object { Write-Host "  $($_.property_name) ($($_.value_type))" }
} else {
    Write-Host "  (none)" -ForegroundColor DarkGray
}

Write-Host "`n=== Applying Properties ===" -ForegroundColor Magenta
Set-OrgProperties -Organization $org -Properties $propertyDefinitions

Write-Host "`n=== Updated Org Properties ===" -ForegroundColor Magenta
$updatedProps = Get-OrgProperties -Organization $org
if ($updatedProps) {
    $updatedProps | ForEach-Object {
        $valCount = if ($_.allowed_values) { $_.allowed_values.Count } else { 0 }
        Write-Host "  $($_.property_name) ($($_.value_type), $valCount values)"
    }
}

