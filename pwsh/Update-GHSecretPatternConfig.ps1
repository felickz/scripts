<#
.SYNOPSIS
    Summarize secret scanning push protection pattern configurations and optionally enable push protection.
.DESCRIPTION
    Uses the pattern-configurations API to fetch current push protection settings for all secret
    scanning patterns in one or more GitHub organizations. Categorizes patterns into:
      - Provider patterns (partner-detected secrets with default push protection)
      - Non-provider patterns (generic patterns like private keys, passwords, connection strings)
      - Custom patterns (custom patterns defined by the organization)

    Displays an aggregate summary table with alert totals, false positive rates, and push
    protection bypass rates per category. Then offers a menu to enable push protection,
    only updating patterns that are not already enabled.

    Requires API version 2026-03-10. Token needs read:org (list) or write:org (update) scope.
.PARAMETER Org
    The GitHub Organization name.
.PARAMETER Enterprise
    The GitHub Enterprise slug. If provided, aggregates across all orgs in the enterprise.
.EXAMPLE
    .\Update-GHSecretPatternConfig.ps1 -Org myorg
.EXAMPLE
    .\Update-GHSecretPatternConfig.ps1 -Enterprise my-enterprise
#>

param(
    [Parameter(ParameterSetName = "Org", Mandatory)]
    [string]$Org,

    [Parameter(ParameterSetName = "Enterprise", Mandatory)]
    [string]$Enterprise
)

$ApiVersion = "2026-03-10"

# Non-provider pattern slugs (generic patterns not tied to a specific provider)
$NonProviderSlugs = @(
    "ec_private_key",
    "generic_private_key",
    "http_basic_authentication_header",
    "http_bearer_authentication_header",
    "mongodb_connection_string",
    "mysql_connection_url",
    "openssh_private_key",
    "pgp_private_key",
    "postgres_connection_string",
    "rsa_private_key",
    "password"
)

# --- Resolve orgs ---
$orgs = @()
if ($Enterprise) {
    Write-Host "Fetching orgs for enterprise '$Enterprise'..." -ForegroundColor Cyan
    $hasNext = $true
    $cursor = $null
    while ($hasNext) {
        $gqlQuery = 'query($slug: String!, $cursor: String) { enterprise(slug: $slug) { organizations(first: 100, after: $cursor) { pageInfo { hasNextPage endCursor } nodes { login } } } }'
        $gqlArgs = @('-f', "slug=$Enterprise", '-F', "cursor=$cursor", '-f', "query=$gqlQuery")
        $raw = gh api graphql @gqlArgs 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Error "Failed to list orgs for enterprise '$Enterprise': $raw"
            Write-Warning "Ensure your token has the read:enterprise scope: gh auth refresh --scopes read:enterprise"
            exit 1
        }
        $result = $raw | ConvertFrom-Json
        $orgs += $result.data.enterprise.organizations.nodes | ForEach-Object { $_.login }
        $hasNext = $result.data.enterprise.organizations.pageInfo.hasNextPage
        $cursor = $result.data.enterprise.organizations.pageInfo.endCursor
    }
    $orgs = $orgs | Where-Object { $_ }
    Write-Host "Found $($orgs.Count) org(s)" -ForegroundColor Cyan
}
else {
    $orgs = @($Org)
}

# --- Fetch pattern configurations per org ---
# Store per-org config data for use during updates
$orgConfigs = @{}

# Aggregate all patterns across orgs for the summary
$allPatterns = @()

