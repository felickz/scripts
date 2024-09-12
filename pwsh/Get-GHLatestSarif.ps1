$tool = "CodeQL" #"ZAProxy"
$nwo = "octodemo/latam-calculator" #name with owner
gh api -H "Accept: application/vnd.github+json" "/repos/$nwo/code-scanning/analyses?tool_name=$tool&per_page=1" | ConvertFrom-Json | Select-Object -ExpandProperty id | % { gh api -H "Accept: application/sarif+json" "/repos/$nwo/code-scanning/analyses/$_" } > latest-$tool-analysis.sarif