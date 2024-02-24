# find any CodeQL named runs and get their latest status
# - use the gh cli (easy auth and query apis)
# - search for all repos in an org
# - workflows named "CodeQl" running in an action - EXCLUDE PRs
# - Report if the scans were building successful or not (conclusion)

# Use this script to output a csv file to actions upload: https://github.com/vulna-felickz/.github/edit/main/.github/workflows/codeql-org-report.yml

#results:
# Conclusion Workflow_Url                                                                            Org           Repo                                Workflow_Path
# ---------- ------------                                                                            ---           ----                                -------------
# success    https://github.com/vulna-felickz/WebGoat.NET/actions/runs/8019411601                    vulna-felickz WebGoat.NET                         .github/workflows/codeql-analysis.yml
# success    https://github.com/vulna-felickz/WebGoat.NET-CORE/actions/runs/7963273004               vulna-felickz WebGoat.NET-CORE                    .github/workflows/codeql-analysis.yml
# success    https://github.com/vulna-felickz/log4shell-vulnerable-app/actions/runs/5289516341       vulna-felickz log4shell-vulnerable-app            .github/workflows/codeql-analysis.yml
# null       null                                                                                    vulna-felickz my-spring-log4j-vuln-sample         .github/workflows/codeql-analysis.yml
# success    https://github.com/vulna-felickz/reactvulna/actions/runs/5780665366                     vulna-felickz reactvulna                          .github/workflows/codeql-analysis.yml
# success    https://github.com/vulna-felickz/FullDotNetWebApp/actions/runs/7780125962               vulna-felickz FullDotNetWebApp                    .github/workflows/codeql.yml
# success    https://github.com/vulna-felickz/DotNetCoreWebApp/actions/runs/7716451772               vulna-felickz DotNetCoreWebApp                    .github/workflows/codeql.yml
# success    https://github.com/vulna-felickz/puma-prey/actions/runs/7946337933                      vulna-felickz puma-prey                           .github/workflows/codeql.yml
# null       null                                                                                    vulna-felickz code-scanning-javascript-demo       .github/workflows/codeql-analysis.yml
# null       null                                                                                    vulna-felickz BenchmarkJava                       .github/workflows/codeql-analysis.yml
# success    https://github.com/vulna-felickz/babel/actions/runs/7954662269                          vulna-felickz babel                               .github/workflows/codeql-analysis.yml
# null       null                                                                                    vulna-felickz Damn-Vulnerable-GraphQL-Application .github/workflows/codeql-analysis.yml
# success    https://github.com/vulna-felickz/DotNetCoreWebAPI/actions/runs/7967201683               vulna-felickz DotNetCoreWebAPI                    .github/workflows/codeql-analysis.yml
# success    https://github.com/vulna-felickz/WebGoat/actions/runs/7952160077                        vulna-felickz WebGoat                             .github/workflows/codeql-analysis.yml
# success    https://github.com/vulna-felickz/railsgoat/actions/runs/7967722774                      vulna-felickz railsgoat                           .github/workflows/codeql-analysis.yml
# success    https://github.com/vulna-felickz/VulnerableApp/actions/runs/7954709690                  vulna-felickz VulnerableApp                       .github/workflows/codeql.yml
# success    https://github.com/vulna-felickz/demo-java/actions/runs/4263592915                      vulna-felickz demo-java                           .github/workflows/codeql.yml
# success    https://github.com/vulna-felickz/python-request/actions/runs/4512232580                 vulna-felickz python-request                      .github/workflows/codeql.yml
# success    https://github.com/vulna-felickz/OwaspTop10Examples/actions/runs/7954645134             vulna-felickz OwaspTop10Examples                  .github/workflows/codeql.yml
# success    https://github.com/vulna-felickz/CodeQL-Hardcoded-DB-Creds-Java/actions/runs/4765934736 vulna-felickz CodeQL-Hardcoded-DB-Creds-Java      .github/workflows/codeql.yml
# failure    https://github.com/vulna-felickz/norma/actions/runs/4712835511                          vulna-felickz norma                               .github/workflows/codeql.yml
# success    https://github.com/vulna-felickz/vulnerable-express/actions/runs/5488120897             vulna-felickz vulnerable-express                  dynamic/github-code-scanning/codeql
# success    https://github.com/vulna-felickz/vulnerable-express/actions/runs/4771427796             vulna-felickz vulnerable-express                  dynamic/github-code-scanning/codeql
# success    https://github.com/vulna-felickz/felickz-juice-shop/actions/runs/7950039676             vulna-felickz felickz-juice-shop                  .github/workflows/codeql.yml
# success    https://github.com/vulna-felickz/Vulnerability-goapp/actions/runs/6678031794            vulna-felickz Vulnerability-goapp                 dynamic/github-code-scanning/codeql
# failure    https://github.com/vulna-felickz/JavaVulnerableLab/actions/runs/5534779512              vulna-felickz JavaVulnerableLab                   .github/workflows/codeql.yml
# success    https://github.com/vulna-felickz/testing-go-function/actions/runs/6785210118            vulna-felickz testing-go-function                 dynamic/github-code-scanning/codeql
# success    https://github.com/vulna-felickz/ts-jose-jwtdecode/actions/runs/6835036147              vulna-felickz ts-jose-jwtdecode                   dynamic/github-code-scanning/codeql
# success    https://github.com/vulna-felickz/go-zipslip/actions/runs/6836979722                     vulna-felickz go-zipslip                          dynamic/github-code-scanning/codeql
# success    https://github.com/vulna-felickz/netcore-mvc-razor-xss/actions/runs/7940784369          vulna-felickz netcore-mvc-razor-xss               .github/workflows/codeql.yml
# success    https://github.com/vulna-felickz/python-flask/actions/runs/5843840555                   vulna-felickz python-flask                        dynamic/github-code-scanning/codeql
# success    https://github.com/vulna-felickz/python-flask/actions/runs/5196215116                   vulna-felickz python-flask                        dynamic/github-code-scanning/codeql
# failure    https://github.com/vulna-felickz/dvta/actions/runs/5895551266                           vulna-felickz dvta                                dynamic/github-code-scanning/codeql
# success    https://github.com/vulna-felickz/orchestration-demo/actions/runs/6720946958             vulna-felickz orchestration-demo                  .github/workflows/codeql.yml
# success    https://github.com/vulna-felickz/felickz-WebGoat-default/actions/runs/6902314132        vulna-felickz felickz-WebGoat-default             dynamic/github-code-scanning/codeql
# failure    https://github.com/vulna-felickz/felickz-WebGoat-default/actions/runs/6176623595        vulna-felickz felickz-WebGoat-default             dynamic/github-code-scanning/codeql
# success    https://github.com/vulna-felickz/logger-extension-sanitizer/actions/runs/7993853243     vulna-felickz logger-extension-sanitizer          dynamic/github-code-scanning/codeql
# success    https://github.com/vulna-felickz/go-weak-crypto/actions/runs/7072438824                 vulna-felickz go-weak-crypto                      .github/workflows/codeql.yml
# failure    https://github.com/vulna-felickz/WebGoat-default/actions/runs/6424311141                vulna-felickz WebGoat-default                     dynamic/github-code-scanning/codeql
# success    https://github.com/vulna-felickz/js-postmessage/actions/runs/7284385995                 vulna-felickz js-postmessage                      .github/workflows/codeql.yml
# success    https://github.com/vulna-felickz/python-clear-text-log/actions/runs/8017910177          vulna-felickz python-clear-text-log               dynamic/github-code-scanning/codeql
# success    https://github.com/vulna-felickz/go-xxe/actions/runs/7977001132                         vulna-felickz go-xxe                              dynamic/github-code-scanning/codeql
# success    https://github.com/vulna-felickz/dvcsharp-api/actions/runs/8000424963                   vulna-felickz dvcsharp-api                        .github/workflows/codeql.yml
# failure    https://github.com/vulna-felickz/WebGoat.Net46/actions/runs/8015188622                  vulna-felickz WebGoat.Net46                       .github/workflows/codeql.yml
# null       null                                                                                    vulna-felickz WebGoat-Autobuild                   dynamic/github-code-scanning/codeql
# failure    https://github.com/vulna-felickz/WebGoat-Autobuild/actions/runs/8026262312              vulna-felickz WebGoat-Autobuild                   dynamic/github-code-scanning/codeql
$org = "vulna-felickz"
$csv = "CodeQLWorkflowStatus.csv"
$header = "Conclusion,Workflow_Url,Org,Repo,Workflow_Path"
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
    | %{ "$_,$org,$name,$($workflow.path)" } `
    | Add-Content -Path "./$csv" `
}

Import-Csv -Path "./$csv" | Format-Table