# Runbook — Populate ADX and validate reports

This runbook shows the minimal steps to populate ADX tables and validate the reports in a sandbox tenant.

Prerequisites
- An Azure subscription with permissions to read Resource Graph, Cost, Monitor, and Activity Log.
- An ADX cluster and database (the repo does not create these).
- A service principal or managed identity that the pipeline can use to ingest into ADX.

1) Provision/verify ADX and ADLS
- Ensure ADX cluster exists and you have its URL (https://<cluster>.<region>.kusto.windows.net) and a database name.
- Grant the pipeline identity permissions to ingest (.ingest) and the web app managed identity Data Reader permissions on the DB.

2) Configure tenant variables
- Copy variables/templates/tenant-template.json to variables/environments/<tenant>/config.json and fill values.
- Ensure ADX:ClusterUrl and ADX:Database are correct.

3) Run baseline collection (inventory + metrics + cost)
- From repo root run (PowerShell):
  Import-Module scripts/ConfigHelper.psm1 -Force
  ./scripts/Run-Dashboard-Assessment.ps1 -Mode Baseline -ConfigPath "variables/environments/<tenant>/config.json"

4) Upload JSON to ADLS and ingest to ADX (pipeline)
- Run pipeline/azure-adoption-no-csv.yml in Azure DevOps or execute the ingestion scripts locally following pipeline/DEPLOYMENT.md.

5) Run enrichment rules
- Invoke orphan detection:
  ./scripts/Invoke-OrphanDetection.ps1 -ConfigPath "variables/environments/<tenant>/config.json"
- Detect cost anomalies:
  ./scripts/Detect-CostAnomalies.ps1 -ConfigPath "variables/environments/<tenant>/config.json"
- Run forecast derivation:
  ./scripts/Collect-CostForecast.ps1 -ConfigPath "variables/environments/<tenant>/config.json"
- Collect budgets:
  ./scripts/Collect-CostBudgets.ps1 -ConfigPath "variables/environments/<tenant>/config.json"

6) Verify ADX tables have rows
- Query ADX or use Kusto.Explorer. Minimal checks:
  ResourceUsageFact | summarize count()
  CostAnalysisFact | summarize count()
  CostBudgetFact | summarize count()
  CostForecastFact | summarize count()
  CostAnomalyFact | summarize count()
  OrphanResourceFact | summarize count()

7) Validate API responses
- Call the API endpoints (replace host with deployed app):
  GET /api/orphans/summary
  GET /api/orphans/top
  GET /api/cost/overview
  GET /api/usage/trend?range=90
  GET /api/finops/scorecard

8) Validate frontend
- Build and deploy frontend or run locally with npm run dev. Ensure CORS allowed origin points to frontend.

Troubleshooting
- If a table is empty, re-run the corresponding collector and verify its logs.
- If authentication fails, ensure managed identity/service principal has necessary ADX permissions.

Security
- Do not check tenant secrets or client secrets into repo. Use pipeline variable groups or Key Vault for secrets.

Contact
- For script issues see scripts/README.md and per-module DEPLOYMENT.md under finops/.
