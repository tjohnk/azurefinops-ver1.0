# Deployment

1. Create ADLS Gen2 and ADX.
2. Apply adx/schema.csl.
3. Configure JSON ingestion into ADX.
4. Populate variables/environments/<tenant>/subscriptions.json.
5. Create the Azure DevOps WIF service connection.
6. Assign collection permissions to Sandbox, Dev, Staging and Production.
7. Run and validate the baseline collection.
8. Register the portal application in Microsoft Entra ID.
9. Deploy the ASP.NET Core API to App Service.
10. Deploy the React frontend.
11. Enable App Service Entra authentication.
12. Grant the App Service managed identity read-only ADX access.
13. Configure Application Insights.
14. Add production network controls required by your security baseline.
15. Test the Overview, Services, Resources, Cost and Health modules.
16. Enable the scheduled collector after validation.
