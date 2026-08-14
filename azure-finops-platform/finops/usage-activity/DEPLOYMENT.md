# Deployment

1. Apply `usage-schema.csl` to the ADX database.
2. Collect Resource Graph inventory and Azure Monitor metrics into ResourceUsageFact.
3. Collect Azure Activity Logs into AzureActivityFact.
4. Collect Azure DevOps deployment activity into DeploymentActivityFact.
5. Collect Resource Health into ResourceHealthFact.
6. Run the KQL in `usage-reports.kql` for validation and dashboard APIs.
7. Deploy `UsageActivityController.cs` in the ASP.NET Core API.
8. Add `UsageActivityPage.tsx` and `usage.css` to the React portal.
9. Add the Usage & Activity tab to the main navigation.
10. Test Sandbox, Dev, Staging and Production filtering.
11. Validate activity classifications against service-specific Azure Monitor metrics.

Use managed identity/workload identity federation for collection. Keep Azure access behind the backend API.
