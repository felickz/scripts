#Call GHAzDO API to get the secret scanning alert into $alert variable
$start_line = $alert.physicalLocations[0].region.lineStart
$end_line = $alert.physicalLocations[0].region.lineEnd
$column_start = $alert.physicalLocations[0].region.columnStart
$column_end = $alert.physicalLocations[0].region.columnEnd
$filepath = $alert.physicalLocations[0].filePath

git clone $alert.repositoryUrl
$repositoryName = $alert.repositoryUrl.Split('/')[-1]
cd $repositoryName

# ex output:
# HEAD is now at b9af4f7 Initial commit
git checkout $alert.physicalLocations[0].versionControl.commitHash

$fileContent = Get-Content -Path $filepath
$selectedLines = $fileContent[($start_line-1)..($end_line-1)]
$secretValue = $selectedLines | ForEach-Object { $_.Substring($column_start-1, $column_end-$column_start) }


# ex output:
# Secret value: ghp_<redacted-for-this-comment-only>
Write-Host "Secret value: $secretValue"

#cleanup
Set-Location ..
Remove-Item -Recurse -Force $repositoryName