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
    - OrgList:     Lists all AppInspector-* property schemas defined on the org
    - RepoAssign:  Analyzes a repo's source code and assigns detected tags as property values
    - RepoList:    Lists the AppInspector property values currently assigned to a repo

.PARAMETER Mode
    Operation mode: OrgApply (default), OrgCleanup, OrgList, RepoAssign, or RepoList.

.PARAMETER Org
    GitHub organization name (e.g., "octofelickz").
    Required for OrgApply/OrgCleanup. For RepoAssign, inferred from -RepoNWO or -Org/-Repo.

.PARAMETER Repo
    (RepoAssign mode) Repository name (e.g., "juice-shop"). Used with -Org to form owner/repo.
    Alternative to -RepoNWO. If both -RepoNWO and -Org/-Repo are provided, -RepoNWO takes precedence.

.PARAMETER RepoNWO
    (RepoAssign mode) Target repository in name-with-owner format (e.g., "octofelickz/juice-shop").
    Alternative to -Org/-Repo.

.PARAMETER AnalyzeOutput
    (RepoAssign mode) Path to an AppInspector analyze JSON output file.
    See recommended analyze command in the RepoAssign mode section of this script.
    Quick start: appinspector analyze --source-path <source> --output-file-format json --output-file-path results.json --no-show-progress --tags-only --no-file-metadata --context-lines -1 --disable-archive-crawling --exclusion-globs "**/node_modules/**,**/vendor/**,**/dist/**,**/build/**,**/*.min.js" --file-timeout 15000 --confidence-filters "High"
    See: https://github.com/microsoft/ApplicationInspector/wiki/1.-CLI-Usage

.EXAMPLE
    # Create/update all AppInspector custom properties on the org
    .\Publish-AppInspectorCustomProperties.ps1 -Mode OrgApply -Org "octofelickz"

.EXAMPLE
    # Remove all AppInspector-* custom properties from the org
    .\Publish-AppInspectorCustomProperties.ps1 -Mode OrgCleanup -Org "octofelickz"

.EXAMPLE
    # List all AppInspector-* property schemas on the org
    .\Publish-AppInspectorCustomProperties.ps1 -Mode OrgList -Org "octofelickz"

.EXAMPLE
    # Analyze a repo's source and assign detected tags as property values
    # Step 1: Run appinspector analyze (see RepoAssign section in script for full recommended flags)
    #   appinspector analyze --source-path "C:\repos\octofelickz\juice-shop-felickz" --output-file-format json --output-file-path .\juice-shop-results.json --no-show-progress --tags-only --no-file-metadata --context-lines -1 --disable-archive-crawling --exclusion-globs "**/node_modules/**,**/vendor/**,**/dist/**,**/build/**,**/*.min.js" --file-timeout 15000 --confidence-filters "High"
    # Step 2: Assign the results to the repo (using -RepoNWO)
    .\Publish-AppInspectorCustomProperties.ps1 -Mode RepoAssign -RepoNWO "octofelickz/juice-shop-felickz" -AnalyzeOutput ".\juice-shop-results.json"

.EXAMPLE
    # Same as above but using -Org and -Repo instead of -RepoNWO
    .\Publish-AppInspectorCustomProperties.ps1 -Mode RepoAssign -Org "octofelickz" -Repo "juice-shop-felickz" -AnalyzeOutput ".\juice-shop-results.json"

.EXAMPLE
    # List the AppInspector property values assigned to a repo
    .\Publish-AppInspectorCustomProperties.ps1 -Mode RepoList -RepoNWO "octofelickz/juice-shop-felickz"

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
    [ValidateSet('OrgApply', 'OrgCleanup', 'OrgList', 'RepoAssign', 'RepoList')]
    [string]$Mode = 'OrgApply',

    # ----- Org-level parameters -----
    # GitHub organization name (e.g., "octofelickz")
    [string]$Org,

    # ----- RepoAssign mode parameters -----
    # Repository name (e.g., "juice-shop"). Used with -Org to form owner/repo.
    [string]$Repo,

    # Target repo in name-with-owner format (e.g., "octofelickz/juice-shop")
    # Alternative to -Org/-Repo
    [string]$RepoNWO,

    # Path to an AppInspector analyze JSON output file.
    # See recommended analyze command in the RepoAssign section of this script.
    # Quick start: appinspector analyze --source-path <source> --output-file-format json --output-file-path results.json --no-show-progress --tags-only --no-file-metadata --context-lines -1 --disable-archive-crawling --file-timeout 15000 --confidence-filters "High" --exclusion-globs "**/node_modules/**,**/vendor/**,**/dist/**,**/build/**,**/*.min.js"
    # See: https://github.com/microsoft/ApplicationInspector/wiki/1.-CLI-Usage
    [string]$AnalyzeOutput
)

