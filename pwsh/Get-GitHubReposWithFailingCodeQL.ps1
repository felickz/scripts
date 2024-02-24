# find any CodeQL named runs and get their latest status
# - use the gh cli (easy auth and query apis)
# - search for all repos in an org
# - workflows named "CodeQl" running in an action - EXCLUDE PRs (this is the standard naming for default setup - COULD be used for advanced but not our focus in this script!)
# - Report if the scans were building successful or not (conclusion)

# Determines if it is a CodeQL default setup workflow if the workflow path starts with "dynamic"

# Use this script to output a csv file to actions upload: https://github.com/vulna-felickz/.github/edit/main/.github/workflows/codeql-org-report.yml

#results:
# |Conclusion|Is\_Default|Org|Repo|Workflow\_Path|Workflow\_Url|
# |:--|:--|:--|:--|:--|:--|
# |success|False|vulna-felickz|WebGoat.NET|.github/workflows/codeql-analysis.yml|https://github.com/vulna-felickz/WebGoat.NET/actions/runs/8019411601|
# |success|False|vulna-felickz|log4shell-vulnerable-app|.github/workflows/codeql-analysis.yml|https://github.com/vulna-felickz/log4shell-vulnerable-app/actions/runs/5289516341|
# |null|False|vulna-felickz|my-spring-log4j-vuln-sample|.github/workflows/codeql-analysis.yml|null|
# |success|False|vulna-felickz|FullDotNetWebApp|.github/workflows/codeql.yml|https://github.com/vulna-felickz/FullDotNetWebApp/actions/runs/7780125962|
# |success|False|vulna-felickz|DotNetCoreWebApp|.github/workflows/codeql.yml|https://github.com/vulna-felickz/DotNetCoreWebApp/actions/runs/7716451772|
# |success|False|vulna-felickz|puma-prey|.github/workflows/codeql.yml|https://github.com/vulna-felickz/puma-prey/actions/runs/7946337933|
# |null|False|vulna-felickz|code-scanning-javascript-demo|.github/workflows/codeql-analysis.yml|null|
# |null|False|vulna-felickz|BenchmarkJava|.github/workflows/codeql-analysis.yml|null|
# |success|False|vulna-felickz|babel|.github/workflows/codeql-analysis.yml|https://github.com/vulna-felickz/babel/actions/runs/7954662269|
# |null|False|vulna-felickz|Damn-Vulnerable-GraphQL-Application|.github/workflows/codeql-analysis.yml|null|
# |success|False|vulna-felickz|WebGoat|.github/workflows/codeql-analysis.yml|https://github.com/vulna-felickz/WebGoat/actions/runs/7952160077|
# |success|False|vulna-felickz|railsgoat|.github/workflows/codeql-analysis.yml|https://github.com/vulna-felickz/railsgoat/actions/runs/7967722774|
# |success|False|vulna-felickz|VulnerableApp|.github/workflows/codeql.yml|https://github.com/vulna-felickz/VulnerableApp/actions/runs/7954709690|
# |success|False|vulna-felickz|demo-java|.github/workflows/codeql.yml|https://github.com/vulna-felickz/demo-java/actions/runs/4263592915|
# |success|False|vulna-felickz|python-request|.github/workflows/codeql.yml|https://github.com/vulna-felickz/python-request/actions/runs/4512232580|
# |success|False|vulna-felickz|OwaspTop10Examples|.github/workflows/codeql.yml|https://github.com/vulna-felickz/OwaspTop10Examples/actions/runs/7954645134|
# |success|False|vulna-felickz|CodeQL-Hardcoded-DB-Creds-Java|.github/workflows/codeql.yml|https://github.com/vulna-felickz/CodeQL-Hardcoded-DB-Creds-Java/actions/runs/4765934736|
# |failure|False|vulna-felickz|norma|.github/workflows/codeql.yml|https://github.com/vulna-felickz/norma/actions/runs/4712835511|
# |success|True|vulna-felickz|vulnerable-express|dynamic/github-code-scanning/codeql|https://github.com/vulna-felickz/vulnerable-express/actions/runs/5488120897|
# |success|True|vulna-felickz|vulnerable-express|dynamic/github-code-scanning/codeql|https://github.com/vulna-felickz/vulnerable-express/actions/runs/4771427796|
# |success|False|vulna-felickz|felickz-juice-shop|.github/workflows/codeql.yml|https://github.com/vulna-felickz/felickz-juice-shop/actions/runs/7950039676|
# |failure|False|vulna-felickz|JavaVulnerableLab|.github/workflows/codeql.yml|https://github.com/vulna-felickz/JavaVulnerableLab/actions/runs/5534779512|
# |success|True|vulna-felickz|ts-jose-jwtdecode|dynamic/github-code-scanning/codeql|https://github.com/vulna-felickz/ts-jose-jwtdecode/actions/runs/6835036147|
# |success|True|vulna-felickz|go-zipslip|dynamic/github-code-scanning/codeql|https://github.com/vulna-felickz/go-zipslip/actions/runs/6836979722|
# |success|False|vulna-felickz|netcore-mvc-razor-xss|.github/workflows/codeql.yml|https://github.com/vulna-felickz/netcore-mvc-razor-xss/actions/runs/7940784369|
# |success|True|vulna-felickz|python-flask|dynamic/github-code-scanning/codeql|https://github.com/vulna-felickz/python-flask/actions/runs/5843840555|
# |success|True|vulna-felickz|python-flask|dynamic/github-code-scanning/codeql|https://github.com/vulna-felickz/python-flask/actions/runs/5196215116|
# |failure|True|vulna-felickz|dvta|dynamic/github-code-scanning/codeql|https://github.com/vulna-felickz/dvta/actions/runs/5895551266|
# |success|False|vulna-felickz|orchestration-demo|.github/workflows/codeql.yml|https://github.com/vulna-felickz/orchestration-demo/actions/runs/6720946958|
# |success|True|vulna-felickz|felickz-WebGoat-default|dynamic/github-code-scanning/codeql|https://github.com/vulna-felickz/felickz-WebGoat-default/actions/runs/6902314132|
# |failure|True|vulna-felickz|felickz-WebGoat-default|dynamic/github-code-scanning/codeql|https://github.com/vulna-felickz/felickz-WebGoat-default/actions/runs/6176623595|
# |success|True|vulna-felickz|logger-extension-sanitizer|dynamic/github-code-scanning/codeql|https://github.com/vulna-felickz/logger-extension-sanitizer/actions/runs/7993853243|
# |success|False|vulna-felickz|go-weak-crypto|.github/workflows/codeql.yml|https://github.com/vulna-felickz/go-weak-crypto/actions/runs/7072438824|
# |failure|True|vulna-felickz|WebGoat-default|dynamic/github-code-scanning/codeql|https://github.com/vulna-felickz/WebGoat-default/actions/runs/6424311141|
# |success|False|vulna-felickz|js-postmessage|.github/workflows/codeql.yml|https://github.com/vulna-felickz/js-postmessage/actions/runs/7284385995|
# |success|True|vulna-felickz|python-clear-text-log|dynamic/github-code-scanning/codeql|https://github.com/vulna-felickz/python-clear-text-log/actions/runs/8017910177|
# |success|True|vulna-felickz|go-xxe|dynamic/github-code-scanning/codeql|https://github.com/vulna-felickz/go-xxe/actions/runs/7977001132|
# |success|False|vulna-felickz|dvcsharp-api|.github/workflows/codeql.yml|https://github.com/vulna-felickz/dvcsharp-api/actions/runs/8000424963|
# |failure|False|vulna-felickz|WebGoat.Net46|.github/workflows/codeql.yml|https://github.com/vulna-felickz/WebGoat.Net46/actions/runs/8015188622|
# |null|True|vulna-felickz|WebGoat-Autobuild|dynamic/github-code-scanning/codeql|null|
# |failure|True|vulna-felickz|WebGoat-Autobuild|dynamic/github-code-scanning/codeql|https://github.com/vulna-felickz/WebGoat-Autobuild/actions/runs/8026262312|


