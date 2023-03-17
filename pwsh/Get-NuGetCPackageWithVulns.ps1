# Query the NuGet.org API for packages with the "native" tag that contain vulnerabilities
# Vulnerabilities in NuGet overview: https://devblogs.microsoft.com/nuget/how-to-scan-nuget-packages-for-security-vulnerabilities/

# Native tag  for C++ packages: https://learn.microsoft.com/en-us/nuget/consume-packages/finding-and-choosing-packages#native-c-packages
# NOTE: also seeing tags "C++" and "C" for these packages
#Make Web Request to GET https://search-sample.nuget.org/query?q=NuGet.Versioning&prerelease=false&semVerLevel=2.0.0
$NuGetQuery = "https://api-v2v3search-0.nuget.org/query?q=Tags:native"
$NuGetQueryResponse = Invoke-WebRequest -Uri $NuGetQuery -Method Get -UseBasicParsing

#Convert JSON to PowerShell Object
$NuGetQueryResponse = $NuGetQueryResponse.Content | ConvertFrom-Json

#Loop through each package in the response
foreach ($NuGetPackage in $NuGetQueryResponse.data)
{
    #Get the package ID
    $NuGetPackageID = $NuGetPackage.id

    #Get the package version
    $NuGetPackageVersion = $NuGetPackage.version

    #Get the package vulnerability URL
    $NuGetPackageVulnURL = $NuGetPackage.vulnerabilitiesUrl

    #Make Web Request to GET https://api.nuget.org/v3/registration3-gz-semver2/nuget.versioning/index.json
    $NuGetVulnQuery = $NuGetPackageVulnURL
    $NuGetVulnQueryResponse = Invoke-WebRequest -Uri $NuGetVulnQuery -Method Get -UseBasicParsing

    #Convert JSON to PowerShell Object
    $NuGetVulnQueryResponse = $NuGetVulnQueryResponse.Content | ConvertFrom-Json

    #Loop through each vulnerability in the response
    foreach ($NuGetVuln in $NuGetVulnQueryResponse.data)
    {
        #Get the vulnerability ID
        $NuGetVulnID = $NuGetVuln.id

        #Get the vulnerability severity
        $NuGetVulnSeverity = $NuGetVuln.severity

        #Get the vulnerability description
        $NuGetVulnDescription = $NuGetVuln.description

        #Get the vulnerability advisory URL
        $NuGetVulnAdvisoryURL = $NuGetVuln.advisoryUrl

        #Write the results to the console
        Write-Host "Package ID: $NuGetPackageID"
        Write-Host "Package Version: $NuGetPackageVersion"
        Write-Host "Vulnerability ID: $NuGetVulnID"
        Write-Host "Vulnerability Severity: $NuGetVulnSeverity"
        Write-Host "Vulnerability Description: $NuGetVulnDescription"
        Write-Host "Vulnerability Advisory URL: $NuGetVulnAdvisoryURL"
        Write-Host ""
    }
}


<#* To query for the next set of catalog items to process, the client should:

1. Fetch the recorded cursor value from a local store.
2. Download and deserialize the catalog index.
3. Find all catalog pages with a commit timestamp greater than the cursor.
4. Declare an empty list of catalog items to process.
5. For each catalog page matched in step 3:
a. Download and deserialized the catalog page.
b. Find all catalog items with a commit timestamp greater than the cursor.
c. Add all matching catalog items to the list declared in step 4.
6. Sort the catalog item list by commit timestamp.
7. Process each catalog item in sequence:
a. Download and deserialize the catalog item.
b. React appropriately to the catalog item's type.
c. Process the catalog item document in a client-specific fashion.
8. Record the last catalog item's commit timestamp as the new cursor value.
#>


