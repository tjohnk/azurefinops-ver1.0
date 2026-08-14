# Deployment

1. Apply orphan-schema.csl to ADX.
2. Ensure ResourceInventory includes dynamic resource properties.
3. Ensure CostAnalysisFact contains ResourceId and cost.
4. Run `scripts/Invoke-OrphanDetection.ps1` after inventory and cost ingestion — this executes `orphan-rules.kql` against ADX and appends the result into OrphanResourceFact directly. Already wired into `pipeline/azure-adoption-no-csv.yml` (`EnrichFinOps` stage); running the raw KQL by hand or a separate materialization step is no longer necessary.
5. Grant the web app managed identity read access to OrphanResourceFact.
6. Deploy the Orphans API controller.
7. Add OrphansPage.tsx to the React navigation and import its CSS.
8. Test Sandbox, Dev, Staging and Production filters.
9. Integrate Azure DevOps work-item creation only after authorization/field mapping is approved.

Never auto-delete based only on an orphan classification.
