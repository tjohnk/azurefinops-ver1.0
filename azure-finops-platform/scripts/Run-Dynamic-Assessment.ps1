[CmdletBinding()]
param(
	[ValidateSet("Baseline","Hourly","Daily","Weekly")][string]$Mode="Daily",
	[int]$Days=90,
	[Parameter(Mandatory=$false)][string]$ConfigPath="./variables"
)

$ErrorActionPreference="Stop"

# ============================================
# Import configuration helper
# ============================================
$root = Split-Path $PSScriptRoot -Parent
Import-Module "$PSScriptRoot/ConfigHelper.psm1" -Force

# Logging function
function Write-Log {
	param([string]$Message, [string]$Level = "INFO")
	$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
	$color = @{INFO="Cyan"; WARN="Yellow"; ERROR="Red"; SUCCESS="Green"}[$Level] ?? "Cyan"
	Write-Host "[$timestamp] [$Level] $Message" -ForegroundColor $color
}

try {
	Write-Log "Azure Resource Assessment - Mode: $Mode, Days: $Days"
	Write-Log "Discovering accessible subscriptions dynamically..."

	# ============================================
	# PHASE 0: Dynamic Subscription Discovery
	# ============================================
	Write-Log "=== PHASE 0: Subscription Discovery ===" -Level "INFO"

	# Get all subscriptions accessible to current context
	$allSubscriptions = Get-AzSubscription -ErrorAction Stop

	if ($null -eq $allSubscriptions -or $allSubscriptions.Count -eq 0) {
		Write-Log "ERROR: No subscriptions found. Ensure you are logged in with appropriate permissions" -Level "ERROR"
		exit 1
	}

	if ($allSubscriptions -is [System.Object] -and $allSubscriptions.GetType().Name -ne "PSCustomObject[]") {
		$allSubscriptions = @($allSubscriptions)
	}

	Write-Log "Found $($allSubscriptions.Count) accessible subscriptions:"
	foreach ($sub in $allSubscriptions) {
		$subState = $sub.State
		Write-Log "  ✓ $($sub.Name) ($($sub.Id)) - State: $subState"
	}

	# Filter out disabled subscriptions
	$activeSubscriptions = $allSubscriptions | Where-Object { $_.State -eq "Enabled" }
	Write-Log "Active subscriptions: $($activeSubscriptions.Count)"

	if ($activeSubscriptions.Count -eq 0) {
		Write-Log "WARNING: No active subscriptions found" -Level "WARN"
		exit 0
	}

	# Load shared configuration (service and metric mappings)
	$configDir = Resolve-Path $ConfigPath -ErrorAction Stop
	$sharedDir = Join-Path $configDir "shared"

	Write-Log "Loading shared mappings..."
	$serviceMapping = Get-Content (Join-Path $sharedDir "service-mapping.json") -Raw | ConvertFrom-Json
	$metricMapping = Get-Content (Join-Path $sharedDir "metric-mapping.json") -Raw | ConvertFrom-Json

	Write-Log "Service mappings: $($serviceMapping.Count) types"
	Write-Log "Metric mappings: $($metricMapping.Count) metrics"

	# Setup output directory
	$out = "$root/output"
	New-Item -ItemType Directory -Force -Path $out | Out-Null
	Write-Log "Output directory: $out"
}
catch {
	Write-Log "FATAL: Failed to load configuration: $_" -Level "ERROR"
	exit 1
}

# Import required Azure modules
Write-Log "Importing Azure modules..."
Import-Module Az.Accounts -ErrorAction Stop
Import-Module Az.ResourceGraph -ErrorAction Stop
Import-Module Az.Monitor -ErrorAction Stop
Write-Log "Azure modules imported successfully"

# ============================================
# PHASE 1: Collect Resource Inventory
# ============================================
Write-Log "=== PHASE 1: Resource Inventory Collection ===" -Level "INFO"
$resources = [System.Collections.Generic.List[object]]::new()
$resourceCount = 0
$successCount = 0
$errorCount = 0

