param (
    [Parameter(Mandatory=$true)]
    [string]$SarifFilePath,

    [Parameter(Mandatory=$false)]
    [switch]$ShowExtractionWarnings = $false,

    [Parameter(Mandatory=$false)]
    [switch]$ShowAllWarnings = $false
)

function Get-SarifFileInfo {
    param (
        [Parameter(Mandatory=$true)]
        [string]$FilePath
    )

    try {
        # Read and parse the SARIF file
        $sarifContent = Get-Content -Path $FilePath -Raw | ConvertFrom-Json        # Initialize arrays for detected and extracted files
        $detectedFiles = @()
        $extractedFiles = @()
        $extractionErrors = @()
        $extractionWarnings = @()

        # Get all artifacts (detected files)
        if ($sarifContent.runs[0].artifacts) {
            foreach ($artifact in $sarifContent.runs[0].artifacts) {
                if ($artifact.location.uri) {
                    $detectedFiles += $artifact.location.uri
                }
            }
        }

        # Find extraction notifications
        if ($sarifContent.runs[0].invocations[0].toolExecutionNotifications) {
            $notifications = $sarifContent.runs[0].invocations[0].toolExecutionNotifications

            # Find successfully extracted files
            $successNotifications = $notifications | Where-Object {
                $_.message.text -eq "File successfully extracted." -or
                $_.level -eq "none" -and $_.descriptor.id -like "*successfully-extracted-files*"
            }

            foreach ($notification in $successNotifications) {
                if ($notification.locations -and $notification.locations[0].physicalLocation.artifactLocation.uri) {
                    $extractedFiles += $notification.locations[0].physicalLocation.artifactLocation.uri
                }            }

            # Find extraction errors
            $errorNotifications = $notifications | Where-Object {
                $_.message.text -match "Extraction failed" -or
                $_.message.text -match "cannot open source file"
            }

            foreach ($notification in $errorNotifications) {
                if ($notification.locations -and $notification.locations[0].physicalLocation.artifactLocation.uri) {
                    $uri = $notification.locations[0].physicalLocation.artifactLocation.uri
                    $errorText = $notification.message.text -replace "Extraction failed in .+? with warning ", ""
                    $extractionErrors += [PSCustomObject]@{
                        Uri = $uri
                        Error = $errorText
                    }
                }
            }            # Find extraction warnings/diagnostics
            $warningNotifications = $notifications | Where-Object {
                $_.descriptor.id -like "*diagnostics/extraction-warnings"
            }

            foreach ($notification in $warningNotifications) {
                if ($notification.locations -and $notification.locations[0].physicalLocation.artifactLocation.uri) {
                    $uri = $notification.locations[0].physicalLocation.artifactLocation.uri
                    $warningText = $notification.message.text
                    $extractionWarnings += [PSCustomObject]@{
                        Uri = $uri
                        Warning = $warningText
                    }
                }            }
        }

        # Return the results
        return [PSCustomObject]@{
            DetectedFiles = $detectedFiles | Sort-Object -Unique
            ExtractedFiles = $extractedFiles | Sort-Object -Unique
            ExtractionErrors = $extractionErrors
            ExtractionWarnings = $extractionWarnings
        }
    }
    catch {
        Write-Error "Failed to parse SARIF file: $_"
        return $null
    }
}

# Main execution
$fileInfo = Get-SarifFileInfo -FilePath $SarifFilePath

if ($fileInfo) {
    # Display detected files
    Write-Host "`nDetected Files (${($fileInfo.DetectedFiles.Count)}):" -ForegroundColor Blue
    foreach ($file in $fileInfo.DetectedFiles) {
        Write-Host "  $file"
    }

    # Display extracted files
    Write-Host "`nSuccessfully Extracted Files (${($fileInfo.ExtractedFiles.Count)}):" -ForegroundColor Green
    foreach ($file in $fileInfo.ExtractedFiles) {
        Write-Host "  $file" -ForegroundColor Green
    }

    # Display files with extraction errors
    $failedFiles = $fileInfo.DetectedFiles | Where-Object { $_ -notin $fileInfo.ExtractedFiles }
    Write-Host "`nFiles with Extraction Issues (${($failedFiles.Count)}):" -ForegroundColor Red
    foreach ($file in $failedFiles) {
        Write-Host "  $file" -ForegroundColor Red

        # Show errors for this file
        $errors = $fileInfo.ExtractionErrors | Where-Object { $_.Uri -eq $file }
        foreach ($err in $errors) {
            Write-Host "    - $($err.Error)" -ForegroundColor Yellow
        }
    }

    # Display extraction ratio
    $extractionRatio = $fileInfo.ExtractedFiles.Count / [Math]::Max(1, $fileInfo.DetectedFiles.Count) * 100
    Write-Host "`nExtraction Summary:" -ForegroundColor Magenta
    Write-Host "  Total files detected: $($fileInfo.DetectedFiles.Count)" -ForegroundColor White
    Write-Host "  Total files successfully extracted: $($fileInfo.ExtractedFiles.Count)" -ForegroundColor White
    Write-Host "  Extraction success rate: $([Math]::Round($extractionRatio, 2))%" -ForegroundColor $(if ($extractionRatio -gt 90) { "Green" } elseif ($extractionRatio -gt 50) { "Yellow" } else { "Red" })    # Display extraction warnings if requested
    if ($ShowExtractionWarnings -and $fileInfo.ExtractionWarnings.Count -gt 0) {
        Write-Host "`nExtraction Warnings for Files with Issues:" -ForegroundColor Red
        $failedFiles = $fileInfo.DetectedFiles | Where-Object { $_ -notin $fileInfo.ExtractedFiles }
        foreach ($file in $failedFiles) {
            $warnings = $fileInfo.ExtractionWarnings | Where-Object { $_.Uri -eq $file }
            if ($warnings.Count -gt 0) {
                Write-Host "  $file" -ForegroundColor Red
                foreach ($warning in $warnings) {
                    Write-Host "    - $($warning.Warning)" -ForegroundColor Yellow
                }
            }
        }
    }

    # Display all warnings if requested
    if ($ShowAllWarnings -and $fileInfo.ExtractionWarnings.Count -gt 0) {
        Write-Host "`nAll Extraction Warnings:" -ForegroundColor Yellow
        foreach ($warning in $fileInfo.ExtractionWarnings) {
            Write-Host "  $($warning.Uri)" -ForegroundColor White
            Write-Host "    - $($warning.Warning)" -ForegroundColor Yellow
        }
    }
}
