# Usage: .\Delete-AllCodeQLAnalyses.ps1 -Org <org> -Repo <repo> -Ref <ref> -Tool <tool>

param (
    [string]$Org = "advanced-security",
    [string]$Repo = "sample-javascript-monorepo",
    [string]$Ref = "refs/heads/main",
    [string]$Tool = "CodeQL"
)

# Get the GitHub token from gh auth
$GITHUB_TOKEN = & gh auth token

$REQ_URL = "https://api.github.com/repos/$Org/$Repo/code-scanning/analyses?ref=$Ref"

Write-Output $REQ_URL
Write-Output "REF: $Ref"
Write-Output "TOOL: $Tool"

# Initialize variables for pagination
$ANALYSIS_URLS = @()
$NEXT_URL = $REQ_URL

do {
    # Fetch the current page of results
    $response = Invoke-RestMethod -Method Get `
        -Uri $NEXT_URL `
        -Headers @{
            "Accept" = "application/vnd.github+json"
            "Authorization" = "token $GITHUB_TOKEN"
        }

    # Extract analysis URLs matching the criteria
    $ANALYSIS_URLS += $response `
        | ConvertTo-Json `
        | jq --arg REF "$Ref" --arg TOOL "$Tool" -r '.[] | select((.ref == $REF) and (.deletable == true) and (.tool.name == $TOOL)) | .url'

    # Check for the 'next' link in the Link header
    $NEXT_URL = $response.PSObject.Properties["Link"]?.Value -match '<(.*?)>; rel="next"' ? $matches[1] : $null

} while ($NEXT_URL)

# Output the collected analysis URLs
Write-Output $ANALYSIS_URLS


foreach ($URL in $ANALYSIS_URLS) {
    while ($URL -ne "null") {
        $RESP = Invoke-RestMethod -Method Delete `
            -Uri "${URL}?confirm_delete" `
            -Headers @{
                "Accept" = "application/vnd.github+json"
                "Authorization" = "token $GITHUB_TOKEN"
            } `

            $URL =   $RESP `
            | ConvertTo-Json `
            | jq -r '.next_analysis_url'

        Write-Output $URL
    }
}