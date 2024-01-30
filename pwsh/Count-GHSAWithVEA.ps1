# There is no vulnerable function info available in GraphQL API: https://docs.github.com/en/graphql/reference/objects#securityadvisory
# REST API : https://docs.github.com/en/rest/security-advisories/global-advisories?apiVersion=2022-11-28#get-a-global-security-advisory
# ex: https://github.com/github/advisory-database/blob/3a41004141f4cb3c5c2c2636999772dcea8348ae/advisories/github-reviewed/2022/10/GHSA-w596-4wvx-j9j6/GHSA-w596-4wvx-j9j6.json#L17-L28

# Code Search Syntax: https://docs.github.com/en/search-github/github-code-search/understanding-github-code-search-syntax
$search="repo:github/advisory-database `"affected_functions`""

#TODO: These work great in UI but struggle in this script
#$search="repo:github/advisory-database path:/^advisories\/github-reviewed\// `"affected_functions`""
#$search="repo:github/advisory-database path:/^advisories\/github-reviewed\// affected_functions"

# build list of all ecosystems definded by OSV via the OSSF package ecosystem list: https://ossf.github.io/osv-schema/#affectedpackage-field
$ecosystems = @(
"AlmaLinux",   #AlmaLinux package ecosystem; the name is the name of the source package. The ecosystem string might optionally have a :<RELEASE> suffix to scope the package to a particular AlmaLinux release. <RELEASE> is a numeric version.
"Alpine",   #The Alpine package ecosystem; the name is the name of the source package. The ecosystem string must have a :v<RELEASE-NUMBER> suffix to scope the package to a particular Alpine release branch (the v prefix is required). E.g. v3.16.
"Android",   #The Android ecosystem. Android organizes code using repo tool, which manages multiple git projects under one or more remote git servers, where each project is identified by its name in repo configuration (e.g. platform/frameworks/base). The name field should contain the name of that affected git project/submodule. One exception is when the project contains the Linux kernel source code, in which case name field will be :linux_kernel:, followed by an optional SoC vendor name e.g. :linux_kernel:Qualcomm. The list of recognized SoC vendors is listed in the Appendix
"Bioconductor",   #The biological R package ecosystem. The name is an R package name.
"Bitnami",   #Bitnami package ecosystem; the name is the name of the affected component.
"ConanCenter",   #The ConanCenter ecosystem for C and C++; the name field is a Conan package name.
"CRAN",   #The R package ecosystem. The name is an R package name.
"crates.io",   #The crates.io ecosystem for Rust; the name field is a crate name.
"Debian",   #The Debian package ecosystem; the name is the name of the source package. The ecosystem string might optionally have a :<RELEASE> suffix to scope the package to a particular Debian release. <RELEASE> is a numeric version specified in the Debian distro-info-data. For example, the ecosystem string “Debian:7” refers to the Debian 7 (wheezy) release.
"GHC",   #The Haskell compiler ecosystem. The name field is the name of a component of the GHC compiler ecosystem (e.g., compiler, GHCI, RTS).
"GitHub Actions",   #The GitHub Actions ecosystem; the name field is the action’s repository name with owner e.g. {owner}/{repo}.
"Go",   #The Go ecosystem; the name field is a Go module path.
"Hackage",   #The Haskell package ecosystem. The name field is a Haskell package name as published on Hackage.
"Hex",   #The package manager for the Erlang ecosystem; the name is a Hex package name.
"Linux",   #The Linux kernel. The only supported name is Kernel.
"Maven",   #The Maven Java package ecosystem. The name field is a Maven package name.
"npm",   #The NPM ecosystem; the name field is an NPM package name.
"NuGet",   #The NuGet package ecosystem. The name field is a NuGet package name.
"OSS-Fuzz",   #For reports from the OSS-Fuzz project that have no more appropriate ecosystem; the name field is the name assigned by the OSS-Fuzz project, as recorded in the submitted fuzzing configuration.
"Packagist",   #The PHP package manager ecosystem; the name is a package name.
"Photon OS",   #The Photon OS package ecosystem; the name is the name of the RPM package. The ecosystem string must have a :<RELEASE-NUMBER> suffix to scope the package to a particular Photon OS release. Eg Photon OS:3.0.
"Pub",   #The package manager for the Dart ecosystem; the name field is a Dart package name.
"PyPI",   #the Python PyPI ecosystem; the name field is a normalized PyPI package name.
"Rocky Linux",   #The Rocky Linux package ecosystem; the name is the name of the source package. The ecosystem string might optionally have a :<RELEASE> suffix to scope the package to a particular Rocky Linux release. <RELEASE> is a numeric version.
"RubyGems",   #The RubyGems ecosystem; the name field is a gem name.
"SwiftURL",   #The Swift Package Manager ecosystem. The name is a Git URL to the source of the package. Versions are Git tags that comform to SemVer 2.0.
"Ubuntu"   #The Ubuntu package ecosystem; the name field is the name of the source package. The ecosystem string has a :<RELEASE> suffix to scope the package to a particular Ubuntu release. <RELEASE> is a numeric (“YY.MM”) version as specified in Ubuntu Releases, with a mandatory :LTS suffix if the release is marked as LTS. The release version may also be prefixed with :Pro: to denote Ubuntu Pro (aka Expanded Security Maintenance (ESM)) updates. For example, the ecosystem string “Ubuntu:22.04:LTS” refers to Ubuntu 22.04 LTS (jammy), while “Ubuntu:Pro:18.04:LTS” refers to fixes that landed in Ubuntu 18.04 LTS (bionic) under Ubuntu Pro/ESM.
)

 # #Loop over each ecosystem and build a search string
