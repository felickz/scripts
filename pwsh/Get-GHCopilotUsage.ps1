# Authenticate with GitHub using the GitHub CLI
$auth = & gh auth token

# GitHub username (replace with your GitHub username)
$username = "felickz"

# GitHub API endpoint to get user events
$apiUrl = "https://api.github.com/users/$username/events"

# Create headers for the request
$headers = @{
    Authorization = "token $auth"
    Accept        = "application/vnd.github.v3+json"
}

# Make a request to the GitHub API
$response = Invoke-RestMethod -Uri $apiUrl -Headers $headers -Method Get

# Filter events for Copilot-related events and aggregate usage data by date
$usageReport = $response | Where-Object { $_.type -eq "CopilotEvent" } | Group-Object -Property { $_.created_at.Substring(0, 10) } | Select-Object @{Name="Date";Expression={$_.Name}}, @{Name="Queries";Expression={$_.Count}}

# Output the usage report
$usageReport | Format-Table -AutoSize

# Save the usage report to a file (optional)
#$usageReport | Export-Csv -Path "CopilotUsageReport.csv" -NoTypeInformation