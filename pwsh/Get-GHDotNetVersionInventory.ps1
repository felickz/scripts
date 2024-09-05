#TODO move to a manifest like choco package.config
if (Get-Module -ListAvailable -Name FormatMarkdownTable -ErrorAction SilentlyContinue) {
    #Write-Output "FormatMarkdownTable module is installed"
  }
  else {
    # Handle `Untrusted repository` prompt
    Set-PSRepository PSGallery -InstallationPolicy Trusted
    #directly to output here before module loaded to support Write-ActionInfo
    Write-Output "FormatMarkdownTable module is not installed.  Installing from Gallery..."
    Install-Module -Name FormatMarkdownTable
  }

#https://docs.github.com/en/rest/search/search?apiVersion=2022-11-28#search-code
#$orgs = "octodemo" #Cannot search multiple orgs - condition is unsatisfiable
#$excludeRepos = "github/entitlements"
#$query =  [System.Uri]::EscapeDataString("$($orgs|%{'org:' + $_ + ' '} ) $($excludeRepos|%{'-repo:' + $_ + ' '} ) path:**/*.csproj `"<TargetFramework`"")
#somethine weird with escaping here... just testing:
$query = "org:octodemo+language:XML+%3CTargetFramework"
Write-Host "https://github.com/search?q=$query"

# #gh api "/search/issues?q=$query&type=pullrequests" --paginate  >> resp.json
$code = gh api "/search/code?q=$query" #--paginate

$json = $code | ConvertFrom-Json

Write-Host $json

#How can we get the code, need to use the raw url and grep?
        # $parsedIssues = $issues.items | Select-Object @{Name='nwo';Expression={$_.html_url.split("/")[3]+'/'+$_.html_url.split("/")[4]}},  @{Name='type';Expression={$null -eq $_.pull_request ? "Issue" : "PR"}},  @{Name='issue';Expression={"[#$($_.number) - $($_.title)]($($_.html_url))"}}, @{Name='labels';Expression={($_.labels | ForEach-Object { "[$($_.name)]($($_.url.Replace('api.github.com/repos', 'github.com')))" }) -join ', '}}

        # #parse out the org/repo from the html_url https://github.com/actions/starter-workflows/pull/2312

        # $PRs = $parsedIssues | Where-Object { $_.type -match "PR" } | Select-Object
        # if($PRs.Count -gt 0) {
        # Write-Host "## $(($PRs | Measure-Object).Count) Pull Requests ([query](https://github.com/search?q=$query&type=pullrequests))"
        # $PRs | Format-MarkdownTableTableStyle -ShowMarkdown -DoNotCopyToClipboard -HideStandardOutput
        # }
