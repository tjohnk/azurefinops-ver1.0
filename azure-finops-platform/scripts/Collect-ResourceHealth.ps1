<#
.SYNOPSIS
Collects Azure Resource Health status for every resource in the current inventory and
writes it as ADX-ready JSON matching the ResourceHealthFact schema.

.DESCRIPTION
Before this script existed, ResourceHealthFact had a schema and UsageActivityController's
/health endpoint queried it, but nothing populated it — this was a genuinely uncollected
data source, not a transform-of-existing-data gap like Usage & Activity's other tables.

Resource Health has no bulk/Resource-Graph-style query — it's one API call per resource —
so this reads the same resource-inventory.json the main collector already produced rather
than re-discovering resources, and is deliberately capped (see -MaxResources) since calling
this per-resource across a large estate is the slow part of the whole pipeline.

.PARAMETER MaxResources
Caps how many resources get a health check per run, prioritizing whatever the inventory
lists first. Defaults to 2000. Raise this once you've measured how long a full pass takes
against your estate's actual size — this default is a starting point, not a tuned value.

.EXAMPLE
./Collect-ResourceHealth.ps1 -TenantName "default" -ConfigPath "variables"
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$TenantName,
    [Parameter(Mandatory = $false)][string]$ConfigPath = "./variables",
    [Parameter(Mandatory = $false)][int]$MaxResources = 2000
)

$ErrorActionPreference = "Stop"

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $color = @{INFO="Cyan"; WARN="Yellow"; ERROR="Red"; SUCCESS="Green"}[$Level] ?? "Cyan"
    Write-Host "[$timestamp] [$Level] $Message" -ForegroundColor $color
}

try {
    $root = Split-Path $PSScriptRoot -Parent
    Import-Module "$PSScriptRoot/ConfigHelper.psm1" -Force
    Import-Module Az.Accounts -ErrorAction Stop
    Import-TenantConfig -TenantName $TenantName -ConfigPath $ConfigPath | Out-Null

    $inventoryPath = Join-Path $root "output/resource-inventory.json"
    if (-not (Test-Path $inventoryPath)) {
        throw "resource-inventory.json not found at $inventoryPath — run the main collector (Run-Dashboard-Assessment.ps1) first."
    }
    $resources = @(Get-Content $inventoryPath -Raw | ConvertFrom-Json) | Select-Object -First $MaxResources
    Write-Log "Checking health for $($resources.Count) resource(s)"

    $healthRows = [System.Collections.Generic.List[object]]::new()
    $errors = 0

    # Resource Health is exposed as a provider under each resource, read via the generic
    # REST path rather than a dedicated Az module cmdlet (Az.ResourceHealth's cmdlets vary
    # in availability across Az versions) — this works with just Az.Accounts.
    foreach ($r in $resources) {
        try {
            $healthUri = "https://management.azure.com$($r.resourceId)/providers/Microsoft.ResourceHealth/availabilityStatuses/current?api-version=2022-10-01"
            $token = (Get-AzAccessToken -ResourceUrl "https://management.azure.com/").Token
            $response = Invoke-RestMethod -Uri $healthUri -Headers @{ Authorization = "Bearer $token" } -Method Get -ErrorAction Stop

            $healthRows.Add([pscustomobject]@{
                TimestampUtc     = (Get-Date).ToUniversalTime().ToString("o")
                SubscriptionId   = $r.subscriptionId
                Environment      = if ($r.PSObject.Properties.Name -contains 'environment') { $r.environment } else { "Unclassified" }
                ResourceId       = $r.resourceId
                ResourceName     = $r.resourceName
                HealthStatus     = $response.properties.availabilityState
                AvailabilityState= $response.properties.availabilityState
                Reason           = $response.properties.summary
            })
        }
        catch {
            # Resource Health isn't available for every resource type — a 404 here is
            # normal and expected for many resources, not a failure worth logging loudly.
            $errors++
        }
    }

    Write-Log "Collected health for $($healthRows.Count) resource(s), $errors unavailable/errored"

    $outDir = Join-Path $root "output/adx"
    New-Item -ItemType Directory -Force -Path $outDir | Out-Null
    $outPath = Join-Path $outDir "adx-resource-health.json"
    $healthRows | ConvertTo-Json -Depth 10 | Set-Content -Path $outPath -Encoding utf8

    Write-Log "Wrote $($healthRows.Count) health row(s) to $outPath" -Level "SUCCESS"
}
catch {
    Write-Log "FATAL: Resource health collection failed: $_" -Level "ERROR"
    exit 1
}