$org = "vulna-felickz"
$csv = "CodeQLWorkflowStatus.csv"
$header = "Conclusion,Workflow_Url,Is_Default,Org,Repo,Workflow_Path"
Set-Content -Path "./$csv" -Value $header

gh api /orgs/$org/repos --paginate `
| jq -r '.[] | .name' `
| %{ `
    $name = $_; gh api /repos/$org/$_/actions/workflows --paginate `
    # Need jq -c (compact) so that the JSON removes newlines and can be converted below `
    | jq -c '.workflows[] | select(.name=="CodeQL") | {id: .id, path: .path}' `
    | %{ `
        $workflow = $_ | ConvertFrom-Json; `
        gh api /repos/$org/$name/actions/workflows/$($workflow.id)/runs?exclude_pull_requests=true `
        } `
    | jq -r '.workflow_runs[0] | "\(.conclusion),\(.html_url)"' `
    | %{ "$_,$($workflow.path.StartsWith("dynamic/")),$org,$name,$($workflow.path)" } `
    | Add-Content -Path "./$csv" `
}


#check if FormatMarkdownTable module is installed
if (Get-Module -ListAvailable -Name FormatMarkdownTable -ErrorAction SilentlyContinue) {
    Write-Output "FormatMarkdownTable module is installed"
}
else {
    # Handle `Untrusted repository` prompt
    Set-PSRepository PSGallery -InstallationPolicy Trusted
    #directly to output here before module loaded to support Write-ActionInfo
    Write-Output "FormatMarkdownTable module is not installed.  Installing from Gallery..."
    Install-Module -Name FormatMarkdownTable
}

$markdownSummary = Import-Csv -Path "./$csv" | Format-MarkdownTableTableStyle -ShowMarkdown -DoNotCopyToClipboard -HideStandardOutput
$markdownSummary > $env:GITHUB_STEP_SUMMARY

if ($null -eq $env:GITHUB_ACTIONS) {
    $markdownSummary
}