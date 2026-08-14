Set-StrictMode -Version Latest

<#
Before this module existed, Run-Dynamic-Assessment.ps1 collected raw metric rows
(resource-metrics.json: dateUtc/resourceId/metricName/usageSignal/value) and raw activity
rows (activity-log.json: timeGeneratedUtc/resourceId/operationName/caller/category) — but
nothing ever reshaped either into the ResourceUsageFact or AzureActivityFact schema that
UsageActivityController.cs actually queries. The entire Usage & Activity module (13+
endpoints) had no real data source behind it as a result. This module is that missing
transform.
#>

function Get-UsageStatusForResource {
    <#
    Four-tier status (Active/LowUsage/Inactive/NeverUsed), matching
    finops/usage-activity/STATUS-RULES.md — distinct from the older three-tier
    ACTIVE/LOW_USAGE/NO_USAGE classification in Get-UsageStatusFromMetrics (used
    elsewhere for ResourceInventory/orphan detection), because that one collapses
    "has activity log entries but no metric signal" and "has never been touched at all"
    into the same NO_USAGE bucket — this one tells those two apart via ActivityCount.
    #>
    param(
        [Parameter(Mandatory = $true)][object[]]$MetricRows,
        [Parameter(Mandatory = $true)][int]$ActivityCount
    )

    $nonZero = @($MetricRows | Where-Object { [double]$_.value -gt 0 })
    if ($nonZero.Count -gt 0) {
        $avg = ($nonZero | Measure-Object -Property value -Average).Average
        return if ($avg -ge 5) { 'Active' } else { 'LowUsage' }
    }
    if ($ActivityCount -gt 0) { return 'Inactive' }
    return 'NeverUsed'
}

function Build-ResourceUsageFact {
    param(
        [Parameter(Mandatory = $true)][object[]]$Resources,
        [Parameter(Mandatory = $true)][object[]]$Metrics,
        [Parameter(Mandatory = $true)][object[]]$Activity,
        [Parameter(Mandatory = $true)][datetime]$StartDate,
        [Parameter(Mandatory = $true)][datetime]$EndDate
    )

    $metricsByResource = $Metrics | Group-Object -Property resourceId -AsHashTable -AsString
    $activityByResource = $Activity | Group-Object -Property resourceId -AsHashTable -AsString
    $rows = [System.Collections.Generic.List[object]]::new()

    foreach ($r in $Resources) {
        $resourceId = [string]$r.resourceId
        $resourceMetrics = @(if ($metricsByResource.ContainsKey($resourceId)) { $metricsByResource[$resourceId] } else { @() })
        $resourceActivity = @(if ($activityByResource.ContainsKey($resourceId)) { $activityByResource[$resourceId] } else { @() })

        function SignalAvg($signal) {
            $rowsForSignal = @($resourceMetrics | Where-Object { $_.usageSignal -eq $signal })
            if ($rowsForSignal.Count -eq 0) { return $null }
            return [math]::Round((($rowsForSignal | Measure-Object -Property value -Average).Average), 2)
        }
        function SignalSum($signal) {
            $rowsForSignal = @($resourceMetrics | Where-Object { $_.usageSignal -eq $signal })
            if ($rowsForSignal.Count -eq 0) { return 0 }
            return [math]::Round((($rowsForSignal | Measure-Object -Property value -Sum).Sum), 0)
        }

        $lastActivity = $null
        if ($resourceActivity.Count -gt 0) {
            $lastActivity = ($resourceActivity | ForEach-Object { [datetime]$_.timeGeneratedUtc } | Sort-Object -Descending | Select-Object -First 1)
        }
        elseif ($resourceMetrics.Count -gt 0) {
            $lastActivity = ($resourceMetrics | ForEach-Object { [datetime]$_.dateUtc } | Sort-Object -Descending | Select-Object -First 1)
        }

        $tags = if ($r.PSObject.Properties.Name -contains 'tags') { $r.tags } else { $null }
        $owner = if ($tags -and $tags.ApplicationOwner) { [string]$tags.ApplicationOwner } else { "" }
        $application = if ($tags -and $tags.Application) { [string]$tags.Application } else { "" }
        $businessUnit = if ($tags -and $tags.BusinessUnit) { [string]$tags.BusinessUnit } else { "" }
        $costCenter = if ($tags -and $tags.CostCenter) { [string]$tags.CostCenter } else { "" }

        $rows.Add([pscustomobject]@{
            Date               = $EndDate.ToString("yyyy-MM-dd")
            TimestampUtc       = $EndDate.ToString("o")
            SubscriptionId     = $r.subscriptionId
            SubscriptionName   = $r.subscriptionName
            Environment        = if ($r.PSObject.Properties.Name -contains 'environment') { $r.environment } else { "Unclassified" }
            ResourceId         = $resourceId
            ResourceName       = $r.resourceName
            ResourceGroup      = $r.resourceGroup
            ResourceType       = $r.resourceType
            ServiceName        = $r.serviceName
            Region             = $r.location
            Owner              = $owner
            Application        = $application
            BusinessUnit       = $businessUnit
            CostCenter         = $costCenter
            ActivityCount      = $resourceActivity.Count
            RequestCount       = [int](SignalSum "requests")
            FailedRequestCount = [int](SignalSum "failedRequests")
            InvocationCount    = [int](SignalSum "invocations")
            CPUPercent         = SignalAvg "cpu"
            MemoryPercent      = SignalAvg "memory"
            NetworkBytes       = [int64](SignalSum "network")
            TransactionCount   = [int](SignalSum "transactions")
            LastActivityUtc    = if ($lastActivity) { $lastActivity.ToString("o") } else { $null }
            PowerState         = if ($r.PSObject.Properties.Name -contains 'powerState') { $r.powerState } else { "" }
            UsageStatus        = Get-UsageStatusForResource -MetricRows $resourceMetrics -ActivityCount $resourceActivity.Count
            ActivitySource     = "ResourceGraph+Monitor+ActivityLog"
        })
    }

    return $rows.ToArray()
}

