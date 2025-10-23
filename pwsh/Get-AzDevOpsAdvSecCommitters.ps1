# az devops logout
# az logout


# az devops login --org https://dev.azure.com/<org>
# az devops login --org https://dev.azure.com/<org> --subscription <subscription-id>


# $azureDevopsResourceId = "499b84ac-1321-427f-aa17-267ca6975798"
# Just the token: az account get-access-token --query accessToken -o tsv
$token = az account get-access-token | ConvertFrom-Json
$authValue = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes(":" + $token.accessToken))

$headers = @{     Authorization = "Basic $authValue"; }

$organization = "octodemo-msft"
$pipelineRunUrl = "https://dev.azure.com/$organization/_apis/projects"
Write-Output "Projects in $organization :"
Invoke-RestMethod -Uri $pipelineRunUrl -Method GET -Headers $headers -ContentType 'application/json'


Write-Output "Org Potential Pushers in $organization :"
$orgPotentialPushers = "https://advsec.dev.azure.com/$organization/_apis/management/meterUsageEstimate/details?api-version=7.2-preview.1"
Invoke-RestMethod -Uri $orgPotentialPushers -Method GET -Headers $headers -ContentType 'application/json'

Write-Output "Org Pushers in $organization :"
$orgPushers = "https://advsec.dev.azure.com/$organization/_apis/management/meterUsageEstimate/default?api-version=7.2-preview.1"
Invoke-RestMethod -Uri $orgPushers -Method GET -Headers $headers -ContentType 'application/json'


$yesterday = (Get-Date).AddDays(-3).ToString("yyyy-MM-dd")
#$yesterday = "2025-01-28"
$orgMeterUsageUrl = "https://advsec.dev.azure.com/$organization/_apis/management/meterusage/default?billingDate=$yesterday&api-version=7.2-preview.1"
$orgMeterUsageUrlToday = "https://advsec.dev.azure.com/$organization/_apis/management/meterusage/default?api-version=7.2-preview.1"
$orgMeterUsage = Invoke-RestMethod -Uri $orgMeterUsageUrl -Method GET -Headers $headers -ContentType 'application/json'


Write-Output "Meter Usage Billed Users in $organization :"
# loop through billedUsers and output the userIdentiy converted to JSON - loop through each uniqueName and output as csv printed to output
$orgMeterUsage.billedUsers | ForEach-Object {
    Write-Output $_.userIdentity.uniqueName
}


#curl -H "Authorization: Bearer <insert_pat>" https://advsec.dev.azure.com/<insert_org>/_apis/reporting/summary/alerts\?criteria.alertTypes\=secret\&api-version\=7.2-preview.1 | jq '[.projects[].repos[].totalAlerts] | add'