Set-StrictMode -Version Latest

function Get-EnvironmentNameFromResource {
	param(
		[Parameter(Mandatory = $true)]
		[psobject]$Resource
	)

	$candidates = @()

	if ($Resource.PSObject.Properties.Name -contains 'tags' -and $null -ne $Resource.tags) {
		if ($Resource.tags.environment) { $candidates += [string]$Resource.tags.environment }
		if ($Resource.tags.Environment) { $candidates += [string]$Resource.tags.Environment }
		if ($Resource.tags.env) { $candidates += [string]$Resource.tags.env }
		if ($Resource.tags.Env) { $candidates += [string]$Resource.tags.Env }
	}

	$resourceGroup = if ($Resource.PSObject.Properties.Name -contains 'resourceGroup') { [string]$Resource.resourceGroup } else { '' }
	$subscriptionName = if ($Resource.PSObject.Properties.Name -contains 'subscriptionName') { [string]$Resource.subscriptionName } else { '' }
	$resourceName = if ($Resource.PSObject.Properties.Name -contains 'resourceName') { [string]$Resource.resourceName } else { '' }

	$candidates += @($resourceGroup, $subscriptionName, $resourceName)

	foreach ($candidate in $candidates) {
		if ([string]::IsNullOrWhiteSpace($candidate)) { continue }
		$normalized = $candidate.ToLowerInvariant()
		if ($normalized -match 'prod') { return 'Production' }
		if ($normalized -match 'stag|uat|preprod') { return 'Staging' }
		if ($normalized -match 'dev|test|qa') { return 'Dev' }
		if ($normalized -match 'sbx|sandbox|demo|lab|poc') { return 'Sandbox' }
	}

	return 'Unclassified'
}

function Get-UsageStatusFromMetrics {
	param(
		[Parameter(Mandatory = $true)]
		[object[]]$MetricRows
	)

	if ($null -eq $MetricRows -or $MetricRows.Count -eq 0) {
		return 'NO_USAGE'
	}

	$nonZeroRows = @($MetricRows | Where-Object { [double]$_.value -gt 0 })
	if ($nonZeroRows.Count -eq 0) {
		return 'NO_USAGE'
	}

	$avgValue = ($nonZeroRows | Measure-Object -Property value -Average).Average
	if ($avgValue -lt 5) {
		return 'LOW_USAGE'
	}

	return 'ACTIVE'
}

function Get-OrphanedReason {
	param(
		[Parameter(Mandatory = $true)]
		[psobject]$Resource,
		[Parameter(Mandatory = $true)]
		[string]$UsageStatus,
		[Parameter(Mandatory = $true)]
		[int]$ActivityCount
	)

	if ($ActivityCount -eq 0 -and $UsageStatus -eq 'NO_USAGE') {
		return 'No activity and no usage in the selected time window'
	}

	if ($Resource.resourceType -match 'publicIPAddresses' -and $ActivityCount -eq 0) {
		return 'Public IP with no observed activity'
	}

	if ($Resource.resourceType -match 'disks' -and [string]::IsNullOrWhiteSpace([string]$Resource.managedBy)) {
		return 'Disk is not attached to a managed resource'
	}

	if ($Resource.resourceType -match 'networkInterfaces' -and [string]::IsNullOrWhiteSpace([string]$Resource.managedBy)) {
		return 'Network interface appears unattached'
	}

	return ''
}

function Get-AdvisorRecommendationsForSubscription {
	param(
		[Parameter(Mandatory = $true)]
		[string]$SubscriptionId,
		[Parameter(Mandatory = $true)]
		[string]$SubscriptionName
	)

	$recommendations = [System.Collections.Generic.List[object]]::new()

	try {
		Set-AzContext -SubscriptionId $SubscriptionId -ErrorAction Stop | Out-Null
		$advisorRows = Get-AzAdvisorRecommendation -ErrorAction Stop

		foreach ($row in $advisorRows) {
			$recommendations.Add([pscustomobject]@{
				subscriptionId = $SubscriptionId
				subscriptionName = $SubscriptionName
				recommendationType = if ($row.Category) { [string]$row.Category } else { 'Advisor' }
				impact = if ($row.Impact) { [string]$row.Impact } else { 'Unknown' }
				resourceId = [string]$row.ResourceId
				resourceGroup = [string]$row.ResourceGroup
				shortDescription = if ($row.ShortDescription.Problem) { [string]$row.ShortDescription.Problem } else { [string]$row.Name }
				recommendationText = if ($row.ShortDescription.Solution) { [string]$row.ShortDescription.Solution } else { [string]$row.Description }
				annualSavingsAmount = if ($row.ExtendedProperties.annualSavingsAmount) { [double]$row.ExtendedProperties.annualSavingsAmount } else { 0 }
				monthlySavingsAmount = if ($row.ExtendedProperties.annualSavingsAmount) { [math]::Round(([double]$row.ExtendedProperties.annualSavingsAmount / 12), 2) } else { 0 }
				currency = if ($row.ExtendedProperties.savingsCurrency) { [string]$row.ExtendedProperties.savingsCurrency } else { 'USD' }
				source = 'AzureAdvisor'
			})
		}
	}
	catch {
		Write-Warning "Advisor recommendations unavailable for $SubscriptionName ($SubscriptionId): $($_.Exception.Message)"
	}

	return $recommendations
}

