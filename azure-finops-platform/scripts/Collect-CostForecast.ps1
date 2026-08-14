<#
.SYNOPSIS
Runs forecast-rule.kql against ADX and appends the result into CostForecastFact.

.DESCRIPTION
See finops/cost-analysis/forecast-rule.kql for the methodology and its limitations.
Run this after the day's CostAnalysisFact ingestion — it needs at least 30 days of cost
history to produce a meaningful trend; with less history the growth-rate comparison
degrades gracefully (falls back to a flat projection) rather than erroring, but won't be
useful until real history accumulates.

.EXAMPLE
./Collect-CostForecast.ps1 -TenantName "default" -ConfigPath "variables"
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

    $kqlPath = Join-Path (Split-Path $PSScriptRoot -Parent) "finops/cost-analysis/forecast-rule.kql"
    if (-not (Test-Path $kqlPath)) { throw "forecast-rule.kql not found at $kqlPath" }
    $rule = Get-Content $kqlPath -Raw

    Write-Log "Running cost forecast against $clusterUrl / $database"
    $response = Invoke-AdxSetOrAppend -ClusterUrl $clusterUrl -Database $database `
        -TargetTable "CostForecastFact" -Query $rule

    Write-Log "Forecast completed successfully" -Level "SUCCESS"
    Write-Log ("Result: " + ($response | ConvertTo-Json -Depth 3 -Compress))
}
catch {
    Write-Log "FATAL: Cost forecast failed: $_" -Level "ERROR"
    exit 1
}