foreach ($o in $orgs) {
    Write-Host "Fetching pattern configurations for org '$o'..." -ForegroundColor Cyan
    $raw = gh api "/orgs/$o/secret-scanning/pattern-configurations" -H "X-GitHub-Api-Version: $ApiVersion" 2>&1
    if ($LASTEXITCODE -ne 0) {
        $rawStr = $raw -join " "
        if ($rawStr -match 'HTTP 403' -or $rawStr -match 'admin:org' -or $rawStr -match 'read:org') {
            Write-Host "  ✗ Org '$o': insufficient permissions (HTTP 403)" -ForegroundColor Red
            Write-Host "    Your token needs the 'read:org' scope. Run:" -ForegroundColor Yellow
            Write-Host "      gh auth refresh -h github.com -s read:org" -ForegroundColor White
        }
        elseif ($rawStr -match 'HTTP 404') {
            Write-Host "  ✗ Org '$o': not found (HTTP 404)" -ForegroundColor Red
            Write-Host "    Ensure secret scanning is enabled and the org name is correct." -ForegroundColor Yellow
        }
        else {
            Write-Warning "Failed to fetch pattern configurations for org '$o': $rawStr"
        }
        continue
    }
    $config = $raw | ConvertFrom-Json
    $orgConfigs[$o] = $config

    # Categorize provider patterns
    foreach ($p in $config.provider_pattern_overrides) {
        $category = if ($p.slug -in $NonProviderSlugs) { "Non-Provider" } else { "Provider" }
        $allPatterns += [PSCustomObject]@{
            Org                  = $o
            Category             = $category
            slug                 = $p.slug
            display_name         = $p.display_name
            token_type           = $p.token_type
            alert_total          = $p.alert_total
            alert_total_percentage = $p.alert_total_percentage
            false_positives      = $p.false_positives
            false_positive_rate  = $p.false_positive_rate
            bypass_rate          = $p.bypass_rate
            setting              = $p.setting
            default_setting      = $p.default_setting
        }
    }

    # Categorize custom patterns
    foreach ($p in $config.custom_pattern_overrides) {
        $allPatterns += [PSCustomObject]@{
            Org                  = $o
            Category             = "Custom"
            slug                 = $p.slug
            display_name         = $p.display_name
            token_type           = $p.token_type
            alert_total          = $p.alert_total
            alert_total_percentage = $p.alert_total_percentage
            false_positives      = $p.false_positives
            false_positive_rate  = $p.false_positive_rate
            bypass_rate          = $p.bypass_rate
            setting              = $p.setting
            default_setting      = $p.default_setting
        }
    }
}

if ($allPatterns.Count -eq 0) {
    Write-Host "`nNo pattern configurations found." -ForegroundColor Yellow
    exit 0
}

# --- Compute category metrics ---
$categories = @("Provider", "Non-Provider", "Custom")
$totalAlerts = ($allPatterns | Measure-Object -Property alert_total -Sum).Sum
$summaryRows = @()

foreach ($cat in $categories) {
    $catPatterns = $allPatterns | Where-Object { $_.Category -eq $cat }
    $catAlertTotal = ($catPatterns | Measure-Object -Property alert_total -Sum).Sum
    $catFalsePositives = ($catPatterns | Measure-Object -Property false_positives -Sum).Sum

    $pct = if ($totalAlerts -gt 0) { [math]::Round(($catAlertTotal / $totalAlerts) * 100, 1) } else { 0 }
    $fpRate = if ($catAlertTotal -gt 0) { [math]::Round(($catFalsePositives / $catAlertTotal) * 100, 1) } else { 0 }

    # Weighted average bypass rate across patterns that have alerts
    $patternsWithAlerts = $catPatterns | Where-Object { $_.alert_total -gt 0 }
    $weightedBypass = if (($patternsWithAlerts | Measure-Object).Count -gt 0 -and $catAlertTotal -gt 0) {
        $sumWeighted = ($patternsWithAlerts | ForEach-Object { $_.bypass_rate * $_.alert_total } | Measure-Object -Sum).Sum
        [math]::Round($sumWeighted / $catAlertTotal, 1)
    } else { 0 }

    $enabledCount = ($catPatterns | Where-Object { $_.setting -eq "enabled" -or ($_.setting -eq "not-set" -and $_.default_setting -eq "enabled") } | Measure-Object).Count
    $totalCount = ($catPatterns | Measure-Object).Count

    $summaryRows += [PSCustomObject]@{
        Category             = $cat
        alert_total          = $catAlertTotal
        alert_total_percentage = "$pct%"
        false_positives      = $catFalsePositives
        false_positive_rate  = "$fpRate%"
        bypass_rate          = "$weightedBypass%"
        push_protected       = "$enabledCount/$totalCount"
    }
}

# --- Display summary ---
Write-Host ""
Write-Host "Secret Scanning Alert Summary by Pattern Category" -ForegroundColor White
Write-Host ("=" * 100) -ForegroundColor DarkGray
Write-Host ""

$summaryRows | Format-Table -AutoSize -Property Category, alert_total, alert_total_percentage, false_positives, false_positive_rate, bypass_rate, push_protected

