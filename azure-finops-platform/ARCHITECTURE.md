# Architecture

## Data flow

```
Azure Sandbox / Dev / Staging / Production subscriptions
        |
        v
Azure DevOps pipeline, Workload Identity Federation (read-only identity)
        |
        v
PowerShell collection (scripts/Run-Dashboard-Assessment.ps1)
  Resource Graph | Azure Monitor | Activity Log | Cost Management | Advisor
        |
        v
ADLS Gen2  (raw JSON landing — scripts/Upload-Json-ToStorage.ps1)
        |
        v
Azure Data Explorer  (adx/schema.csl — see that file for the full table set)
        |
        v
ASP.NET Core API  (webapp/backend — Entra ID auth, one Controller per module)
        |
        v
React portal  (webapp/frontend — Azure App Service, Entra ID sign-in)
```

Power BI is not part of this architecture — the portal is the operational interface.
FinOps lifecycle: **Inform → Optimize → Operate** (see
`finops/docs/FINOPS-CAPABILITY-MAP.md`).

## Identity model

Two separate identities are used on purpose:

- **Collector identity** (`sc-azure-adoption-wif` service connection) — Reader + Cost
  Management Reader + Monitoring Reader, scoped to the tenant's Sandbox/Dev/Staging/
  Production subscriptions only. Used only by the `Collect` and `LandAndIngest` pipeline
  stages. Never has write access to the monitored subscriptions.
- **Deploy identity** (`sc-azure-adoption-writer` service connection) — used only to deploy
  the built API to App Service. Never touches the monitored subscriptions.
- **App Service managed identity** — read-only access to the ADX database, used by the API
  at runtime to serve requests. The browser never talks to ADX or Azure directly; it only
  calls the authenticated API (see `webapp/docs/API-CONTRACT.md`).

## Multi-tenancy

Tenant-specific values (tenant ID, storage account, ADX cluster, subscription IDs, App
Service name/SKU) live entirely under `variables/environments/<tenant-name>/`, loaded by
`scripts/ConfigHelper.psm1`. Nothing tenant-specific is hardcoded in code, Bicep, or the
pipeline YAML — the same repo deploys to any tenant by adding a new folder under
`variables/environments/`. `variables/shared/` holds mappings that are the same for every
tenant (service-type → category, metric definitions).

## Module boundaries

Each feature module (Usage & Activity, Cost Analysis, Orphaned Resources) owns:
- its own ADX tables in `adx/schema.csl`
- its own `Controllers/<Module>/*.cs` folder
- its own `frontend/src/<module>/` page + stylesheet
- its own `finops/<module>/` folder for KQL rules, README, and deployment notes

They share: `AdxService` (the one Kusto query client, `webapp/backend/Services/
AdxService.cs`), the Entra ID auth/CORS setup in `Program.cs`, and the left-nav shell in
`webapp/frontend/src/main.tsx` / `App.tsx`.

## Production hardening not yet in this repo

For a fully hardened enterprise deployment, layer in (not included here — see
`GAP-ANALYSIS.md` for what's genuinely still open vs. what's just not attempted):
- VNet integration / private endpoints for the App Service and ADX cluster
- Application Gateway / WAF in front of the portal
- Azure Monitor / Application Insights alerting on collector failures (the pipeline has a
  `CollectorHealth` table for this — it's ingested but nothing currently alerts on it)
