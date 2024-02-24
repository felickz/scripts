# find any CodeQL named runs and get their latest status
# - use the gh cli (easy auth and query apis)
# - search for all repos in an org
# - workflows named "CodeQl" running in an action - EXCLUDE PRs
# - Report if the scans were building successful or not (conclusion)

# Use this script to output a csv file to actions upload: https://github.com/vulna-felickz/.github/edit/main/.github/workflows/codeql-org-report.yml

#results:
# Org           Repo                                Conclusion Workflow_Url
# ---           ----                                ---------- ------------
# vulna-felickz WebGoat.NET                         success    https://github.com/vulna-felickz/WebGoat.NET/actions/runs/8019411601
# vulna-felickz log4shell-vulnerable-app            success    https://github.com/vulna-felickz/log4shell-vulnerable-app/actions/runs/5289516341
# vulna-felickz my-spring-log4j-vuln-sample         null       null
# vulna-felickz FullDotNetWebApp                    success    https://github.com/vulna-felickz/FullDotNetWebApp/actions/runs/7780125962
# vulna-felickz DotNetCoreWebApp                    success    https://github.com/vulna-felickz/DotNetCoreWebApp/actions/runs/7716451772
# vulna-felickz puma-prey                           success    https://github.com/vulna-felickz/puma-prey/actions/runs/7946337933
# vulna-felickz code-scanning-javascript-demo       null       null
# vulna-felickz BenchmarkJava                       null       null
# vulna-felickz babel                               success    https://github.com/vulna-felickz/babel/actions/runs/7954662269
# vulna-felickz Damn-Vulnerable-GraphQL-Application null       null
# vulna-felickz DotNetCoreWebAPI                    success    https://github.com/vulna-felickz/DotNetCoreWebAPI/actions/runs/7967201683
# vulna-felickz WebGoat                             success    https://github.com/vulna-felickz/WebGoat/actions/runs/7952160077
# vulna-felickz railsgoat                           success    https://github.com/vulna-felickz/railsgoat/actions/runs/7967722774
# vulna-felickz VulnerableApp                       success    https://github.com/vulna-felickz/VulnerableApp/actions/runs/7954709690
# vulna-felickz demo-java                           success    https://github.com/vulna-felickz/demo-java/actions/runs/4263592915
# vulna-felickz python-request                      success    https://github.com/vulna-felickz/python-request/actions/runs/4512232580
# vulna-felickz OwaspTop10Examples                  success    https://github.com/vulna-felickz/OwaspTop10Examples/actions/runs/7954645134
# vulna-felickz CodeQL-Hardcoded-DB-Creds-Java      success    https://github.com/vulna-felickz/CodeQL-Hardcoded-DB-Creds-Java/actions/runs/4765934736
# vulna-felickz norma                               failure    https://github.com/vulna-felickz/norma/actions/runs/4712835511
# vulna-felickz vulnerable-express                  success    https://github.com/vulna-felickz/vulnerable-express/actions/runs/5488120897
# vulna-felickz vulnerable-express                  success    https://github.com/vulna-felickz/vulnerable-express/actions/runs/4771427796
# vulna-felickz felickz-juice-shop                  success    https://github.com/vulna-felickz/felickz-juice-shop/actions/runs/7950039676
# vulna-felickz Vulnerability-goapp                 success    https://github.com/vulna-felickz/Vulnerability-goapp/actions/runs/6678031794
# vulna-felickz JavaVulnerableLab                   failure    https://github.com/vulna-felickz/JavaVulnerableLab/actions/runs/5534779512
# vulna-felickz testing-go-function                 success    https://github.com/vulna-felickz/testing-go-function/actions/runs/6785210118
# vulna-felickz ts-jose-jwtdecode                   success    https://github.com/vulna-felickz/ts-jose-jwtdecode/actions/runs/6835036147
# vulna-felickz go-zipslip                          success    https://github.com/vulna-felickz/go-zipslip/actions/runs/6836979722
# vulna-felickz netcore-mvc-razor-xss               success    https://github.com/vulna-felickz/netcore-mvc-razor-xss/actions/runs/7940784369
# vulna-felickz python-flask                        success    https://github.com/vulna-felickz/python-flask/actions/runs/5843840555
# vulna-felickz python-flask                        success    https://github.com/vulna-felickz/python-flask/actions/runs/5196215116
# vulna-felickz dvta                                failure    https://github.com/vulna-felickz/dvta/actions/runs/5895551266
# vulna-felickz orchestration-demo                  success    https://github.com/vulna-felickz/orchestration-demo/actions/runs/6720946958
# vulna-felickz felickz-WebGoat-default             success    https://github.com/vulna-felickz/felickz-WebGoat-default/actions/runs/6902314132
# vulna-felickz felickz-WebGoat-default             failure    https://github.com/vulna-felickz/felickz-WebGoat-default/actions/runs/6176623595
# vulna-felickz logger-extension-sanitizer          success    https://github.com/vulna-felickz/logger-extension-sanitizer/actions/runs/7993853243
# vulna-felickz go-weak-crypto                      success    https://github.com/vulna-felickz/go-weak-crypto/actions/runs/7072438824
# vulna-felickz WebGoat-default                     failure    https://github.com/vulna-felickz/WebGoat-default/actions/runs/6424311141
# vulna-felickz js-postmessage                      success    https://github.com/vulna-felickz/js-postmessage/actions/runs/7284385995
# vulna-felickz python-clear-text-log               success    https://github.com/vulna-felickz/python-clear-text-log/actions/runs/8017910177
# vulna-felickz go-xxe                              success    https://github.com/vulna-felickz/go-xxe/actions/runs/7977001132
# vulna-felickz dvcsharp-api                        success    https://github.com/vulna-felickz/dvcsharp-api/actions/runs/8000424963
# vulna-felickz WebGoat.Net46                       failure    https://github.com/vulna-felickz/WebGoat.Net46/actions/runs/8015188622
# vulna-felickz WebGoat-Autobuild                   null       null
# vulna-felickz WebGoat-Autobuild                   failure    https://github.com/vulna-felickz/WebGoat-Autobuild/actions/runs/8026262312

$org = "vulna-felickz"
$csv = "CodeQLWorkflowStatus.csv"
$header = "Org,Repo,Conclusion,Workflow_Url"
Set-Content -Path "./$csv" -Value $header

gh api /orgs/$org/repos --paginate `
| jq -r '.[] | .name' `
| %{ `
    $name = $_; gh api /repos/$org/$_/actions/workflows --paginate `
    | jq '.workflows[] | select(.name=="CodeQL") | .id' `
    | % { gh api /repos/$org/$name/actions/workflows/$_/runs?exclude_pull_requests=true } `
    | jq -r '.workflow_runs[0] | "\(.conclusion),\(.html_url)"' `
    | %{ "$org,$name,$_" } `
    | Add-Content -Path "./$csv" `
}

Import-Csv -Path "./$csv" | Format-Table