# Show patterns per category
# Non-Provider and Custom: list all patterns (small lists). Provider: top 10 with alerts.
foreach ($cat in $categories) {
    if ($cat -eq "Provider") {
        $catPatterns = $allPatterns | Where-Object { $_.Category -eq $cat -and $_.alert_total -gt 0 }
    }
    else {
        $catPatterns = $allPatterns | Where-Object { $_.Category -eq $cat }
    }
    if (($catPatterns | Measure-Object).Count -eq 0) { continue }

    $label = if ($cat -eq "Provider") { "Top patterns for '$cat'" } else { "All patterns for '$cat'" }
    Write-Host "  ${label}:" -ForegroundColor Yellow
    $selected = if ($cat -eq "Provider") { $catPatterns | Sort-Object -Property alert_total -Descending | Select-Object -First 10 } else { $catPatterns | Sort-Object -Property alert_total -Descending }
    $selected | ForEach-Object {
            $pushIcon = if ($_.setting -eq "enabled" -or ($_.setting -eq "not-set" -and $_.default_setting -eq "enabled")) { "[push]" } else { "      " }
            Write-Host "    $($_.alert_total.ToString().PadLeft(6))  $pushIcon  $($_.display_name) ($($_.slug))"
        }
    Write-Host ""
}

# --- Menu ---
Write-Host ("=" * 100) -ForegroundColor DarkGray
Write-Host ""
Write-Host "Push Protection Configuration Options:" -ForegroundColor White
Write-Host "  1. Enable push protection for ALL secret types" -ForegroundColor Cyan
Write-Host "  2. Enable push protection for all NON-PROVIDER patterns only" -ForegroundColor Cyan
Write-Host "  3. Reset all patterns to their default push protection setting" -ForegroundColor Cyan
Write-Host "  4. Exit (implement each pattern individually)" -ForegroundColor Cyan
Write-Host ""
$choice = Read-Host "Select an option (1-4)"

function Invoke-PatternConfigPatch {
    param(
        [string]$OrgName,
        [hashtable]$Body,
        [string]$SuccessMessage
    )

    $jsonBody = $Body | ConvertTo-Json -Depth 5 -Compress
    $raw = $jsonBody | gh api --method PATCH "/orgs/$OrgName/secret-scanning/pattern-configurations" -H "X-GitHub-Api-Version: $ApiVersion" --input - 2>&1
    if ($LASTEXITCODE -ne 0) {
        $rawStr = $raw -join " "
        if ($rawStr -match 'HTTP 403' -or $rawStr -match 'admin:org') {
            Write-Host "  ✗ Org '$OrgName': insufficient permissions (HTTP 403)" -ForegroundColor Red
            Write-Host "    Your token needs the 'admin:org' scope. Run:" -ForegroundColor Yellow
            Write-Host "      gh auth refresh -h github.com -s admin:org" -ForegroundColor White
        }
        elseif ($rawStr -match 'HTTP 409') {
            Write-Host "  ✗ Org '$OrgName': conflict — pattern config was modified by another user (HTTP 409)" -ForegroundColor Red
            Write-Host "    Re-run the script to fetch the latest config version and try again." -ForegroundColor Yellow
        }
        elseif ($rawStr -match 'HTTP 404') {
            Write-Host "  ✗ Org '$OrgName': not found (HTTP 404)" -ForegroundColor Red
            Write-Host "    Ensure secret scanning is enabled and the org name is correct." -ForegroundColor Yellow
        }
        else {
            Write-Warning "Failed to update org '$OrgName': $rawStr"
        }
    }
    else {
        Write-Host "  ✓ Org '$OrgName': $SuccessMessage" -ForegroundColor Green
    }
}

