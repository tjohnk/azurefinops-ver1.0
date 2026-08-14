# Recommended live ingestion

Azure Resource Graph:
- resource inventory, properties, subscription and environment mapping

Azure Monitor:
- VM CPU/memory/network
- App Service requests and failures
- Function invocations
- Storage transactions
- SQL utilization

Azure Activity Log:
- create/update/delete
- start/stop/deallocate/restart
- administrative operations
- caller and operation status

Azure DevOps:
- pipeline/deployment runs
- repository, branch, requested-by, result

Resource Health:
- availability and health state

The browser should never query these services directly. Collect/normalize into ADX and expose authenticated API endpoints.
