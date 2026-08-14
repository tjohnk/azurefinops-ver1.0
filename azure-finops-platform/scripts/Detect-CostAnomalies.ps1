<#
.SYNOPSIS
Runs anomaly-rule.kql against ADX and appends the result into CostAnomalyFact.

.DESCRIPTION
See finops/cost-analysis/anomaly-rule.kql for the methodology and its limitations. Run
this after the day's CostAnalysisFact ingestion. Per automation-map.md this is intended to
run hourly (cost anomaly detection is listed there under "Hourly") — the daily pipeline
default in pipeline/azure-adoption-no-csv.yml runs it once a day; trigger the pipeline
manually with a shorter cadence if you want the hourly behavior that document describes.

.EXAMPLE
./Detect-CostAnomalies.ps1 -TenantName "default" -ConfigPath "variables"
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$TenantName,
    [Parameter(Mandatory = $false)][string]$ConfigPath = "./variables"
)

$ErrorActionPreference = "Stop"

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $color = @{INFO="Cyan"; WARN="Yellow"; ERROR="Red"; SUCCESS="Green"}[$Level] ?? "Cyan"
    Write-Host "[$timestamp] [$Level] $Message" -ForegroundColor $color
}

try {
    Import-Module "$PSScriptRoot/ConfigHelper.psm1" -Force
    Import-Module "$PSScriptRoot/AdxHelper.psm1" -Force
    Import-Module Az.Accounts -ErrorAction Stop

    $config = Import-TenantConfig -TenantName $TenantName -ConfigPath $ConfigPath
    $clusterUrl = $config.adx.clusterUrl
    $database = $config.adx.database

    if ([string]::IsNullOrWhiteSpace($clusterUrl) -or $clusterUrl -like "*REPLACE*") {
        throw "adx.clusterUrl is not configured for tenant '$TenantName'"
    }

    $kqlPath = Join-Path (Split-Path $PSScriptRoot -Parent) "finops/cost-analysis/anomaly-rule.kql"
    if (-not (Test-Path $kqlPath)) { throw "anomaly-rule.kql not found at $kqlPath" }
    $rule = Get-Content $kqlPath -Raw

    Write-Log "Running cost anomaly detection against $clusterUrl / $database"
    $response = Invoke-AdxSetOrAppend -ClusterUrl $clusterUrl -Database $database `
        -TargetTable "CostAnomalyFact" -Query $rule

    Write-Log "Anomaly detection completed successfully" -Level "SUCCESS"
    Write-Log ("Result: " + ($response | ConvertTo-Json -Depth 3 -Compress))
}
catch {
    Write-Log "FATAL: Cost anomaly detection failed: $_" -Level "ERROR"
    exit 1
}