foreach ($sub in $activeSubscriptions) {
	$subscriptionId = $sub.Id
	$subscriptionName = $sub.Name

	try {
		Write-Log "Collecting resources from subscription: $subscriptionName ($subscriptionId)"
		Set-AzContext -SubscriptionId $subscriptionId -ErrorAction Stop | Out-Null

		# Get all resources using Resource Graph Query (more efficient)
		$query = @"
Resources
| project 
	id,
	name,
	type,
	resourceGroup,
	subscriptionId,
	location,
	kind,
	managedBy,
	tags,
	sku,
	properties
| limit 5000
"@

		$items = @()
		$skipToken = $null

		do {
			try {
				if ($skipToken) {
					$pageResults = Search-AzGraph -Query $query -First 1000 -SkipToken $skipToken -ErrorAction Stop
				} else {
					$pageResults = Search-AzGraph -Query $query -First 1000 -ErrorAction Stop
				}

				if ($pageResults) {
					$items += $pageResults
					$skipToken = $pageResults[-1].__tokens[0]
				}
			}
			catch {
				Write-Log "WARNING: Error querying resource graph for $subscriptionName (page): $_" -Level "WARN"
				break
			}
		} while ($skipToken)

		Write-Log "Retrieved $($items.Count) resources from $subscriptionName"

		# Process each resource
		foreach ($r in $items) {
			try {
				$m = $serviceMapping | Where-Object { $_.resourceType -ieq $r.type } | Select-Object -First 1

				# Determine usage status (default to Active)
				$usageStatus = "ACTIVE"
				if ($r.tags -and $r.tags.usageStatus) {
					$usageStatus = $r.tags.usageStatus
				}

				$resource = [pscustomobject]@{
					snapshotDateUtc = (Get-Date).ToUniversalTime().ToString("o")
					subscriptionId = $subscriptionId
					subscriptionName = $subscriptionName
					resourceId = $r.id
					resourceName = $r.name
					resourceGroup = $r.resourceGroup
					resourceType = $r.type
					serviceCategory = if ($m) { $m.serviceCategory } else { "Other" }
					serviceName = if ($m) { $m.serviceName } else { $r.type }
					location = $r.location
					kind = $r.kind
					managedBy = $r.managedBy
					sku = $r.sku
					tags = $r.tags
					usageStatus = $usageStatus
				}

				$resources.Add($resource)
				$resourceCount++
			}
			catch {
				$errorCount++
				Write-Log "ERROR processing resource $($r.name): $_" -Level "ERROR"
			}
		}

		$successCount++
		Write-Log "SUCCESS: Processed $($items.Count) resources from $subscriptionName"
	}
	catch {
		$errorCount++
		Write-Log "ERROR: Failed to collect from subscription $subscriptionName ($subscriptionId): $_" -Level "ERROR"
		continue
	}
}

Write-Log "=== PHASE 1 SUMMARY ===" -Level "INFO"
Write-Log "Subscriptions processed: $successCount"
Write-Log "Subscriptions with errors: $errorCount"
Write-Log "Total resources collected: $resourceCount"

$inventoryPath = "$out/resource-inventory.json"
$resources | ConvertTo-Json -Depth 10 | Set-Content -Encoding utf8 $inventoryPath -ErrorAction Stop
Write-Log "Resource inventory saved to: $inventoryPath"

# ============================================
# PHASE 2: Collect Metrics (for resources with metrics)
# ============================================
Write-Log "=== PHASE 2: Metrics Collection ===" -Level "INFO"
$days = if ($Mode -eq "Hourly") { 1 } else { $Days }
$start = (Get-Date).ToUniversalTime().AddDays(-$days)
$end = (Get-Date).ToUniversalTime()
$grain = New-TimeSpan -Minutes (if ($Mode -eq "Hourly") { 60 } else { 1440 })

Write-Log "Collecting metrics from $($start.ToShortDateString()) to $($end.ToShortDateString())"
Write-Log "Time grain: $($grain.TotalMinutes) minutes"

$metrics = [System.Collections.Generic.List[object]]::new()
$metricCount = 0
$metricErrors = 0
$metricsCollected = 0

# Group resources by subscription for efficient processing
$resourcesBySubscription = $resources | Group-Object -Property subscriptionId

