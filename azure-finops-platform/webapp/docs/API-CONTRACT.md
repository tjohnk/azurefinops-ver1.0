# API contract

All routes require an authenticated bearer token (Microsoft Entra ID). The React
client must call this API only — it must never hold Azure credentials or query
ADX/Azure directly. Every list-style endpoint accepts `environment` (or `e`) as
an optional query parameter: `All | Sandbox | Dev | Staging | Production`.

## Overview — `OverviewController`
- `GET /api/overview?environment=Production` — adoption counts (Active / LowUsage / NoUsage / Orphaned) and AdoptionPercent — this is the "Resources by Status" panel
- `GET /api/overview/top-services?environment=&top=10` — Top N services by resource count
- `GET /api/overview/service-adoption?environment=&top=10` — % Active resources per service
- `GET /api/overview/locations?environment=&top=10` — resource count by Azure region

## FinOps — `FinOpsController`
- `GET /api/finops/scorecard` — spend + potential/realized savings by environment
- `GET /api/finops/anomalies` — open cost anomalies
- `GET /api/finops/optimization` — optimization pipeline summary
- `GET /api/finops/governance` — tag compliance and owner coverage by environment

## Usage & Activity — `UsageActivityController`
- `GET /api/usage/overview`, `/last-activity`, `/environment`, `/adoption`, `/never-used`,
  `/inactive`, `/trend?days=90`, `/identities`, `/failures`, `/changes`, `/deployments`,
  `/vm-utilization`, `/app-service`, `/storage`, `/sql`, `/health`, `/heatmap`,
  `/environment-service`, `/usage-cost`

## Cost Analysis — `CostAnalysisController`
- `GET /api/cost/overview`, `/trend?days=90`, and the other report endpoints listed in
  `finops/cost-analysis/README.md` (Cost by Environment/Service/Resource/Resource Group/
  Application/Business Unit/Owner, Unallocated, Anomalies, Budget vs Actual, Forecast,
  SKU, Region, Compute/Storage/Networking/Monitoring, Cost Increases, Environment x Service)

## Orphaned Resources — `OrphansController` / `OrphanActionsController`
- `GET /api/orphans/summary`, `/by-environment`, `/by-type`, `/age`, `/top`,
  `/resource/{resourceId}`
- `POST /api/orphans/actions/work-item-request` — returns a `READY_FOR_ADO_INTEGRATION`
  payload; does not create the work item itself (see GAP-ANALYSIS.md)

## Not yet implemented
`Resources`, `Recommendations`, `Service Adoption`, `Reports`, and `Data Dictionary` appear
in the left nav (`webapp/frontend/src/main.tsx`) but have no dedicated controller yet — the
React app currently falls back to the Overview page for these. See GAP-ANALYSIS.md.
