<#
.SYNOPSIS
Collects recent Azure DevOps pipeline run history and writes it as ADX-ready JSON
matching the DeploymentActivityFact schema.

.DESCRIPTION
Before this script existed, DeploymentActivityFact had a schema and
UsageActivityController's /deployments endpoint queried it, but there was no collection
code for it at all — it's not derivable from any Azure Resource Manager data, since
deployment history lives in Azure DevOps, not Azure itself.

Authenticates using the pipeline's own OAuth token (`System.AccessToken`) rather than a
separate credential — this only works when run from within the Azure DevOps pipeline with
"Allow scripts to access the OAuth token" enabled on the job, and needs the running
identity to have at least Reader access on the DevOps project's Builds. Running this
script outside the pipeline (e.g. locally) requires a Personal Access Token instead — pass
one via -PersonalAccessToken if so.

.PARAMETER Days
How many days of pipeline run history to pull. Defaults to 30.

.EXAMPLE
./Collect-DeploymentActivity.ps1 -TenantName "default" -ConfigPath "variables" -OAuthToken $env:SYSTEM_ACCESSTOKEN
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$TenantName,
    [Parameter(Mandatory = $false)][string]$ConfigPath = "./variables",
    [Parameter(Mandatory = $false)][string]$OAuthToken,
    [Parameter(Mandatory = $false)][string]$PersonalAccessToken,
    [Parameter(Mandatory = $false)][int]$Days = 30
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
    $config = Import-TenantConfig -TenantName $TenantName -ConfigPath $ConfigPath

    $org = $config.devops.organization
    $project = $config.devops.project
    if ([string]::IsNullOrWhiteSpace($org) -or $org -like "*REPLACE*") {
        throw "devops.organization is not configured for tenant '$TenantName' — set it in variables/environments/$TenantName/config.json"
    }

    if ($PersonalAccessToken) {
        $authHeader = "Basic " + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$PersonalAccessToken"))
    }
    elseif ($OAuthToken) {
        $authHeader = "Bearer $OAuthToken"
    }
    else {
        throw "Pass -OAuthToken (from `$(System.AccessToken) in the pipeline) or -PersonalAccessToken (for local runs)."
    }

    $since = (Get-Date).ToUniversalTime().AddDays(-$Days).ToString("o")
    $uri = "https://dev.azure.com/$org/$project/_apis/build/builds?minTime=$since&api-version=7.1-preview.7"

    Write-Log "Fetching builds for $org/$project since $since"
    $response = Invoke-RestMethod -Uri $uri -Headers @{ Authorization = $authHeader } -Method Get -ErrorAction Stop
    $builds = @($response.value)
    Write-Log "Retrieved $($builds.Count) build(s)"

    $rows = [System.Collections.Generic.List[object]]::new()
    foreach ($b in $builds) {
        $rows.Add([pscustomobject]@{
            TimestampUtc  = $b.startTime
            Environment   = if ($b.sourceBranch -match 'prod') { "Production" } elseif ($b.sourceBranch -match 'stag') { "Staging" } elseif ($b.sourceBranch -match 'dev') { "Dev" } else { "Unclassified" }
            SubscriptionId= ""
            ResourceId    = ""
            ResourceName  = $b.definition.name
            PipelineId    = [string]$b.definition.id
            PipelineName  = $b.definition.name
            RunId         = [string]$b.id
            Repository    = $b.repository.name
            Branch        = $b.sourceBranch
            RequestedBy   = $b.requestedFor.displayName
            Status        = if ($b.result) { $b.result } else { $b.status }
            DurationSeconds = if ($b.startTime -and $b.finishTime) {
                [int]([datetime]$b.finishTime - [datetime]$b.startTime).TotalSeconds
            } else { $null }
        })
    }

    $outDir = Join-Path $root "output/adx"
    New-Item -ItemType Directory -Force -Path $outDir | Out-Null
    $outPath = Join-Path $outDir "adx-deployment-activity.json"
    $rows | ConvertTo-Json -Depth 10 | Set-Content -Path $outPath -Encoding utf8

    Write-Log "Wrote $($rows.Count) deployment row(s) to $outPath" -Level "SUCCESS"
}
catch {
    Write-Log "FATAL: Deployment activity collection failed: $_" -Level "ERROR"
    exit 1
}
