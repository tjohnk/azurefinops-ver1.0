# Deployment checklist (Azure DevOps)

This is the end-to-end checklist. Module-specific steps (already covered here, but with
extra detail per module) are in `finops/<module>/DEPLOYMENT.md`.

## 1. Prerequisites (manual, one-time per tenant)

1. Create an ADLS Gen2 storage account for raw JSON landing.
2. Create an Azure Data Explorer cluster and a database (default name `AzureAdoption`).
   **Not automated yet** — see `GAP-ANALYSIS.md`.
3. Apply `adx/schema.csl` to that database (via the ADX web UI, `Kusto.Explorer`, or the
   `Az.Kusto` PowerShell module).
4. Register an Entra ID app for the API, and a second one for the collector (Workload
   Identity Federation, no secrets).
5. Grant the collector identity Reader + Cost Management Reader + Monitoring Reader on the
   Sandbox, Dev, Staging, and Production subscriptions — read-only, nothing more.

## 2. Tenant configuration

1. Copy `variables/templates/tenant-template.json` to
   `variables/environments/<tenant-name>/config.json` and fill in every `<REPLACE-...>`.
2. Copy `variables/environments/example-corp/subscriptions.json` to
   `variables/environments/<tenant-name>/subscriptions.json` and fill in real subscription
   IDs for Sandbox/Dev/Staging/Production.
3. Review `variables/shared/service-mapping.json` and `metric-mapping.json` — these are
   tenant-agnostic defaults; only change them if your service taxonomy differs.

## 3. Azure DevOps setup

1. Create the two service connections referenced in `pipeline/azure-adoption-no-csv.yml`:
   `sc-azure-adoption-wif` (collector, read-only) and `sc-azure-adoption-writer` (deploy).
2. Import `pipeline/azure-adoption-no-csv.yml` as a pipeline, with `tenantName` set to your
   tenant folder name.

That's it for step 2 in most setups — as of the tenant-config consolidation, the pipeline's
`Validate` stage loads `ADX_CLUSTER_URL`, `ADX_CLUSTER_NAME`, `ADX_RESOURCE_GROUP`,
`ADX_DATABASE`, `AZURE_AD_TENANT_ID`, `AZURE_AD_CLIENT_ID`, `STORAGE_ACCOUNT`,
`STORAGE_RESOURCE_GROUP`, and `WEBAPP_RESOURCE_GROUP` directly from your
`variables/environments/<tenant>/config.json` and passes them to every later stage — there's
no separate Azure DevOps variable group to keep in sync with that file. Only add a variable
group if you introduce an actual secret later (there are none today; auth is Workload
Identity Federation throughout).

## 4. First run

1. Run the pipeline manually with `runMode: Baseline` and validate the `Collect` stage
   output (`output/adx/*.json`) before trusting a scheduled run.
2. Confirm `LandAndIngest` actually lands JSON in ADLS (`Upload-Json-ToStorage.ps1` step) —
   the ADX ingestion step itself is still a stub; see `GAP-ANALYSIS.md` before expecting
   data to show up in ADX automatically.
3. Once ingestion is wired up, validate row counts per table against what the collector
   reported (`CollectorHealth`).

## 5. Web app

1. Deploy `webapp/infra/appservice.bicep` (App Service only — ADX is a separate
   prerequisite, see step 1.2 above).
2. Let `BuildWebApp` / `DeployToProduction` stages build and deploy the API.
3. Deploy the React frontend (`webapp/frontend`) — build with `npm run build`, publish the
   `dist/` output to the same App Service or a static hosting target of your choice.
4. Enable Entra ID sign-in on the App Service, and grant its managed identity read-only
   access to the ADX database.

## 6. Go-live

1. Test all four environment filters (Sandbox/Dev/Staging/Production) across every module
   page (Overview, Usage & Activity, Cost Analysis, Orphaned Resources).
2. Validate cost totals in the Cost Analysis page against Azure Cost Management directly
   before treating the numbers as authoritative.
3. Enable the daily schedule (already the pipeline default — see `README.md`) once the
   above all check out.
