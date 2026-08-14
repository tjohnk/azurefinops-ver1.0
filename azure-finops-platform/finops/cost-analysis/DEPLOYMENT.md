# Deployment

1. Apply `cost-schema.csl` to the AzureAdoption ADX database.
2. Populate CostAnalysisFact from Azure Cost Management export/FOCUS-compatible cost data or your approved cost ingestion source (already automated — `scripts/Run-Dashboard-Assessment.ps1`).
3. Populate CostBudgetFact by running `scripts/Collect-CostBudgets.ps1` (reads real Azure consumption budgets via `Get-AzConsumptionBudget`) and CostForecastFact by running `scripts/Collect-CostForecast.ps1` (derives a trend forecast from cost history already in ADX — see `forecast-rule.kql` for the methodology). Both are wired into `pipeline/azure-adoption-no-csv.yml`.
4. Populate CostAnomalyFact by running `scripts/Detect-CostAnomalies.ps1` (baseline-deviation detection over cost history already in ADX — see `anomaly-rule.kql`). Also wired into the pipeline (`EnrichFinOps` stage).
5. Deploy `CostAnalysisController.cs`.
6. Add `CostAnalysisPage.tsx` and `cost.css` to the React app.
7. Add `Cost Analysis` to the main portal navigation.
8. Grant the web app managed identity read access to the required ADX tables.
9. Test the four environment filters.
10. Validate cost totals against Azure Cost Management before production use.

The web client must not query Azure Cost Management or ADX directly; all queries should go through the authenticated API.