foreach ($subGroup in $resourcesBySubscription) {
	$subscriptionId = $subGroup.Name

	try {
		Set-AzContext -SubscriptionId $subscriptionId -ErrorAction Stop | Out-Null
		Write-Log "Collecting metrics for subscription: $subscriptionId ($($subGroup.Group.Count) resources)"

		foreach ($r in $subGroup.Group) {
			# Find applicable metrics for this resource type
			$applicableMetrics = $metricMapping | Where-Object { $_.resourceType -ieq $r.resourceType }

			if ($applicableMetrics.Count -eq 0) {
				continue
			}

			foreach ($m in $applicableMetrics) {
				try {
					Write-Log "Querying metric $($m.metricName) for $($r.resourceName)..." -Level "INFO"

					$data = Get-AzMetric -ResourceId $r.resourceId `
						-MetricName $m.metricName `
						-StartTime $start `
						-EndTime $end `
						-TimeGrain $grain `
						-AggregationType $m.aggregation `
						-WarningAction SilentlyContinue `
						-ErrorAction Stop

					if ($data -and $data.Data) {
						foreach ($d in $data.Data) {
							$v = $d.($m.aggregation)
							if ($null -ne $v) {
								$metric = [pscustomobject]@{
									dateUtc = $d.TimeStamp.ToUniversalTime().ToString("o")
									subscriptionId = $r.subscriptionId
									subscriptionName = $r.subscriptionName
									resourceId = $r.resourceId
									resourceName = $r.resourceName
									serviceName = $r.serviceName
									metricName = $m.metricName
									usageSignal = $m.usageSignal
									aggregation = $m.aggregation
									value = [double]$v
								}
								$metrics.Add($metric)
								$metricCount++
							}
						}
						$metricsCollected++
					}
				}
				catch {
					$metricErrors++
					Write-Log "WARNING: $($r.resourceName) - Metric $($m.metricName) unavailable: $($_.Exception.Message)" -Level "WARN"
				}
			}
		}

		Write-Log "Completed metrics for subscription: $subscriptionId"
	}
	catch {
		Write-Log "ERROR collecting metrics for subscription $subscriptionId: $_" -Level "ERROR"
	}
}

Write-Log "=== PHASE 2 SUMMARY ===" -Level "INFO"
Write-Log "Total metrics collected: $metricCount"
Write-Log "Resources with metric data: $metricsCollected"
Write-Log "Metric errors/warnings: $metricErrors"

$metricsPath = "$out/resource-metrics.json"
$metrics | ConvertTo-Json -Depth 6 | Set-Content -Encoding utf8 $metricsPath -ErrorAction Stop
Write-Log "Metrics saved to: $metricsPath"

# ============================================
# PHASE 3: Collect Activity Logs
# ============================================
Write-Log "=== PHASE 3: Activity Log Collection ===" -Level "INFO"
$activity = [System.Collections.Generic.List[object]]::new()
$activityCount = 0
$activityErrors = 0

foreach ($sub in $activeSubscriptions) {
	$subscriptionId = $sub.Id
	$subscriptionName = $sub.Name

	try {
		Write-Log "Collecting activity logs for $subscriptionName"
		Set-AzContext -SubscriptionId $subscriptionId -ErrorAction Stop | Out-Null

		# Get activity logs with pagination
		$eventLogs = @()
		$skipToken = $null
		$pageCount = 0

		do {
			try {
				$pageEvents = Get-AzActivityLog `
					-StartTime $start `
					-EndTime $end `
					-WarningAction SilentlyContinue `
					-ErrorAction Stop

				if ($pageEvents) {
					$eventLogs += $pageEvents
					$pageCount++
				}
				else {
					break
				}
			}
			catch {
				Write-Log "WARNING: Error retrieving activity log page for $subscriptionName (page $pageCount): $_" -Level "WARN"
				break
			}
		} while ($pageEvents.Count -gt 0)

		Write-Log "Retrieved $($eventLogs.Count) activity events from $subscriptionName (in $pageCount pages)"

		foreach ($e in $eventLogs) {
			try {
				$activityRecord = [pscustomobject]@{
					timeGeneratedUtc = $e.EventTimestamp.ToUniversalTime().ToString("o")
					subscriptionId = $subscriptionId
					subscriptionName = $subscriptionName
					resourceId = $e.ResourceId
					resourceGroup = $e.ResourceGroupName
					resourceName = if ($e.ResourceId) { ($e.ResourceId -split "/")[-1] } else { "N/A" }
					operationName = $e.OperationName.Value
					activityStatus = $e.Status.Value
					caller = $e.Caller
					category = $e.Category.Value
				}
				$activity.Add($activityRecord)
				$activityCount++
			}
			catch {
				$activityErrors++
				Write-Log "ERROR processing activity record: $_" -Level "ERROR"
			}
		}
	}
	catch {
		Write-Log "ERROR collecting activity logs from $subscriptionName ($subscriptionId): $_" -Level "ERROR"
	}
}

Write-Log "=== PHASE 3 SUMMARY ===" -Level "INFO"
Write-Log "Total activity records collected: $activityCount"
Write-Log "Activity errors: $activityErrors"

$activityPath = "$out/activity-log.json"
$activity | ConvertTo-Json -Depth 5 | Set-Content -Encoding utf8 $activityPath -ErrorAction Stop
Write-Log "Activity logs saved to: $activityPath"

# ============================================
# PHASE 4: Aggregate Summary
# ============================================
Write-Log "=== PHASE 4: Generating Aggregated Summary ===" -Level "INFO"

$summary = [pscustomobject]@{
	collectionTime = (Get-Date).ToUniversalTime().ToString("o")
	mode = $Mode
	dateRange = @{
		start = $start.ToString("o")
		end = $end.ToString("o")
	}
	subscriptionsScanned = $activeSubscriptions.Count
	subscriptions = @($activeSubscriptions | Select-Object @{Name="id";Expression={$_.Id}}, @{Name="name";Expression={$_.Name}}, @{Name="state";Expression={$_.State}})
	resourcesCollected = @{
		total = $resourceCount
		bySubscription = $($resources | Group-Object -Property subscriptionName | ForEach-Object { [pscustomobject]@{ name = $_.Name; count = $_.Count } })
		byResourceType = $($resources | Group-Object -Property resourceType | ForEach-Object { [pscustomobject]@{ type = $_.Name; count = $_.Count } } | Sort-Object -Property count -Descending | Select-Object -First 10)
		byLocation = $($resources | Group-Object -Property location | ForEach-Object { [pscustomobject]@{ location = $_.Name; count = $_.Count } } | Sort-Object -Property count -Descending | Select-Object -First 10)
		byServiceCategory = $($resources | Group-Object -Property serviceCategory | ForEach-Object { [pscustomobject]@{ category = $_.Name; count = $_.Count } })
	}
	metricsCollected = @{
		total = $metricCount
		resourcesWithMetrics = $metricsCollected
		errors = $metricErrors
	}
	activityLogsCollected = @{
		total = $activityCount
		errors = $activityErrors
	}
	files = @{
		inventory = "resource-inventory.json"
		metrics = "resource-metrics.json"
		activityLog = "activity-log.json"
		summary = "summary.json"
	}
}

$summaryPath = "$out/summary.json"
$summary | ConvertTo-Json -Depth 10 | Set-Content -Encoding utf8 $summaryPath -ErrorAction Stop
Write-Log "Summary saved to: $summaryPath"

# ============================================
# Final Summary
# ============================================
Write-Log "=== COLLECTION COMPLETE ===" -Level "INFO"
Write-Log "Mode: $Mode | Date Range: $($start.ToShortDateString()) to $($end.ToShortDateString())"
Write-Log "Subscriptions: $($activeSubscriptions.Count) | Resources: $resourceCount | Metrics: $metricCount | Activity: $activityCount"
Write-Log "Output files created in: $out"
Write-Log "  - resource-inventory.json (All resources across subscriptions)"
Write-Log "  - resource-metrics.json (Usage metrics)"
Write-Log "  - activity-log.json (Azure Activity Logs)"
Write-Log "  - summary.json (Aggregated summary)"
Write-Log "Completed JSON collection: $Mode" -Level "SUCCESS"
Write-Host "Completed JSON collection from ALL accessible subscriptions: $Mode" -ForegroundColor Green
