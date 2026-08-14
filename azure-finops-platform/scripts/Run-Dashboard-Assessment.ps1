[CmdletBinding()]
param(
	[ValidateSet("Baseline","Hourly","Daily","Weekly")][string]$Mode = "Daily",
	[int]$Days = 90,
	[Parameter(Mandatory = $false)][string]$ConfigPath = "./variables"
)

$ErrorActionPreference = "Stop"
$root = Split-Path $PSScriptRoot -Parent
$out = Join-Path $root "output"
$adxOut = Join-Path $out "adx"
$dashboardOut = Join-Path $out "dashboard"

Import-Module "$PSScriptRoot/ConfigHelper.psm1" -Force
Import-Module "$PSScriptRoot/DashboardDataHelper.psm1" -Force
Import-Module "$PSScriptRoot/UsageDataHelper.psm1" -Force

function Write-Log {
	param([string]$Message, [string]$Level = "INFO")
	$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
	$color = @{INFO="Cyan"; WARN="Yellow"; ERROR="Red"; SUCCESS="Green"}[$Level] ?? "Cyan"
	Write-Host "[$timestamp] [$Level] $Message" -ForegroundColor $color
}

Write-Log "Running base dynamic assessment..."
& "$PSScriptRoot/Run-Dynamic-Assessment.ps1" -Mode $Mode -Days $Days -ConfigPath $ConfigPath
if ($LASTEXITCODE -ne 0) {
	throw "Run-Dynamic-Assessment.ps1 failed with exit code $LASTEXITCODE"
}

New-Item -ItemType Directory -Force -Path $dashboardOut | Out-Null
New-Item -ItemType Directory -Force -Path $adxOut | Out-Null

$inventoryPath = Join-Path $out "resource-inventory.json"
$metricsPath = Join-Path $out "resource-metrics.json"
$activityPath = Join-Path $out "activity-log.json"
$summaryPath = Join-Path $out "summary.json"

if (-not (Test-Path $inventoryPath)) { throw "Missing inventory file: $inventoryPath" }
if (-not (Test-Path $metricsPath)) { throw "Missing metrics file: $metricsPath" }
if (-not (Test-Path $activityPath)) { throw "Missing activity file: $activityPath" }
if (-not (Test-Path $summaryPath)) { throw "Missing summary file: $summaryPath" }

$resources = @(Get-Content $inventoryPath -Raw | ConvertFrom-Json)
$metrics = @(Get-Content $metricsPath -Raw | ConvertFrom-Json)
$activity = @(Get-Content $activityPath -Raw | ConvertFrom-Json)
$summary = Get-Content $summaryPath -Raw | ConvertFrom-Json
$subscriptions = @($summary.subscriptions)

$startDate = [datetime]$summary.dateRange.start
$endDate = [datetime]$summary.dateRange.end

Import-Module Az.Accounts -ErrorAction Stop
Import-Module Az.Advisor -ErrorAction SilentlyContinue

$costRows = [System.Collections.Generic.List[object]]::new()
$advisorRows = [System.Collections.Generic.List[object]]::new()

foreach ($subscription in $subscriptions) {
	$subscriptionId = [string]$subscription.id
	$subscriptionName = [string]$subscription.name
	Write-Log "Collecting cost and recommendation data for $subscriptionName"

	$subscriptionCostRows = @(Get-CostDataForSubscription -SubscriptionId $subscriptionId -StartDate $startDate -EndDate $endDate)
	foreach ($costRow in $subscriptionCostRows) {
		$costResourceId = if ($costRow.PSObject.Properties.Name -contains 'ResourceId') { [string]$costRow.ResourceId } else { '' }
		$matchingResource = $null
		if (-not [string]::IsNullOrWhiteSpace($costResourceId)) {
			$matchingResource = $resources | Where-Object { $_.resourceId -eq $costResourceId } | Select-Object -First 1
		}

		$environment = if ($matchingResource) { [string]$matchingResource.environment } else { 'Unclassified' }
		$resourceName = if ($matchingResource) { [string]$matchingResource.resourceName } else { '' }
		$resourceGroup = if ($costRow.PSObject.Properties.Name -contains 'ResourceGroupName') { [string]$costRow.ResourceGroupName } else { '' }
		$serviceName = if ($costRow.PSObject.Properties.Name -contains 'ServiceName') { [string]$costRow.ServiceName } else { '' }
		$resourceLocation = if ($costRow.PSObject.Properties.Name -contains 'ResourceLocation') { [string]$costRow.ResourceLocation } else { '' }
		$resourceType = if ($costRow.PSObject.Properties.Name -contains 'ResourceType') { [string]$costRow.ResourceType } else { '' }
		$pretaxCost = if ($costRow.PSObject.Properties.Name -contains 'PreTaxCost' -and $costRow.PreTaxCost -ne $null) { [double]$costRow.PreTaxCost } else { 0 }
		$currency = if ($costRow.PSObject.Properties.Name -contains 'Currency' -and -not [string]::IsNullOrWhiteSpace([string]$costRow.Currency)) { [string]$costRow.Currency } else { 'USD' }
		$dateValue = if ($costRow.PSObject.Properties.Name -contains 'UsageDate' -and $costRow.UsageDate) { [string]$costRow.UsageDate } else { $startDate.ToString('yyyy-MM-dd') }

		$costRows.Add([pscustomobject]@{
			Date = $dateValue
			SubscriptionId = $subscriptionId
			SubscriptionName = $subscriptionName
			Environment = $environment
			ResourceId = $costResourceId
			ResourceGroup = $resourceGroup
			ResourceName = $resourceName
			ServiceName = $serviceName
			MeterCategory = $serviceName
			MeterName = $resourceType
			Quantity = 0
			PreTaxCost = [math]::Round($pretaxCost, 2)
			Currency = $currency
			ResourceLocation = $resourceLocation
		})
	}

	$subscriptionAdvisorRows = @(Get-AdvisorRecommendationsForSubscription -SubscriptionId $subscriptionId -SubscriptionName $subscriptionName)
	foreach ($advisorRow in $subscriptionAdvisorRows) {
		$advisorRows.Add($advisorRow)
	}
}

