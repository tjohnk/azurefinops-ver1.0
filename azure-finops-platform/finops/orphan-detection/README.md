# Orphaned Resources module

Includes detection for:
- Unattached managed disks
- Unassociated public IPs
- Unattached NICs
- Empty App Service Plans
- Empty Load Balancers
- Empty Application Gateways
- Unassociated NAT Gateways
- Empty Private Endpoints

The module enriches candidates with 90-day cost and produces confidence, age, dependency and remediation fields.

Safety: no automatic deletion. Human review and an approved workflow are required before remediation.