# Resolve RepoNWO: from -RepoNWO directly, or combine -Org/-Repo
if (-not $RepoNWO -and $Org -and $Repo) {
    $RepoNWO = "$Org/$Repo"
}

# Resolve Org: from -Org param, or infer from -RepoNWO
if (-not $Org -and $RepoNWO) {
    $Org = $RepoNWO.Split('/')[0]
}
if (-not $Org) {
    Write-Error "Organization is required. Provide -Org, -RepoNWO, or -Org/-Repo."
    return
}

$prefix = 'AppInspector'
$descriptionPrefix = '🪟Microsoft🖥️Application🕵️Inspector'

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
    Remove-OrgAppInspectorProperties -Organization $Org -Prefix $prefix

    Write-Host "`n=== Remaining Org Properties ===" -ForegroundColor Magenta
    $remaining = Get-OrgProperties -Organization $Org
    if ($remaining) {
        $remaining | ForEach-Object { Write-Host "  $($_.property_name) ($($_.value_type))" }
    } else {
        Write-Host "  (none)" -ForegroundColor DarkGray
    }
    return
}

# ============================================================
# OrgList Mode
# ============================================================
if ($Mode -eq 'OrgList') {
    Write-Host "`n=== AppInspector Org Properties for '$Org' ===" -ForegroundColor Green
    $allProps = Get-OrgProperties -Organization $Org
    $aiProps = $allProps | Where-Object { $_.property_name -like "$prefix-*" }

    if (-not $aiProps) {
        Write-Host "  No $prefix-* properties found." -ForegroundColor DarkGray
        return
    }

    Write-Host "  Found $($aiProps.Count) properties:`n" -ForegroundColor Cyan
    foreach ($prop in $aiProps) {
        $valCount = if ($prop.allowed_values) { $prop.allowed_values.Count } else { 0 }
        Write-Host "  $($prop.property_name) ($($prop.value_type), $valCount values)" -ForegroundColor White
        if ($prop.description) {
            Write-Host "    Description: $($prop.description)" -ForegroundColor DarkGray
        }
        if ($prop.allowed_values -and $prop.allowed_values.Count -gt 0) {
            foreach ($val in $prop.allowed_values) {
                Write-Host "      $val" -ForegroundColor DarkGray
            }
        }
    }
    return
}

# ============================================================
# RepoList Mode
# ============================================================
if ($Mode -eq 'RepoList') {
    if (-not $RepoNWO) {
        Write-Error "RepoList mode requires -RepoNWO or -Org/-Repo parameter."
        return
    }

    Write-Host "`n=== AppInspector Properties for '$RepoNWO' ===" -ForegroundColor Green
    $repoProps = gh api "/repos/$RepoNWO/properties/values" | ConvertFrom-Json
    $aiRepoProps = $repoProps | Where-Object { $_.property_name -like "$prefix-*" }

    if (-not $aiRepoProps) {
        Write-Host "  No $prefix-* values assigned." -ForegroundColor DarkGray
        return
    }

    $totalValues = 0
    foreach ($prop in $aiRepoProps) {
        $values = @($prop.value)
        if ($values.Count -eq 0 -or ($values.Count -eq 1 -and [string]::IsNullOrEmpty($values[0]))) {
            continue
        }
        $totalValues += $values.Count
        Write-Host "  $($prop.property_name) ($($values.Count) values):" -ForegroundColor White
        foreach ($val in $values) {
            Write-Host "    $val" -ForegroundColor DarkGray
        }
    }

    Write-Host "`n  Total: $totalValues tag values assigned" -ForegroundColor Cyan
    return
}