function Get-CostDataForSubscription {
	param(
		[Parameter(Mandatory = $true)]
		[string]$SubscriptionId,
		[Parameter(Mandatory = $true)]
		[datetime]$StartDate,
		[Parameter(Mandatory = $true)]
		[datetime]$EndDate
	)

	$scope = "/subscriptions/$SubscriptionId"
	$body = @{
		type = 'ActualCost'
		timeframe = 'Custom'
		timePeriod = @{
			from = $StartDate.ToString('yyyy-MM-ddT00:00:00Z')
			to = $EndDate.ToString('yyyy-MM-ddT23:59:59Z')
		}
		dataSet = @{
			granularity = 'Daily'
			aggregation = @{
				totalCost = @{
					name = 'PreTaxCost'
					function = 'Sum'
				}
			}
			grouping = @(
				@{ type = 'Dimension'; name = 'SubscriptionId' },
				@{ type = 'Dimension'; name = 'ResourceGroupName' },
				@{ type = 'Dimension'; name = 'ResourceLocation' },
				@{ type = 'Dimension'; name = 'ResourceType' },
				@{ type = 'Dimension'; name = 'ServiceName' },
				@{ type = 'Dimension'; name = 'Currency' }
			)
		}
	}

	try {
		$response = Invoke-AzRestMethod -Path "$scope/providers/Microsoft.CostManagement/query?api-version=2023-03-01" -Method POST -Payload ($body | ConvertTo-Json -Depth 10) -ErrorAction Stop
		if ([string]::IsNullOrWhiteSpace($response.Content)) {
			return @()
		}

		$content = $response.Content | ConvertFrom-Json
		if ($null -eq $content.properties.rows) {
			return @()
		}

		$columns = @($content.properties.columns | ForEach-Object { $_.name })
		$result = foreach ($row in $content.properties.rows) {
			$item = @{}
			for ($i = 0; $i -lt $columns.Count; $i++) {
				$item[$columns[$i]] = $row[$i]
			}
			[pscustomobject]$item
		}

		return @($result | Where-Object {
			$currency = if ($_.PSObject.Properties.Name -contains 'Currency' -and -not [string]::IsNullOrWhiteSpace([string]$_.Currency)) { [string]$_.Currency } else { 'USD' }
			$currency -eq 'USD'
		})
	}
	catch {
		Write-Warning "Cost query failed for subscription $SubscriptionId: $($_.Exception.Message)"
		return @()
	}
}

