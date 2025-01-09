#  gh api /repos/octodemo/webgoat/code-scanning/analyses --paginate --jq '.[] | select(.ref == "refs/heads/main") | .category' | sort -u
$nwo = "octodemo/webgoat"
$branch = "refs/heads/main"

$jqFilter = @"
.[] | select(.ref == `"$branch`") | .category
"@

gh api "/repos/$nwo/code-scanning/analyses" --paginate --jq "$jqFilter" | Sort-Object -Unique