# Azure Estate FinOps Intelligence Platform

A tenant-agnostic platform for monitoring, analyzing, and optimizing Azure infrastructure
cost and resource utilization across Sandbox, Dev, Staging, and Production subscriptions.

PowerShell collection scripts pull inventory, metrics, cost, and activity data from Azure,
land it as JSON, and feed Azure Data Explorer (ADX). An ASP.NET Core API queries ADX with
role-based security, and a React portal renders it. No Power BI license is required.

> **New to this repo?** Read `GAP-ANALYSIS.md` first. This repo was consolidated from four
> separately-generated packages (a base platform plus three feature modules), and that file
> documents what was reconciled, what was fixed, and what's still open before this is truly
> production-ready end to end.

## Architecture

```
Azure subscriptions (Sandbox / Dev / Staging / Production)
        |
        v
Azure DevOps pipeline (Workload Identity Federation, read-only)
        |
        v
PowerShell collection  --  Resource Graph | Monitor | Activity Log | Cost Management | Advisor
        |
        v
ADLS Gen2 (raw JSON landing)
        |
        v
Azure Data Explorer  --  see adx/schema.csl for the full table set
        |
        v
ASP.NET Core API (Entra ID auth, read-only managed identity to ADX)
        |
        v
React portal (Azure App Service)
```

See `ARCHITECTURE.md` for the full breakdown, and `finops/docs/FINOPS-CAPABILITY-MAP.md` for
how this maps onto the FinOps Framework (Inform / Optimize / Operate).

## Author

All code, scripts, and documentation in this repo were written by Black Box Infra team with Claude and other AI based tools. The following are the primary points of contact for this platform:

Appllication Onwer  - Tom John Kokkadan

Platform point of Contact - Ankit Saraswat

Code review and Sanity checks performed by - Rahul Basu

## Azure services used

Compiled directly from the scripts, Bicep, and controllers — not a planning list.

**Data collection (PowerShell → Azure APIs):**

| Service | Used for | Where |
|---|---|---|
| Azure Resource Graph | Resource inventory across subscriptions | `Run-Dynamic-Assessment.ps1` |
| Azure Monitor (Metrics) | CPU, requests, transactions per resource | `Run-Dynamic-Assessment.ps1` |
| Azure Activity Log | Who did what, when, per resource | `Run-Dynamic-Assessment.ps1` |
| Azure Cost Management | Daily cost by resource/service/SKU | `Run-Dynamic-Assessment.ps1` |
| Azure Advisor | Built-in cost/security/reliability recommendations | `Run-Dashboard-Assessment.ps1` |
| Azure Consumption (Budgets) | Real subscription budgets | `Collect-CostBudgets.ps1` |
| Azure Resource Health | Per-resource availability status | `Collect-ResourceHealth.ps1` |

**Storage & analytics:**

| Service | Used for |
|---|---|
| Azure Data Lake Storage Gen2 (ADLS) | Raw JSON landing zone before ingestion |
| Azure Data Explorer (ADX / Kusto) | The entire analytics backend — every Fact table, every report query |

**Hosting & identity:**

| Service | Used for |
|---|---|
| Azure App Service (Linux) | Hosts the .NET API and the React portal |
| Microsoft Entra ID | Portal sign-in, and Workload Identity Federation for the pipeline (no stored credentials) |
| Azure Monitor (Diagnostic Settings) | App Service HTTP/console/platform logs |

**Adjacent, not strictly "Azure":**
- Azure DevOps — the pipeline itself, and the source for Deployment Activity data (`Collect-DeploymentActivity.ps1`)

**Referenced conceptually but not yet integrated:**
- Azure Policy — `FinOpsGovernanceFact.PolicyState` exists as a column but is intentionally left `"NotEvaluated"` — nothing calls the Policy compliance API yet (see `GAP-ANALYSIS.md`)
- Azure Key Vault — not used at all; Workload Identity Federation throughout means there are no secrets/keys to store

## Modules

| Module | Controller | Frontend page | ADX tables |
|---|---|---|---|
| Overview | `OverviewController` | `main.tsx` (`OverviewPage`) | `ResourceUsageFact`, `OrphanResourceFact` |
| FinOps scorecard | `FinOpsController` | — | `CostAnalysisFact`, `FinOpsOptimizationFact`, `CostAnomalyFact`, `FinOpsGovernanceFact` |
| Usage & Activity | `UsageActivityController` | `UsageActivityPage.tsx` | `ResourceUsageFact`, `AzureActivityFact`, `DeploymentActivityFact`, `ResourceHealthFact` |
| Cost Analysis | `CostAnalysisController` | `CostAnalysisPage.tsx` | `CostAnalysisFact`, `CostBudgetFact`, `CostForecastFact`, `CostAnomalyFact` |
| Orphaned Resources | `OrphansController`, `OrphanActionsController` | `OrphansPage.tsx` | `OrphanResourceFact` |

Each module also has its own README/DEPLOYMENT notes under `finops/<module>/`.

## Repository layout

