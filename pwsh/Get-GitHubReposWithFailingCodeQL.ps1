# find any CodeQL named runs and get their latest status
# - use the gh cli (easy auth and query apis)
# - search for all repos in an org
# - workflows named "CodeQl" running in an action - EXCLUDE PRs
# - Report if the scans were building successful or not (conclusion)

#results:
# success - https://github.com/vulna-felickz/WebGoat.NET/actions/runs/8019411601 (WebGoat.NET)
# success - https://github.com/vulna-felickz/WebGoat.NET-CORE/actions/runs/7963273004 (WebGoat.NET-CORE)
# success - https://github.com/vulna-felickz/log4shell-vulnerable-app/actions/runs/5289516341 (log4shell-vulnerable-app)
# null - null (my-spring-log4j-vuln-sample)
# success - https://github.com/vulna-felickz/reactvulna/actions/runs/5780665366 (reactvulna)
# success - https://github.com/vulna-felickz/FullDotNetWebApp/actions/runs/7780125962 (FullDotNetWebApp)
# success - https://github.com/vulna-felickz/DotNetCoreWebApp/actions/runs/7716451772 (DotNetCoreWebApp)
# success - https://github.com/vulna-felickz/puma-prey/actions/runs/7946337933 (puma-prey)
# null - null (code-scanning-javascript-demo)
# null - null (BenchmarkJava)
# success - https://github.com/vulna-felickz/babel/actions/runs/7954662269 (babel)
# null - null (Damn-Vulnerable-GraphQL-Application)
# success - https://github.com/vulna-felickz/DotNetCoreWebAPI/actions/runs/7967201683 (DotNetCoreWebAPI)
# success - https://github.com/vulna-felickz/WebGoat/actions/runs/7952160077 (WebGoat)
# success - https://github.com/vulna-felickz/railsgoat/actions/runs/7967722774 (railsgoat)
# success - https://github.com/vulna-felickz/VulnerableApp/actions/runs/7954709690 (VulnerableApp)
# success - https://github.com/vulna-felickz/demo-java/actions/runs/4263592915 (demo-java)

$org = "vulna-felickz"; `
gh api /orgs/$org/repos `
| jq -r '.[] | .name' `
| %{ `
    $name = $_; gh api /repos/$org/$_/actions/workflows `
    | jq '.workflows[] | select(.name=="CodeQL") | .id' `
    | % { gh api /repos/$org/$name/actions/workflows/$_/runs?exclude_pull_requests=true } `
    | jq -r '.workflow_runs[0] | "\(.conclusion) - \(.html_url)"'`
    | %{ "$_ ($name)" } `
}
