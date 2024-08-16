#Run tests for dotnet and nuget cli tools to check if they are able to authenticate with the nuget feed

$output = dotnet nuget list source
$lines = $output -split "`n"

# Initialize an empty array to store the sources
$sources = @()

# Loop through each line and extract the name and URL
for ($i = 0; $i -lt $lines.Length; $i++) {
    if ($lines[$i] -match '^\s*\d+\.\s*(.+?)\s+\[Enabled\]$') {
        $name = $matches[1]
        $url = $lines[$i + 1].Trim()
        $sources += [PSCustomObject]@{ Name = $name; URL = $url }
    }
}


# make it totally random like new guid - does not matter we just want to test connectivity
$searchFor = [System.Guid]::NewGuid().ToString()

# Loop through each source and print the name and URL
foreach ($source in $sources) {
    Write-Host "➕ Name: $($source.Name) / URL: $($source.URL)"

    try {
        $startTime = [System.Diagnostics.Stopwatch]::StartNew()

        $search =  dotnet package search $searchFor --source $source.URL --take 1
        # Write-Host "Search: $search"

        $elapsedTime = $startTime.ElapsedMilliseconds

        # if the $search response contains "error:" then its an error
        if ($search -match "error:") {
            Write-Host "❌ Error ($($elapsedTime)ms): $search"
        } else {
            Write-Host "🟢 Success ($($elapsedTime)ms)"
        }

    }
    catch {
        Write-Host "🕵️ $_.Exception.Message"
    }



}



$output =  nuget sources list -Verbosity detailed

$lines = $output -split "`n"

# Initialize an empty array to store the sources
$sources = @()

# Loop through each line and extract the name and URL
for ($i = 0; $i -lt $lines.Length; $i++) {
    if ($lines[$i] -match '^\s*\d+\.\s*(.+?)\s+\[Enabled\]$') {
        $name = $matches[1]
        $url = $lines[$i + 1].Trim()
        $sources += [PSCustomObject]@{ Name = $name; URL = $url }
    }
}

$searchFor = [System.Guid]::NewGuid().ToString()
# Loop through each source and print the name and URL
foreach ($source in $sources) {
    Write-Host "➕ Name: $($source.Name) / URL: $($source.URL)"

    # This list cannot be paged / filtered to one package
    #    $packages = nuget list -Source $($source.Name)

    try {

        #errors easier to catch in stderror
        $process = Start-Process nuget -ArgumentList "search", $searchFor, "-Source", $($source.Name), "-NonInteractive" -NoNewWindow -RedirectStandardOutput "output.txt" -RedirectStandardError "error.txt" -PassThru
        $process.WaitForExit()

        $elapsedTime = $startTime.ElapsedMilliseconds


        $output = Get-Content "output.txt"
        $err = Get-Content "error.txt"

        if ($process.ExitCode -ne 0) {
            Write-Host "❌ Error ($($elapsedTime)ms): $err"
        } else {
            Write-Host "🟢 Success ($($elapsedTime)ms)"
        }
    }
    catch {
        Write-Host "🕵️ $_.Exception.Message"
    }

}