$dashboardData = Build-DashboardData `
	-Resources $resources `
	-Metrics $metrics `
	-Activity $activity `
	-Subscriptions $subscriptions `
	-CostRows @($costRows) `
	-AdvisorRecommendations @($advisorRows) `
	-StartDate $startDate `
	-EndDate $endDate

$dashboardFiles = @{
	'dashboard-overview.json' = $dashboardData.dashboardOverview
	'dashboard-resources-by-environment.json' = $dashboardData.dashboardResourcesByEnvironment
	'dashboard-resources-by-status.json' = $dashboardData.dashboardResourcesByStatus
	'dashboard-cost-analysis.json' = $dashboardData.dashboardCostByEnvironment
	'dashboard-cost-by-service.json' = $dashboardData.dashboardCostByService
	'dashboard-service-adoption.json' = $dashboardData.dashboardServiceAdoption
	'dashboard-locations.json' = $dashboardData.dashboardLocations
	'dashboard-environment-comparison.json' = $dashboardData.dashboardEnvironmentComparison
	'dashboard-unused-resources.json' = $dashboardData.dashboardUnusedResources
	'dashboard-recommendations.json' = $dashboardData.dashboardRecommendations
	'dashboard-reports.json' = $dashboardData.dashboardReports
	'dashboard-data-dictionary.json' = $dashboardData.dashboardDataDictionary
}

foreach ($entry in $dashboardFiles.GetEnumerator()) {
	$path = Join-Path $dashboardOut $entry.Key
	$entry.Value | ConvertTo-Json -Depth 10 | Set-Content -Path $path -Encoding utf8
	Write-Log "Dashboard output saved: $path"
}

Write-Log "Building ResourceUsageFact and AzureActivityFact (Usage & Activity module's real data source)..."
$resourceUsageFact = Build-ResourceUsageFact -Resources $resources -Metrics $metrics -Activity $activity -StartDate $startDate -EndDate $endDate
$azureActivityFact = Build-AzureActivityFact -Activity $activity -Resources $resources
$governanceFact = Build-GovernanceFact -Resources $resources -SnapshotDate $endDate
Write-Log "ResourceUsageFact rows: $($resourceUsageFact.Count), AzureActivityFact rows: $($azureActivityFact.Count), GovernanceFact rows: $($governanceFact.Count)"

$adxFiles = @{
	'adx-resource-inventory.json' = $dashboardData.normalizedResources
	'adx-cost-fact.json' = $dashboardData.normalizedCost
	'adx-recommendations.json' = $dashboardData.normalizedRecommendations
	'adx-resource-usage.json' = $resourceUsageFact
	'adx-activity.json' = $azureActivityFact
	'adx-governance.json' = $governanceFact
	'adx-collector-health.json' = [pscustomobject]@{
		RunId = [guid]::NewGuid().ToString()
		RunStartUtc = $startDate.ToString('o')
		RunEndUtc = (Get-Date).ToUniversalTime().ToString('o')
		Mode = $Mode
		Environment = 'All'
		Status = 'Completed'
		ResourcesCollected = @($dashboardData.normalizedResources).Count
		MetricRows = @($metrics).Count
		ActivityRows = @($activity).Count
		Errors = 0
	}
}

foreach ($entry in $adxFiles.GetEnumerator()) {
	$path = Join-Path $adxOut $entry.Key
	$entry.Value | ConvertTo-Json -Depth 10 | Set-Content -Path $path -Encoding utf8
	Write-Log "ADX-ready output saved: $path"
}

Write-Log "Dashboard assessment completed successfully" -Level "SUCCESS"
Write-Host "Dashboard data created in $dashboardOut and ADX-ready data created in $adxOut" -ForegroundColor Green