```
adx/                  Canonical ADX schema (schema.csl) and ingestion notes
finops/                FinOps framework: governance, runbooks, KPIs, capability map,
                       plus one folder per module (cost-analysis, usage-activity,
                       orphan-detection) with that module's README/DEPLOYMENT/KQL
pipeline/              Azure DevOps pipeline (azure-adoption-no-csv.yml)
scripts/               PowerShell collection scripts (tenant-agnostic, config-driven) —
                       includes budget/forecast/anomaly/orphan-detection scripts that
                       derive from data already in ADX rather than re-fetching it
variables/             Tenant configuration — see variables/README.md
webapp/backend/        ASP.NET Core API (.NET 8), one Controllers/<Module> folder per module
webapp/frontend/       React + Vite portal
webapp/infra/          Bicep for the App Service (ADX cluster is a separate prerequisite —
                       see GAP-ANALYSIS.md)
GAP-ANALYSIS.md         What was found and fixed during consolidation, and what remains
ARCHITECTURE.md         Full architecture, data flow, and security model
DEPLOYMENT.md           End-to-end deployment checklist
```

## Onboarding a new tenant

This repo is written to be tenant-agnostic — no organization-specific values are hardcoded
anywhere in code, Bicep, or the pipeline. Every existing Azure service this platform touches
(ADX cluster, its resource group, the ADLS storage account and its resource group, the App
Service name and its resource group, the Entra tenant and app registration) is a value in
`variables/environments/<tenant-name>/config.json` — the pipeline's `Validate` stage loads
that file and passes every value on to the stages that need it. There is no separate Azure
DevOps variable group to keep in sync with it.

```powershell
# 1. Copy the template
Copy-Item variables/templates/tenant-template.json variables/environments/<tenant-name>/config.json
Copy-Item variables/environments/example-corp/subscriptions.json variables/environments/<tenant-name>/subscriptions.json

# 2. Fill in the <REPLACE-...> placeholders in both files with your EXISTING Azure
#    service names — this repo does not create an ADX cluster or storage account for
#    you (see GAP-ANALYSIS.md); it expects them to already exist and just needs their
#    names/resource groups/URLs.

# 3. Test locally
Import-Module scripts/ConfigHelper.psm1 -Force
$config = Import-TenantConfig -TenantName "<tenant-name>"

# 4. Run a Baseline collection
./scripts/Run-Dashboard-Assessment.ps1 -Mode Baseline -ConfigPath "variables"
```

Then run the pipeline (`pipeline/azure-adoption-no-csv.yml`) with `tenantName: <tenant-name>`.
`variables/environments/example-corp/` is a worked example with fake GUIDs — copy it, don't
edit it in place.

## Local development and mock ADX

If you do not have an ADX cluster available, or want to iterate quickly on UI/API changes,
run the backend in `Development` to use the repository's mock ADX service and sample payloads.

1. Start the backend (Development mode):
   ```powershell
   $env:ASPNETCORE_ENVIRONMENT='Development'
   $env:ASPNETCORE_URLS='http://localhost:5001'
   dotnet run --project .\webapp\backend\AzureEstate.Api.csproj
   ```
   In this mode, API endpoints return stable mock JSON from `webapp/backend/mock/data/*.json`.

2. Start the frontend:
   ```bash
   cd webapp/frontend
   npm install
   npm run dev
   ```
   The frontend expects the API at `http://localhost:5001` with the backend command above.

3. Key local-test files:
   - `webapp/backend/Services/MockAdxService.cs` (development mock for ADX-backed queries)
   - `webapp/backend/mock/data/*.json` (sample fact payloads used by the mock service)

### Required steps to populate real ADX data

Mock mode is for development only. For real dashboards and metrics, you must run collection
and ingestion against your tenant:

1. Configure tenant files under `variables/environments/<tenant-name>/`.
2. Run collectors (pipeline or local scripts) to produce JSON snapshots.
3. Land data in ADLS Gen2.
4. Ingest into ADX using the schema in `adx/schema.csl`.
5. Repeat on schedule so trend/anomaly/forecast views have enough history.

### Caveats

- Forecast views need sufficient historical cost data (typically ~30 days minimum).
- Anomaly and orphan-enrichment outputs depend on scheduled runs; one-time baseline runs are not enough.
- Budget/cost collection is currently USD-oriented; multi-currency tenants may need conversion logic.
- `FinOpsGovernanceFact.PolicyState` is intentionally `"NotEvaluated"` until Policy API integration is added.
- `OrphanResourceFact.AdoWorkItemId` remains empty unless optional ADO work-item automation is implemented.

## Deploying via Azure DevOps

See `DEPLOYMENT.md` for the full checklist. In short: the pipeline has five stages —
Validate, Collect, LandAndIngest, BuildWebApp, DeployToProduction — and runs daily by
default (`runMode: Daily`, cron `0 2 * * *`). Trigger it manually with a different
`runMode` (`Baseline`, `Hourly`, `Weekly`) as needed; the schedule and the default mode are
independent, so changing one doesn't change the other.

The pipeline uses two separate service connections on purpose: `sc-azure-adoption-wif` is
read-only across the tenant's subscriptions and is used only for collection, while
`sc-azure-adoption-writer` is used only to deploy the built API and never touches the
tenant's Azure resources being monitored.

## What's deferred

Azure OpenAI-generated narrative summaries (an "AI insights" layer on top of the collected
data) were discussed during design but are explicitly **not** part of this build — planned
as a later stage, once there's enough collection history for a summary to be meaningful.

## Roadmap for the modules not yet built

`Resources`, `Recommendations` (beyond FinOps optimization), `Service Adoption` (beyond
Usage & Activity's adoption endpoint), `Reports`, and `Data Dictionary` are present in the
portal's left navigation but don't have a dedicated backend module yet.
