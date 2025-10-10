param(
    [Parameter(Mandatory=$true)]
    [string]$OrgName
)

# Get unique CVEs from Dependabot alerts
$cves = gh api /orgs/$OrgName/dependabot/alerts --paginate --jq '.[].security_advisory.cve_id' | Sort-Object -Unique

# Fetch KEV catalog
$kev = (Invoke-WebRequest 'https://www.cisa.gov/sites/default/files/feeds/known_exploited_vulnerabilities.json').Content | ConvertFrom-Json

# Cross-reference and display matches
$kevCves = $kev.vulnerabilities.cveID
$kevMatches = $cves | Where-Object { $kevCves -contains $_ }

if ($kevMatches) {
    Write-Host "`n⚠️  CRITICAL: Found $($kevMatches.Count) Dependabot alert(s) in CISA KEV catalog:`n" -ForegroundColor Red
    $kevMatches | ForEach-Object {
        $currentCve = $_.Trim()
        $vuln = $kev.vulnerabilities | Where-Object { $_.cveID.Trim() -eq $currentCve }
        if ($vuln) {
            Write-Host "CVE: $($vuln.cveID)" -ForegroundColor Yellow
            Write-Host "  Product: $($vuln.vendorProject) $($vuln.product)"
            Write-Host "  Name: $($vuln.vulnerabilityName)"
            Write-Host "  Due Date: $($vuln.dueDate)"
            Write-Host "  Ransomware: $($vuln.knownRansomwareCampaignUse)`n"
        } else {
            Write-Host "CVE: $currentCve - NOT FOUND in KEV data" -ForegroundColor Magenta
        }
    }
} else {
    Write-Host "`n✓ No Dependabot alerts found in CISA KEV catalog" -ForegroundColor Green
}