$results = foreach ($ecosystem in $ecosystems) {    
    $ecosystemSearch = $search + " AND `"\`"ecosystem\`": \`"$ecosystem\`"`""

    #URI encode the search string
    $ecosystemSearch = [System.Uri]::EscapeDataString($ecosystemSearch) # Most similar to the JS encodeURIComponent() function
    #$search = [System.Web.HttpUtility]::UrlEncode($search) # Also encodes spaces as + instead of %20
        
    #use the gh cli to call the search api https://docs.github.com/en/rest/search/search?apiVersion=2022-11-28
    $apiResponse = gh api search/code?q=$ecosystemSearch | ConvertFrom-Json    

    #Create $advisoryEcosystem variable to use a map to transform the ecosystem string to match the advisory database, ex "PyPi" to "pip", "Pub" to "pub"
    $advisoryMap = @{
        "GitHub Actions" = "actions"
        "Go" = "go"
        "crates.io" = "rust"
        "Hex" = "erlang"
        "Maven" = "maven"
        "npm" = "npm"
        "NuGet" = "nuget"
        "Packagist" = "composer" #??
        "Pub" = "pub"
        "PyPI" = "pip"
        "RubyGems" = "rubygems"
    }

    $advisoryEcosystem = $advisoryMap[$ecosystem] ?? "other"
    # Would much rather use GraphQL here, but ecosystem is not exposed in the advisory database Objects https://docs.github.com/en/graphql/reference/objects#securityadvisory
    $totalAdvisories = $advisoryEcosystem -eq "other" ? "x" : (gh api -X GET /advisories -F ecosystem=$advisoryEcosystem -F per_page=100 --paginate | ConvertFrom-Json).Count 

    # Create a custom object with the ecosystem and count
    New-Object PSObject -Property @{
        Ecosystem = $ecosystem
        Count = $apiResponse.total_count
        TotalAdvisories = $totalAdvisories
    }

    #Write-Host $ecosystemSearch
}

Write-Host "Advisory DB VEA Inventory  $($(Get-Date -AsUTC).ToString('u'))"
# Output the results as a table
$results | Sort-Object -Property Count -Descending | ConvertTo-Markdown


#https://www.powershellgallery.com/packages/PSMarkdown/1.1/Content/ConvertTo-Markdown.ps1
Function ConvertTo-Markdown {
    [CmdletBinding()]
    [OutputType([string])]
    Param (
        [Parameter(
            Mandatory = $true,
            Position = 0,
            ValueFromPipeline = $true
        )]
        [PSObject[]]$InputObject
    )

    Begin {
        $items = @()
        $columns = @{}
    }

    Process {
        ForEach($item in $InputObject) {
            $items += $item

            $item.PSObject.Properties | %{
                if($_.Value -ne $null){
                    if(-not $columns.ContainsKey($_.Name) -or $columns[$_.Name] -lt $_.Value.ToString().Length) {
                        $columns[$_.Name] = $_.Value.ToString().Length
                    }
                }
            }
        }
    }

    End {
        ForEach($key in $($columns.Keys)) {
            $columns[$key] = [Math]::Max($columns[$key], $key.Length)
        }

        $header = @()
        ForEach($key in $columns.Keys) {
            $header += ('{0,-' + $columns[$key] + '}') -f $key
        }
        $header -join ' | '

        $separator = @()
        ForEach($key in $columns.Keys) {
            $separator += '-' * $columns[$key]
        }
        $separator -join ' | '

        ForEach($item in $items) {
            $values = @()
            ForEach($key in $columns.Keys) {
                $values += ('{0,-' + $columns[$key] + '}') -f $item.($key)
            }
            $values -join ' | '
        }
    }
}