# ============================================================
# RepoAssign Mode
# ============================================================
# Maps detected tags from an AppInspector analyze JSON output to consolidated
# property names and assigns them as repo custom property values.
#
# ---- Recommended appinspector analyze command for org-wide scanning ----
#
# Optimized for accuracy + speed at scale (100k+ repos):
#
#   appinspector analyze `
#     --source-path "<source-path>" `
#     --output-file-format json `
#     --output-file-path "<output>.json" `
#     --no-show-progress `
#     --tags-only `
#     --no-file-metadata `
#     --context-lines -1 `
#     --disable-archive-crawling `
#     --exclusion-globs "**/node_modules/**,**/vendor/**,**/bower_components/**,**/.bundle/**,**/packages/**,**/*.min.js,**/*.min.css,**/dist/**,**/build/**,**/out/**,**/target/**,**/bin/**,**/obj/**,**/.vs/**,**/.git/**" `
#     --file-timeout 15000 `
#     --confidence-filters "High" `
#     --console-verbosity Verbose
#
# Flag breakdown:
#   --output-file-format json    JSON output for programmatic consumption
#   --no-show-progress           Suppress progress bar (CI/automation friendly)
#   --tags-only                  Skip detailed match data — we only need tag names, not file/line/excerpt info.
#                                  Massive speedup: skips excerpt extraction and per-match metadata.
#   --no-file-metadata           Skip per-file metadata collection. We don't need file-level stats.
#   --context-lines -1           Don't extract code samples or excerpts. Combined with --tags-only for max speed.
#   --disable-archive-crawling   Don't unpack .zip/.jar/.nupkg etc. Huge time saver on large repos.
#                                  Archive contents are typically 3rd-party dependencies anyway.
#   --exclusion-globs            Exclude resolved dependency dirs and generated/minified code:
#                                  **/node_modules/**     - npm/yarn resolved deps (can be 100k+ files)
#                                  **/vendor/**           - PHP Composer, Go vendor, Ruby bundler
#                                  **/bower_components/** - Bower (legacy)
#                                  **/.bundle/**          - Ruby Bundler
#                                  **/packages/**         - NuGet packages folder
#                                  **/*.min.js            - Minified JS (source already scanned)
#                                  **/*.min.css           - Minified CSS
#                                  **/dist/**             - Build output directories
#                                  **/build/**            - Build output directories
#                                  **/out/**              - Build output directories
#                                  **/target/**           - Maven/Gradle build output
#                                  **/bin/**              - .NET/compiled output (default)
#                                  **/obj/**              - .NET intermediate output (default)
#                                  **/.vs/**              - Visual Studio cache (default)
#                                  **/.git/**             - Git internal (default)
#   --file-timeout 15000        15s per-file timeout (default is 60s). Prevents hanging on huge generated files.
#                                  Most source files process in <1s. 15s is generous for legitimate code.
#   --confidence-filters "High"  High confidence only. Reduces noise from low/medium confidence matches.
#                                  For property tagging we want precision over recall.
#   --console-verbosity Verbose  Maximum detail in console output. Shows all processing info,
#                                  file-level progress, and rule matching details.
#
# Optional additional flags (not included by default):
#   --processing-timeout 300000         5min total processing timeout. Use for CI time-boxing.
#   --enumeration-timeout 60000         1min enumeration timeout. Prevents hanging on huge directory trees.
#   --non-backtracking-regex            Slightly faster but may miss some patterns.
#   --max-num-matches-per-tag 1         Max 1 match per tag. Faster but may miss nuanced tag detection.
#
# Example:
#   appinspector analyze --source-path "C:\repos\octofelickz\juice-shop-felickz" --output-file-format json --output-file-path .\juice-shop-results.json --no-show-progress --tags-only --no-file-metadata --context-lines -1 --disable-archive-crawling --exclusion-globs "**/node_modules/**,**/vendor/**,**/bower_components/**,**/.bundle/**,**/packages/**,**/*.min.js,**/*.min.css,**/dist/**,**/build/**,**/out/**,**/target/**,**/bin/**,**/obj/**,**/.vs/**,**/.git/**" --file-timeout 15000 --confidence-filters "High" --console-verbosity Verbose
#   .\Publish-AppInspectorCustomProperties.ps1 -Mode RepoAssign -RepoNWO "octofelickz/juice-shop-felickz" -AnalyzeOutput ".\juice-shop-results.json"
#
# See: https://github.com/microsoft/ApplicationInspector/wiki/1.-CLI-Usage
if ($Mode -eq 'RepoAssign') {
    if (-not $RepoNWO) {
        Write-Error "RepoAssign mode requires -RepoNWO parameter (e.g., -RepoNWO 'octofelickz/juice-shop-felickz')"
        return
    }

    if (-not $AnalyzeOutput) {
        Write-Error "RepoAssign mode requires -AnalyzeOutput parameter. Generate with: appinspector analyze --source-path <source> --output-file-format json --output-file-path results.json --no-show-progress --tags-only --disable-archive-crawling --exclusion-globs '**/node_modules/**'"
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
        Write-Error ("Property '$propertyName' exceeds the 200 allowed_values limit ($($allowedValues.Count) values). " +
            "The merge table in this script needs to be updated to split this group into smaller sub-groups. " +
            "See `$mergeTable and Get-TagPropertyName. " +
            "Please report this issue to the script maintainer: https://github.com/felickz/scripts/issues")
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
$currentProps = Get-OrgProperties -Organization $Org
if ($currentProps) {
    $currentProps | ForEach-Object { Write-Host "  $($_.property_name) ($($_.value_type))" }
} else {
    Write-Host "  (none)" -ForegroundColor DarkGray
}

Write-Host "`n=== Applying Properties ===" -ForegroundColor Magenta
Set-OrgProperties -Organization $Org -Properties $propertyDefinitions

Write-Host "`n=== Updated Org Properties ===" -ForegroundColor Magenta
$updatedProps = Get-OrgProperties -Organization $Org
if ($updatedProps) {
    $updatedProps | ForEach-Object {
        $valCount = if ($_.allowed_values) { $_.allowed_values.Count } else { 0 }
        Write-Host "  $($_.property_name) ($($_.value_type), $valCount values)"
    }
}

