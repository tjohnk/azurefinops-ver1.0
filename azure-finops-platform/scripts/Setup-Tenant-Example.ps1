#!/usr/bin/env pwsh
<#
.SYNOPSIS
Example script showing how to use the new centralized configuration

.DESCRIPTION
This demonstrates loading tenant config and using it in collection scripts

.EXAMPLE
.\Setup-Tenant-Example.ps1
#>

# Import configuration helper
$rootPath = Split-Path $PSScriptRoot -Parent
Import-Module "$PSScriptRoot/ConfigHelper.psm1" -Force

try {
	# Load tenant configuration
	$config = Import-TenantConfig -TenantName "example-corp"

	Write-Host "`n=== TENANT CONFIGURATION ===" -ForegroundColor Green
	Write-Host "Tenant: $($config.tenantName)"
	Write-Host "Tenant ID: $($config.tenantId)"
	Write-Host "Storage Account: $($config.storage.accountName)"
	Write-Host "ADX Cluster: $($config.adx.clusterUrl)"
	Write-Host "Database: $($config.adx.database)"
	Write-Host ""

	Write-Host "=== SUBSCRIPTIONS ===" -ForegroundColor Green
	foreach ($sub in $config.subscriptions) {
		Write-Host "  - $($sub.subscriptionName): $($sub.subscriptionId)"
	}
	Write-Host ""

	Write-Host "=== SERVICE MAPPING SAMPLES ===" -ForegroundColor Green
	$config.serviceMapping | Select-Object -First 3 | ForEach-Object {
		Write-Host "  - $($_.serviceName) ($($_.resourceType))"
	}
	Write-Host "  ... and $($config.serviceMapping.Count - 3) more"
	Write-Host ""

	Write-Host "=== METRIC MAPPING SAMPLES ===" -ForegroundColor Green
	$config.metricMapping | Select-Object -First 3 | ForEach-Object {
		Write-Host "  - $($_.metricName) [$($_.aggregation)] on $($_.resourceType)"
	}
	Write-Host "  ... and $($config.metricMapping.Count - 3) more"
	Write-Host ""

	# Example: Use configuration in a real scenario
	Write-Host "=== EXAMPLE: CONNECT TO ADX ===" -ForegroundColor Cyan
	Write-Host "To connect to ADX in your scripts, use:"
	Write-Host "`$cluster = `$config.adx.clusterUrl"
	Write-Host "`$database = `$config.adx.database"
	Write-Host "`$kcsb = [Kusto.Data.KustoConnectionStringBuilder]::new(`$cluster)"
	Write-Host "`$kcsb = `$kcsb.WithAadManagedIdentity()"
	Write-Host ""

	Write-Host "=== EXAMPLE: ITERATE SUBSCRIPTIONS ===" -ForegroundColor Cyan
	Write-Host "foreach(`$sub in `$config.subscriptions) {"
	Write-Host "    Set-AzContext -SubscriptionId `$sub.subscriptionId"
	Write-Host "    # Your collection logic here"
	Write-Host "}"
	Write-Host ""

	Write-Host "Configuration loaded successfully! Use this pattern in your production scripts." -ForegroundColor Green
}
catch {
	Write-Host "ERROR: $_" -ForegroundColor Red
	exit 1
}