function Build-AzureActivityFact {
    param(
        [Parameter(Mandatory = $true)][object[]]$Activity,
        [Parameter(Mandatory = $true)][object[]]$Resources
    )

    $resourceById = $Resources | Group-Object -Property resourceId -AsHashTable -AsString
    $rows = [System.Collections.Generic.List[object]]::new()

    foreach ($e in $Activity) {
        $r = if ($e.resourceId -and $resourceById.ContainsKey([string]$e.resourceId)) { $resourceById[[string]$e.resourceId][0] } else { $null }
        $callerType = if ([string]::IsNullOrWhiteSpace($e.caller)) { "Unknown" }
                      elseif ($e.caller -match '^[0-9a-f-]{36}$') { "ManagedIdentity" }
                      elseif ($e.caller -match '@') { "Human" }
                      else { "ServicePrincipal" }

        $rows.Add([pscustomobject]@{
            TimestampUtc     = $e.timeGeneratedUtc
            SubscriptionId   = $e.subscriptionId
            SubscriptionName = $e.subscriptionName
            Environment      = if ($r -and $r.PSObject.Properties.Name -contains 'environment') { $r.environment } else { "Unclassified" }
            ResourceId       = $e.resourceId
            ResourceGroup    = $e.resourceGroup
            ResourceProvider = if ($e.resourceId) { ($e.resourceId -split '/providers/')[1] -split '/' | Select-Object -First 1 } else { "" }
            OperationName    = $e.operationName
            ActivityStatus   = $e.activityStatus
            Caller           = $e.caller
            CallerType       = $callerType
            CorrelationId    = ""
            ResourceName     = $e.resourceName
            Region           = if ($r) { $r.location } else { "" }
        })
    }

    return $rows.ToArray()
}

function Build-GovernanceFact {
    <#
    Tag compliance against finops/governance/TAGGING-STANDARD.md's required tag list —
    the other half of what FinOpsGovernanceFact needs (TagCompliancePercent, OwnerPresent,
    MissingRequiredTags) is derivable straight from ResourceInventory's tags, which is
    already collected; nothing was computing it before. PolicyState and BudgetState are
    NOT computed here — they need Azure Policy compliance and budget-vs-actual data this
    script doesn't have, so they're left as "NotEvaluated" rather than guessed at.
    #>
    param(
        [Parameter(Mandatory = $true)][object[]]$Resources,
        [Parameter(Mandatory = $true)][datetime]$SnapshotDate
    )

    $requiredTags = @('Environment','Application','ApplicationOwner','TechnicalOwner','BusinessUnit','CostCenter','Project','Criticality')
    $rows = [System.Collections.Generic.List[object]]::new()

    foreach ($r in $Resources) {
        $tags = if ($r.PSObject.Properties.Name -contains 'tags') { $r.tags } else { $null }
        $presentTags = @($requiredTags | Where-Object {
            $tags -and $tags.PSObject.Properties.Name -contains $_ -and -not [string]::IsNullOrWhiteSpace([string]$tags.$_)
        })
        $missing = $requiredTags.Count - $presentTags.Count
        $ownerPresent = $presentTags -contains 'ApplicationOwner' -or $presentTags -contains 'TechnicalOwner'

        $rows.Add([pscustomobject]@{
            SnapshotDate         = $SnapshotDate.ToString("yyyy-MM-dd")
            Environment          = if ($r.PSObject.Properties.Name -contains 'environment') { $r.environment } else { "Unclassified" }
            SubscriptionId       = $r.subscriptionId
            ResourceId           = $r.resourceId
            ResourceName         = $r.resourceName
            MissingRequiredTags  = $missing
            TagCompliancePercent = [math]::Round((($presentTags.Count / $requiredTags.Count) * 100), 2)
            OwnerPresent         = $ownerPresent
            PolicyState          = "NotEvaluated"
            BudgetState          = "NotEvaluated"
        })
    }

    return $rows.ToArray()
}

Export-ModuleMember -Function Get-UsageStatusForResource, Build-ResourceUsageFact, Build-AzureActivityFact, Build-GovernanceFact
