Set-StrictMode -Version Latest

<#
.SYNOPSIS
Runs a `.set-or-append` management command against an ADX database, appending the
result of a KQL query into a target table.

.DESCRIPTION
Factored out of Invoke-OrphanDetection.ps1 so the same execution path is shared by every
script that computes something from data already in ADX and writes the result back as a
table (orphan detection, cost forecast, cost anomaly detection) — rather than three near-
identical copies of the same REST call.
#>
function Invoke-AdxSetOrAppend {
    param(
        [Parameter(Mandatory = $true)][string]$ClusterUrl,
        [Parameter(Mandatory = $true)][string]$Database,
        [Parameter(Mandatory = $true)][string]$TargetTable,
        [Parameter(Mandatory = $true)][string]$Query
    )

    $token = (Get-AzAccessToken -ResourceUrl $ClusterUrl).Token
    $mgmtCommand = ".set-or-append $TargetTable <|`n$Query"
    $body = @{ db = $Database; csl = $mgmtCommand } | ConvertTo-Json -Depth 5
    $uri = "$ClusterUrl/v1/rest/mgmt"

    return Invoke-RestMethod -Uri $uri -Method Post -Body $body -ContentType "application/json" `
        -Headers @{ Authorization = "Bearer $token" }
}

Export-ModuleMember -Function Invoke-AdxSetOrAppend
