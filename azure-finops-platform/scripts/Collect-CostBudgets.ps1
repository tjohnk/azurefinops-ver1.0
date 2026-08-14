<#
.SYNOPSIS
Collects Azure consumption budgets for every accessible subscription and writes them as
ADX-ready JSON matching the CostBudgetFact schema.

.DESCRIPTION
Unlike forecast and anomaly detection, budgets aren't something to derive from cost
history already in ADX — they're a resource you define directly in Azure (via the Portal,
`New-AzConsumptionBudget`, or a Bicep/ARM template) and this script's only job is to read
them and shape them to match CostBudgetFact. Before this script existed, CostBudgetFact had
a schema and CostAnalysisController's /budget endpoint queried it, but nothing populated it.

Output lands at $root/output/adx/adx-cost-budget.json, following the same convention as
the other adx-*.json files Run-Dashboard-Assessment.ps1 produces — pick it up with
Upload-Json-ToStorage.ps1 and the pipeline's existing ingestion step the same way.

.PARAMETER TenantName
Tenant folder name under variables/environments/ — used only to resolve environment names
from subscription names via the same heuristic Run-Dynamic-Assessment.ps1 uses (tag or
name pattern matching prod/staging/dev/sandbox). If your subscriptions don't follow that
naming convention, the Environment column will read "Unclassified" — tag your subscriptions
or budgets with an Environment tag to fix that, rather than relying on name-matching alone.

.EXAMPLE
./Collect-CostBudgets.ps1 -TenantName "default" -ConfigPath "variables"
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
    $root = Split-Path $PSScriptRoot -Parent
    Import-Module "$PSScriptRoot/ConfigHelper.psm1" -Force
    Import-Module "$PSScriptRoot/DashboardDataHelper.psm1" -Force
    Import-Module Az.Accounts -ErrorAction Stop
    Import-Module Az.Consumption -ErrorAction Stop

    # Confirms the tenant exists and is configured, even though this script only needs
    # Azure AD auth (already established by the pipeline's service connection) — keeps
    # the same "fail fast on bad tenant config" behavior as every other collection script.
    Import-TenantConfig -TenantName $TenantName -ConfigPath $ConfigPath | Out-Null

    $subscriptions = Get-AzSubscription -ErrorAction Stop | Where-Object { $_.State -eq "Enabled" }
    Write-Log "Found $($subscriptions.Count) active subscriptions"

    $budgetRows = [System.Collections.Generic.List[object]]::new()

    foreach ($sub in $subscriptions) {
        try {
            Set-AzContext -SubscriptionId $sub.Id -ErrorAction Stop | Out-Null
            $budgets = Get-AzConsumptionBudget -ErrorAction Stop
            Write-Log "Subscription $($sub.Name): $($budgets.Count) budget(s)"

            $pseudoResource = [pscustomobject]@{ subscriptionName = $sub.Name; resourceGroup = ""; resourceName = "" }
            $environment = Get-EnvironmentNameFromResource -Resource $pseudoResource

            foreach ($b in $budgets) {
                $currency = if ($b.CurrentSpend -and $b.CurrentSpend.Unit) { [string]$b.CurrentSpend.Unit } else { "USD" }
                if ($currency -ne "USD") {
                    Write-Log "Skipping budget '$($b.Name)' in subscription $($sub.Name) because currency '$currency' is not USD" -Level "WARN"
                    continue
                }

                $warningPercent = 80.0
                $criticalPercent = 100.0
                if ($b.Notification -and $b.Notification.Count -gt 0) {
                    $thresholds = @($b.Notification.Values | ForEach-Object { [double]$_.Threshold } | Sort-Object)
                    if ($thresholds.Count -ge 1) { $warningPercent = $thresholds[0] }
                    if ($thresholds.Count -ge 2) { $criticalPercent = $thresholds[-1] }
                }

                $budgetRows.Add([pscustomobject]@{
                    ScopeId         = "/subscriptions/$($sub.Id)"
                    ScopeType       = "Subscription"
                    Environment     = $environment
                    BudgetName      = $b.Name
                    PeriodStart     = ([datetime]$b.TimePeriod.StartDate).ToString("yyyy-MM-dd")
                    PeriodEnd       = if ($b.TimePeriod.EndDate) { ([datetime]$b.TimePeriod.EndDate).ToString("yyyy-MM-dd") } else { $null }
                    BudgetAmount    = [double]$b.Amount
                    Currency        = "USD"
                    WarningPercent  = $warningPercent
                    CriticalPercent = $criticalPercent
                })
            }
        }
        catch {
            Write-Log "WARNING: Could not read budgets for subscription $($sub.Name): $_" -Level "WARN"
        }
    }

    $outDir = Join-Path $root "output/adx"
    New-Item -ItemType Directory -Force -Path $outDir | Out-Null
    $outPath = Join-Path $outDir "adx-cost-budget.json"
    $budgetRows | ConvertTo-Json -Depth 10 | Set-Content -Path $outPath -Encoding utf8

    Write-Log "Wrote $($budgetRows.Count) budget row(s) to $outPath" -Level "SUCCESS"
}
catch {
    Write-Log "FATAL: Budget collection failed: $_" -Level "ERROR"
    exit 1
}
