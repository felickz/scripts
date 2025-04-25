# Create an autofix/PR for a code scanning alert

$nwo = "dsp-testing/actions-injection-bad-autofix"
$alert = "27"


# https://docs.github.com/en/rest/code-scanning/code-scanning?apiVersion=2022-11-28#create-an-autofix-for-a-code-scanning-alert
# Create succeeds even if exists, so dont even both r calling GET
$autofixResult = gh api --method POST "/repos/$nwo/code-scanning/alerts/$alert/autofix"

$autofix = $autofixResult | ConvertFrom-Json
Write-Host "Create Autofix for $alert Status: $($autofix | Select-Object -ExpandProperty status )"

$branch = "alert-autofix-$alert-generated"
$defaultBranch = (gh api "repos/$nwo" | jq -r .default_branch).ToString()
$sha = (gh api "repos/$nwo/git/refs/heads/$defaultBranch" | jq -r .object.sha).ToString()

# create branch wiht gh api
gh api -X POST "repos/$nwo/git/refs" -f ref="refs/heads/$branch" -f sha=$sha

# https://docs.github.com/en/rest/code-scanning/code-scanning?apiVersion=2022-11-28#commit-an-autofix-for-a-code-scanning-alert
gh api --method POST "/repos/$nwo/code-scanning/alerts/$alert/autofix/commits" -f "target_ref=refs/heads/$branch" -f "message=Let's fix this 🪲!"

$alertDescription = (gh api "repos/$nwo/code-scanning/alerts/$alert" | jq -r .rule.description).ToString()
# use the GH CLI to create a PR for the autofix branch
$body = @"
Potential fix for [https://github.com/$nwo/security/code-scanning/$alert](https://github.com/$nwo/security/code-scanning/$alert)

$($autofix | Select-Object -ExpandProperty description )
"@

gh pr create --repo $nwo --base $defaultBranch --head $branch --draft --title "Potential fix for code scanning alert no. $alert : $alertDescription" --body $body

