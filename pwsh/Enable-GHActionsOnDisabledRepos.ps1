$org = "octofelickz"

Write-Host "Starting at $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
# Get all non-archived, non-disabled repos and check/enable Actions
# Ignore templates? .is_template == false
gh api "/orgs/$org/repos" --paginate --jq '[ .[] | select(.archived == false and .disabled == false) | { name: .name } ] | .[].name ' |
ForEach-Object {
    #Ignore repos that are temporary private forks for security advisory vulnerablibility reporting (ex: <name>-ghsa-4xcm-h78r-r3ww)
    if ($_ -notmatch "-ghsa-[a-zA-Z0-9]{4}-[a-zA-Z0-9]{4}-[a-zA-Z0-9]{4}$") {
        if ((gh api "/repos/$org/$_/actions/permissions" --jq '.enabled') -eq 'false') {
            gh api --method PUT "/repos/$org/$_/actions/permissions" -F "enabled=true" --silent
            Write-Host "Enabled Actions for '$org/$_'"
        }
    }
}
Write-Host "Ending at $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"