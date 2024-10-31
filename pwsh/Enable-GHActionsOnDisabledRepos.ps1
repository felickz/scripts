#Auth the GH cli via one of these mechanisms:
# - gh auth refresh -h github.com -s admin:org
# - $Env:GH_TOKEN = <PAT>
$org = "octofelickz"

Write-Host "Starting at $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
# Get all non-archived, non-disabled repos and check/enable Actions
# Ignore templates? .is_template == false
gh api "/orgs/$org/repos" --paginate --jq '[ .[] | select(.archived == false and .disabled == false) | { name: .name } ] | .[].name ' |
ForEach-Object {
    #Ignore repos that are temporary private forks for security advisory vulnerablibility reporting (ex: <reponame>-ghsa-<ghsa-id> )
    if ($_ -notmatch "-ghsa(-[23456789cfghjmpqrvwx]{4}){3}$") {
        if ((gh api "/repos/$org/$_/actions/permissions" --jq '.enabled') -eq 'false') {
            gh api --method PUT "/repos/$org/$_/actions/permissions" -F "enabled=true" --silent
            Write-Host "Enabled Actions for '$org/$_'"
        }
    }
}
Write-Host "Ending at $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"