function Update-PushProtection {
    param(
        [string]$OrgName,
        [object]$Config,
        [string[]]$TargetSlugs  # if empty/null, target all patterns
    )

    $providerChanges = @()
    $customChanges = @()

    foreach ($p in $Config.provider_pattern_overrides) {
        # Skip if targeting specific slugs and this isn't one of them
        if ($TargetSlugs -and $p.slug -notin $TargetSlugs) { continue }

        # Already effectively enabled — no change needed
        $effective = if ($p.setting -eq "not-set") { $p.default_setting } else { $p.setting }
        if ($effective -eq "enabled") { continue }

        $providerChanges += @{ token_type = $p.token_type; push_protection_setting = "enabled" }
    }

    foreach ($p in $Config.custom_pattern_overrides) {
        if ($TargetSlugs -and $p.slug -notin $TargetSlugs) { continue }

        if ($p.setting -eq "enabled") { continue }

        $customChanges += @{
            token_type              = $p.token_type
            custom_pattern_version  = $p.custom_pattern_version
            push_protection_setting = "enabled"
        }
    }

    $totalChanges = $providerChanges.Count + $customChanges.Count
    if ($totalChanges -eq 0) {
        Write-Host "  ✓ Org '$OrgName': all targeted patterns already have push protection enabled" -ForegroundColor Green
        return
    }

    Write-Host "  Org '$OrgName': updating $totalChanges pattern(s)..." -ForegroundColor Cyan

    $body = @{ pattern_config_version = $Config.pattern_config_version }
    if ($providerChanges.Count -gt 0) { $body.provider_pattern_settings = $providerChanges }
    if ($customChanges.Count -gt 0)   { $body.custom_pattern_settings = $customChanges }

    Invoke-PatternConfigPatch -OrgName $OrgName -Body $body -SuccessMessage "push protection enabled for $totalChanges pattern(s)"
}

function Reset-PushProtectionToDefault {
    param(
        [string]$OrgName,
        [object]$Config
    )

    $providerChanges = @()
    $customChanges = @()

    foreach ($p in $Config.provider_pattern_overrides) {
        # Only reset patterns whose setting differs from "not-set" (i.e. has been overridden)
        if ($p.setting -eq "not-set") { continue }

        $providerChanges += @{ token_type = $p.token_type; push_protection_setting = "not-set" }
    }

    foreach ($p in $Config.custom_pattern_overrides) {
        if ($p.setting -eq $p.default_setting) { continue }

        $targetSetting = if ($p.default_setting -eq "enabled") { "enabled" } else { "disabled" }
        $customChanges += @{
            token_type              = $p.token_type
            custom_pattern_version  = $p.custom_pattern_version
            push_protection_setting = $targetSetting
        }
    }

    $totalChanges = $providerChanges.Count + $customChanges.Count
    if ($totalChanges -eq 0) {
        Write-Host "  ✓ Org '$OrgName': all patterns already match their default settings" -ForegroundColor Green
        return
    }

    Write-Host "  Org '$OrgName': resetting $totalChanges pattern(s) to defaults..." -ForegroundColor Cyan

    $body = @{ pattern_config_version = $Config.pattern_config_version }
    if ($providerChanges.Count -gt 0) { $body.provider_pattern_settings = $providerChanges }
    if ($customChanges.Count -gt 0)   { $body.custom_pattern_settings = $customChanges }

    Invoke-PatternConfigPatch -OrgName $OrgName -Body $body -SuccessMessage "$totalChanges pattern(s) reset to defaults"
}

switch ($choice) {
    "1" {
        Write-Host "`nEnabling push protection for all secret types..." -ForegroundColor Yellow
        foreach ($o in $orgs) {
            if (-not $orgConfigs.ContainsKey($o)) { continue }
            Update-PushProtection -OrgName $o -Config $orgConfigs[$o] -TargetSlugs $null
        }
    }
    "2" {
        Write-Host "`nEnabling push protection for non-provider patterns..." -ForegroundColor Yellow
        foreach ($o in $orgs) {
            if (-not $orgConfigs.ContainsKey($o)) { continue }
            Update-PushProtection -OrgName $o -Config $orgConfigs[$o] -TargetSlugs $NonProviderSlugs
        }
    }
    "3" {
        Write-Host "`nResetting all patterns to default push protection settings..." -ForegroundColor Yellow
        foreach ($o in $orgs) {
            if (-not $orgConfigs.ContainsKey($o)) { continue }
            Reset-PushProtectionToDefault -OrgName $o -Config $orgConfigs[$o]
        }
    }
    "4" {
        Write-Host "`nExiting. Review the summary above to plan per-pattern implementation." -ForegroundColor Yellow
    }
    default {
        Write-Host "`nInvalid selection. Exiting." -ForegroundColor Red
    }
}
