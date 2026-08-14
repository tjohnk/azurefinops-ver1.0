<#
.SYNOPSIS
Runs orphan-rules.kql against the ADX database and appends the results into
OrphanResourceFact.

.DESCRIPTION
Before this script existed, orphan-rules.kql was documentation only — nothing in the
repo ever executed it. finops/orphan-detection/DEPLOYMENT.md said to "run orphan-rules.kql
after inventory and cost ingestion" and "materialize the output into OrphanResourceFact"
as manual steps. This automates both: it reads the KQL file, wraps it in a
`.set-or-append OrphanResourceFact <|` management command, and submits it to the ADX
cluster's management endpoint using the caller's own Azure AD token (Workload Identity
Federation in the pipeline — no separate credential needed).

Run this AFTER the day's ResourceInventory and CostAnalysisFact ingestion has completed —
the rule joins against both tables, so running it first would silently produce an empty or
stale result rather than an error.

.PARAMETER TenantName
Tenant folder name under variables/environments/ — supplies the ADX cluster URL and
database from that tenant's config.json (adx.clusterUrl, adx.database).

.EXAMPLE
./Invoke-OrphanDetection.ps1 -TenantName "default" -ConfigPath "variables"
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
        throw "adx.clusterUrl is not configured for tenant '$TenantName' — set it in variables/environments/$TenantName/config.json"
    }

    $kqlPath = Join-Path (Split-Path $PSScriptRoot -Parent) "finops/orphan-detection/orphan-rules.kql"
    if (-not (Test-Path $kqlPath)) {
        throw "orphan-rules.kql not found at $kqlPath"
    }
    $rule = Get-Content $kqlPath -Raw

    Write-Log "Running orphan detection against $clusterUrl / $database"
    $response = Invoke-AdxSetOrAppend -ClusterUrl $clusterUrl -Database $database `
        -TargetTable "OrphanResourceFact" -Query $rule

    Write-Log "Orphan detection completed successfully" -Level "SUCCESS"
    Write-Log ("Result: " + ($response | ConvertTo-Json -Depth 3 -Compress))
}
catch {
    Write-Log "FATAL: Orphan detection failed: $_" -Level "ERROR"
    exit 1
}
