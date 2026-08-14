#!/usr/bin/env pwsh
<#
.SYNOPSIS
Load tenant configuration from centralized variables folder

.DESCRIPTION
This helper function reads tenant configuration from the variables folder structure
and exports it for use in PowerShell scripts.

.PARAMETER TenantName
The tenant name/folder path under variables/environments/

.PARAMETER ConfigPath
Optional override for the base configuration path (default: ./variables)

.EXAMPLE
$config = Import-TenantConfig -TenantName "my-tenant"
$adxCluster = $config.adx.clusterUrl
#>

function Import-TenantConfig {
	[CmdletBinding()]
	param(
		[Parameter(Mandatory = $true)]
		[string]$TenantName,

		[Parameter(Mandatory = $false)]
		[string]$ConfigPath = "./variables"
	)

	$ErrorActionPreference = "Stop"

	# Log function
	function Write-ConfigLog {
		param([string]$Message, [string]$Level = "INFO")
		Write-Host "[$Level] [CONFIG] $Message" -ForegroundColor Cyan
	}

	try {
		Write-ConfigLog "Loading configuration for tenant: $TenantName"

		# Resolve config path
		$configDir = Resolve-Path $ConfigPath -ErrorAction Stop
		Write-ConfigLog "Config directory: $configDir"

		# Load shared configs (service and metric mappings)
		$sharedDir = Join-Path $configDir "shared"
		if (-not (Test-Path $sharedDir)) {
			throw "Shared configuration directory not found: $sharedDir"
		}

		Write-ConfigLog "Loading shared mappings..."
		$serviceMapping = Get-Content (Join-Path $sharedDir "service-mapping.json") -Raw | ConvertFrom-Json
		$metricMapping = Get-Content (Join-Path $sharedDir "metric-mapping.json") -Raw | ConvertFrom-Json

		# Load tenant-specific config
		$tenantDir = Join-Path $configDir "environments" $TenantName
		if (-not (Test-Path $tenantDir)) {
			throw "Tenant directory not found: $tenantDir"
		}

		Write-ConfigLog "Loading tenant-specific configuration from: $tenantDir"

		# Try to load tenant-config.json or config.json
		$tenantConfigFile = @(
			(Join-Path $tenantDir "config.json"),
			(Join-Path $tenantDir "tenant-config.json")
		) | Where-Object { Test-Path $_ } | Select-Object -First 1

		if (-not $tenantConfigFile) {
			throw "No configuration file found in $tenantDir (expected config.json or tenant-config.json)"
		}

		$tenantConfig = Get-Content $tenantConfigFile -Raw | ConvertFrom-Json

		# Load subscriptions
		$subsFile = Join-Path (Join-Path $configDir "environments") "subscriptions.json"
		if (-not (Test-Path $subsFile)) {
			throw "Subscriptions file not found: $subsFile"
		}

		$subscriptions = Get-Content $subsFile -Raw | ConvertFrom-Json

		# Build comprehensive config object
		$config = @{
			tenantName         = $TenantName
			tenantId           = $tenantConfig.tenantId
			storage            = $tenantConfig.storage
			adx                = $tenantConfig.adx
			webapp             = $tenantConfig.webapp
			subscriptions      = $subscriptions.subscriptions
			serviceMapping     = $serviceMapping
			metricMapping      = $metricMapping
			configPath         = $configDir
		}

		Write-ConfigLog "Configuration loaded successfully" -Level "SUCCESS"
		Write-ConfigLog "Tenant ID: $($config.tenantId)"
		Write-ConfigLog "Storage: $($config.storage.accountName)"
		Write-ConfigLog "ADX Cluster: $($config.adx.clusterUrl)"
		Write-ConfigLog "Subscriptions found: $($config.subscriptions.Count)"

		return $config
	}
	catch {
		Write-Host "ERROR loading configuration: $_" -ForegroundColor Red
		throw
	}
}

Export-ModuleMember -Function Import-TenantConfig
