# find any CodeQL named runs and get their latest status.. i took some liberty in this sample but if you wanted to search for all repos in an org who have codeql running in an action and see if the scans were building successful

#results:
# success - https://github.com/vulna-felickz/WebGoat.NET/actions/runs/3497120617
#success - https://github.com/vulna-felickz/WebGoat.NET-CORE/actions/runs/6383441854
#success - https://github.com/vulna-felickz/log4shell-vulnerable-app/actions/runs/5289516341
#success - https://github.com/vulna-felickz/reactvulna/actions/runs/5780665366
#success - https://github.com/vulna-felickz/FullDotNetWebApp/actions/runs/5173725533
#success - https://github.com/vulna-felickz/DotNetCoreWebApp/actions/runs/4483110033
#success - https://github.com/vulna-felickz/code-scanning-javascript-demo/actions/runs/2633836803
#success - https://github.com/vulna-felickz/BenchmarkJava/actions/runs/2685850607
#failure - https://github.com/vulna-felickz/babel/actions/runs/6376049500
#success - https://github.com/vulna-felickz/Damn-Vulnerable-GraphQL-Application/actions/runs/2819556620
#failure - https://github.com/vulna-felickz/DotNetCoreWebAPI/actions/runs/6387549363
#success - https://github.com/vulna-felickz/WebGoat/actions/runs/5372117418
#success - https://github.com/vulna-felickz/railsgoat/actions/runs/4793129543
#success - https://github.com/vulna-felickz/VulnerableApp/actions/runs/4401479230
$org = "vulna-felickz"; gh api /orgs/$org/repos |  jq -r '.[] | .name' | %{ $name = $_; gh api /repos/$org/$_/actions/workflows | jq '.workflows[] | select(.name=="CodeQL") | .id' | % { gh api /repos/$org/$name/actions/workflows/$_/runs?exclude_pull_requests=true } | jq -r '.workflow_runs[0] | "\(.conclusion) - \(.html_url)"' }
