# Usage classification

UsageStatus on ResourceUsageFact must be one of exactly four values:

Active: meaningful resource-specific activity within the configured activity window.
LowUsage: some activity observed, but below the service-specific threshold (e.g. a VM
  under 5% average CPU, an App Service with a handful of requests/day). Distinguishing
  LowUsage from Active is what powers the "Low Usage" tile on the Overview dashboard —
  without it, the Overview and Usage & Activity pages will disagree on resource counts.
Inactive: no meaningful activity for the configured threshold.
NeverUsed: no observed activity since creation/first collection.
90+ Days Inactive: last meaningful activity is more than 90 days old (a derived view over
  Inactive/NeverUsed by LastActivityUtc, not a fifth UsageStatus value).

Rules must be service-specific — a "Low Usage" VM and a "Low Usage" Storage Account need
different signals and thresholds. Do not delete resources solely because a rule marks them
inactive. Orphan status is intentionally NOT a UsageStatus value — it is tracked separately
in OrphanResourceFact and joined in at query time (see OverviewController), since a resource
can be both actively-used by one metric and orphaned by dependency (e.g. an unattached disk
that still shows recent snapshot activity).
