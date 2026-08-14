[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)][string]$StorageAccount,
    [Parameter(Mandatory=$false)][string]$Container,
    [Parameter(Mandatory=$false)][string]$SourceFolder,
    [Parameter(Mandatory=$false)][string]$Prefix="raw",
    [Parameter(Mandatory=$false)][string]$TenantName,
    [Parameter(Mandatory=$false)][string]$ConfigPath="./variables"
)

$ErrorActionPreference="Stop"

# Import modules
Import-Module Az.Storage -ErrorAction Stop

# Import configuration helper
$root = Split-Path $PSScriptRoot -Parent
if (Test-Path "$PSScriptRoot/ConfigHelper.psm1") {
    Import-Module "$PSScriptRoot/ConfigHelper.psm1" -Force
}

# Logging function
function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $color = @{INFO="Cyan"; WARN="Yellow"; ERROR="Red"; SUCCESS="Green"}[$Level] ?? "Cyan"
    Write-Host "[$timestamp] [$Level] $Message" -ForegroundColor $color
}

# Validation function
function Assert-Parameter {
    param([string]$Value, [string]$Name)
    if ([string]::IsNullOrWhiteSpace($Value)) {
        throw "Required parameter missing: $Name"
    }
}

try {
    Write-Log "Starting JSON upload to Azure Storage"

    # If tenant name provided, load from config; otherwise use explicit parameters
    if (-not [string]::IsNullOrWhiteSpace($TenantName)) {
        Write-Log "Loading storage config from tenant: $TenantName"
        $config = Import-TenantConfig -TenantName $TenantName -ConfigPath $ConfigPath
        $StorageAccount = $config.storage.accountName
        $Container = $config.storage.rawContainer
        $SourceFolder = if ($SourceFolder) { $SourceFolder } else { "$root/output" }
        $Prefix = "raw/$($config.collection.defaultMode)"

        Write-Log "Resolved from config - Storage: $StorageAccount, Container: $Container, Prefix: $Prefix"
    }
    else {
        # Validate explicit parameters
        Assert-Parameter $StorageAccount "StorageAccount"
        Assert-Parameter $Container "Container"
        Assert-Parameter $SourceFolder "SourceFolder"
    }

    # Verify source folder exists
    if (-not (Test-Path $SourceFolder -PathType Container)) {
        throw "Source folder not found: $SourceFolder"
    }

    Write-Log "Source folder: $SourceFolder"
    Write-Log "Target: $StorageAccount/$Container"
    Write-Log "Prefix: $Prefix"

    # Create storage context using managed identity
    Write-Log "Creating Azure Storage context using managed identity..."
    $ctx = New-AzStorageContext -StorageAccountName $StorageAccount -UseConnectedAccount -ErrorAction Stop
    Write-Log "Storage context created successfully"

    # Get files to upload
    $files = Get-ChildItem $SourceFolder -Filter *.json -File -ErrorAction Stop

    if ($files.Count -eq 0) {
        Write-Log "WARNING: No JSON files found in $SourceFolder" -Level "WARN"
        exit 0
    }

    Write-Log "Found $($files.Count) JSON files to upload"

    # Upload files with error handling
    $successCount = 0
    $failCount = 0

    foreach ($file in $files) {
        try {
            $blobName = "$Prefix/$($file.Name)"
            Write-Log "Uploading: $($file.Name) -> $blobName"

            Set-AzStorageBlobContent `
                -File $file.FullName `
                -Container $Container `
                -Blob $blobName `
                -Context $ctx `
                -Force `
                -ErrorAction Stop | Out-Null

            $successCount++
            Write-Log "Uploaded successfully: $($file.Name)"
        }
        catch {
            $failCount++
            Write-Log "FAILED to upload $($file.Name): $_" -Level "ERROR"
        }
    }

    # Summary
    Write-Log "=== UPLOAD SUMMARY ===" -Level "INFO"
    Write-Log "Total files: $($files.Count) | Success: $successCount | Failed: $failCount"

    if ($failCount -gt 0) {
        throw "Upload completed with $failCount errors"
    }

    Write-Log "JSON landed in Azure Storage." -Level "SUCCESS"
    Write-Host "JSON landed in Azure Storage." -ForegroundColor Green
}
catch {
    Write-Log "FATAL ERROR: $_" -Level "ERROR"
    exit 1
}