function Build-DashboardData {
	param(
		[Parameter(Mandatory = $true)]
		[object[]]$Resources,
		[Parameter(Mandatory = $true)]
		[object[]]$Metrics,
		[Parameter(Mandatory = $true)]
		[object[]]$Activity,
		[Parameter(Mandatory = $true)]
		[object[]]$Subscriptions,
		[Parameter(Mandatory = $true)]
		[object[]]$CostRows,
		[Parameter(Mandatory = $true)]
		[object[]]$AdvisorRecommendations,
		[Parameter(Mandatory = $true)]
		[datetime]$StartDate,
		[Parameter(Mandatory = $true)]
		[datetime]$EndDate
	)

	$resourceList = @($Resources)
	$metricList = @($Metrics)
	$activityList = @($Activity)
	$costList = @($CostRows)
	$advisorList = @($AdvisorRecommendations)

	foreach ($resource in $resourceList) {
		$environment = Get-EnvironmentNameFromResource -Resource $resource
		Add-Member -InputObject $resource -NotePropertyName environment -NotePropertyValue $environment -Force

		$resourceMetricRows = @($metricList | Where-Object { $_.resourceId -eq $resource.resourceId })
		$usageStatus = if ($resource.PSObject.Properties.Name -contains 'usageStatus' -and -not [string]::IsNullOrWhiteSpace([string]$resource.usageStatus)) {
			[string]$resource.usageStatus
		}
		else {
			Get-UsageStatusFromMetrics -MetricRows $resourceMetricRows
		}

		Add-Member -InputObject $resource -NotePropertyName usageStatus -NotePropertyValue $usageStatus -Force

		$activityCount = @($activityList | Where-Object { $_.resourceId -eq $resource.resourceId }).Count
		Add-Member -InputObject $resource -NotePropertyName activityCount -NotePropertyValue $activityCount -Force

		$orphanedReason = Get-OrphanedReason -Resource $resource -UsageStatus $usageStatus -ActivityCount $activityCount
		Add-Member -InputObject $resource -NotePropertyName orphanedReason -NotePropertyValue $orphanedReason -Force
		Add-Member -InputObject $resource -NotePropertyName isOrphaned -NotePropertyValue (-not [string]::IsNullOrWhiteSpace($orphanedReason)) -Force
	}

	$resourcesByEnvironment = @($resourceList | Group-Object environment | ForEach-Object {
		[pscustomobject]@{
			environment = $_.Name
			totalResources = $_.Count
			percent = if ($resourceList.Count -gt 0) { [math]::Round(($_.Count / $resourceList.Count) * 100, 2) } else { 0 }
		}
	} | Sort-Object totalResources -Descending)

	$resourcesByStatus = @($resourceList | Group-Object usageStatus | ForEach-Object {
		[pscustomobject]@{
			status = $_.Name
			totalResources = $_.Count
			percent = if ($resourceList.Count -gt 0) { [math]::Round(($_.Count / $resourceList.Count) * 100, 2) } else { 0 }
		}
	})

	$serviceAdoption = @($resourceList | Group-Object serviceName | ForEach-Object {
		$groupRows = @($_.Group)
		$active = @($groupRows | Where-Object { $_.usageStatus -eq 'ACTIVE' }).Count
		$low = @($groupRows | Where-Object { $_.usageStatus -eq 'LOW_USAGE' }).Count
		$none = @($groupRows | Where-Object { $_.usageStatus -eq 'NO_USAGE' }).Count
		$orphaned = @($groupRows | Where-Object { $_.isOrphaned }).Count
		[pscustomobject]@{
			serviceName = $_.Name
			totalResources = $groupRows.Count
			activeResources = $active
			lowUsageResources = $low
			noUsageResources = $none
			orphanedResources = $orphaned
			adoptionPercent = if ($groupRows.Count -gt 0) { [math]::Round(($active / $groupRows.Count) * 100, 2) } else { 0 }
		}
	} | Sort-Object totalResources -Descending)

	$locations = @($resourceList | Group-Object location | ForEach-Object {
		[pscustomobject]@{
			location = if ([string]::IsNullOrWhiteSpace($_.Name)) { 'Unknown' } else { $_.Name }
			totalResources = $_.Count
		}
	} | Sort-Object totalResources -Descending)

	$environmentComparison = @($resourceList | Group-Object environment | ForEach-Object {
		$envName = $_.Name
		$envRows = @($_.Group)
		$envCostRows = @($costList | Where-Object { $_.Environment -eq $envName })
		[pscustomobject]@{
			environment = $envName
			totalResources = $envRows.Count
			activeResources = @($envRows | Where-Object { $_.usageStatus -eq 'ACTIVE' }).Count
			lowUsageResources = @($envRows | Where-Object { $_.usageStatus -eq 'LOW_USAGE' }).Count
			noUsageResources = @($envRows | Where-Object { $_.usageStatus -eq 'NO_USAGE' }).Count
			orphanedResources = @($envRows | Where-Object { $_.isOrphaned }).Count
			monthlyCost = [math]::Round((($envCostRows | Measure-Object -Property PreTaxCost -Sum).Sum), 2)
		}
	} | Sort-Object totalResources -Descending)

	$topUnusedResources = @($resourceList |
		Where-Object { $_.usageStatus -eq 'NO_USAGE' -or $_.isOrphaned } |
		ForEach-Object {
			$costForResource = ($costList | Where-Object { $_.ResourceId -eq $_.resourceId } | Measure-Object -Property PreTaxCost -Sum).Sum
			[pscustomobject]@{
				resourceName = $_.resourceName
				resourceType = $_.resourceType
				environment = $_.environment
				resourceGroup = $_.resourceGroup
				lastActivity = if ($_.activityCount -gt 0) { 'Recent' } else { '-' }
				monthlyCost = [math]::Round($costForResource, 2)
				orphanedReason = $_.orphanedReason
			}
		} |
		Sort-Object monthlyCost -Descending |
		Select-Object -First 10)

	$costByEnvironment = @($costList | Group-Object Environment | ForEach-Object {
		[pscustomobject]@{
			environment = $_.Name
			monthlyCost = [math]::Round((($_.Group | Measure-Object -Property PreTaxCost -Sum).Sum), 2)
		}
	} | Sort-Object monthlyCost -Descending)

	$costByService = @($costList | Group-Object ServiceName | ForEach-Object {
		[pscustomobject]@{
			serviceName = if ([string]::IsNullOrWhiteSpace($_.Name)) { 'Unknown' } else { $_.Name }
			monthlyCost = [math]::Round((($_.Group | Measure-Object -Property PreTaxCost -Sum).Sum), 2)
		}
	} | Sort-Object monthlyCost -Descending)

	$derivedRecommendations = [System.Collections.Generic.List[object]]::new()
	foreach ($resource in ($resourceList | Where-Object { $_.usageStatus -eq 'NO_USAGE' -or $_.usageStatus -eq 'LOW_USAGE' -or $_.isOrphaned })) {
		$recommendationType = if ($resource.isOrphaned) { 'Delete' } elseif ($resource.usageStatus -eq 'LOW_USAGE') { 'Right-size' } else { 'Shutdown (Schedule)' }
		$resourceCost = ($costList | Where-Object { $_.ResourceId -eq $resource.resourceId } | Measure-Object -Property PreTaxCost -Sum).Sum
		$derivedRecommendations.Add([pscustomobject]@{
			subscriptionId = $resource.subscriptionId
			subscriptionName = $resource.subscriptionName
			recommendationType = $recommendationType
			impact = 'Medium'
			resourceId = $resource.resourceId
			resourceGroup = $resource.resourceGroup
			shortDescription = "$recommendationType candidate for $($resource.resourceName)"
			recommendationText = $resource.orphanedReason
			monthlySavingsAmount = [math]::Round($resourceCost, 2)
			currency = 'USD'
			source = 'DerivedHeuristic'
		})
	}

	$allRecommendations = @($advisorList + $derivedRecommendations)
	$recommendationSummary = @($allRecommendations | Group-Object recommendationType | ForEach-Object {
		[pscustomobject]@{
			recommendation = $_.Name
			resources = $_.Count
			potentialMonthlySavings = [math]::Round((($_.Group | Measure-Object -Property monthlySavingsAmount -Sum).Sum), 2)
		}
	} | Sort-Object potentialMonthlySavings -Descending)

	$overview = [pscustomobject]@{
		collectionStartUtc = $StartDate.ToString('o')
		collectionEndUtc = $EndDate.ToString('o')
		subscriptionsScanned = $Subscriptions.Count
		totalResources = $resourceList.Count
		activeResources = @($resourceList | Where-Object { $_.usageStatus -eq 'ACTIVE' }).Count
		lowUsageResources = @($resourceList | Where-Object { $_.usageStatus -eq 'LOW_USAGE' }).Count
		noUsageResources = @($resourceList | Where-Object { $_.usageStatus -eq 'NO_USAGE' }).Count
		orphanedResources = @($resourceList | Where-Object { $_.isOrphaned }).Count
		totalMonthlyCost = [math]::Round((($costList | Measure-Object -Property PreTaxCost -Sum).Sum), 2)
	}

	$reports = [pscustomobject]@{
		generatedUtc = (Get-Date).ToUniversalTime().ToString('o')
		availableReports = @(
			'dashboard-overview.json',
			'dashboard-cost-analysis.json',
			'dashboard-service-adoption.json',
			'dashboard-environment-comparison.json',
			'dashboard-unused-resources.json',
			'dashboard-recommendations.json',
			'dashboard-locations.json',
			'dashboard-data-dictionary.json'
		)
	}

	$dataDictionary = @(
		[pscustomobject]@{ field = 'totalResources'; description = 'Count of discovered Azure resources across all accessible subscriptions.' },
		[pscustomobject]@{ field = 'usageStatus'; description = 'Derived status based on collected metrics and activity data: ACTIVE, LOW_USAGE, or NO_USAGE.' },
		[pscustomobject]@{ field = 'isOrphaned'; description = 'True when the script detects an unattached or inactive standalone resource pattern.' },
		[pscustomobject]@{ field = 'monthlyCost'; description = 'Pre-tax cost aggregated from Azure Cost Management query results for the selected period.' },
		[pscustomobject]@{ field = 'adoptionPercent'; description = 'Percentage of active resources within a service or environment grouping.' }
	)

	return [pscustomobject]@{
		normalizedResources = $resourceList
		normalizedCost = $costList
		normalizedRecommendations = $allRecommendations
		dashboardOverview = $overview
		dashboardResourcesByEnvironment = $resourcesByEnvironment
		dashboardResourcesByStatus = $resourcesByStatus
		dashboardCostByEnvironment = $costByEnvironment
		dashboardCostByService = $costByService
		dashboardServiceAdoption = $serviceAdoption
		dashboardLocations = $locations
		dashboardEnvironmentComparison = $environmentComparison
		dashboardUnusedResources = $topUnusedResources
		dashboardRecommendations = $recommendationSummary
		dashboardReports = $reports
		dashboardDataDictionary = $dataDictionary
	}
}

Export-ModuleMember -Function Get-EnvironmentNameFromResource, Get-UsageStatusFromMetrics, Get-OrphanedReason, Get-AdvisorRecommendationsForSubscription, Get-CostDataForSubscription, Build-DashboardData
