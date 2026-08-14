# Gap Analysis — Consolidation of the four source packages

This repo was assembled from four separately AI-generated packages: a base platform
(`azure-estate-finops-intelligence-platform-pack`) and three feature-module add-ons
(Usage & Activity, Cost Analysis, Orphaned Resources). Each was built in its own session
without full visibility into the others. This document records what that produced, what
was fixed during consolidation, and what's genuinely still open.

## 1. Two incompatible generations existed side by side — resolved

The base package's zip contained a full, older, incompatible implementation nested
alongside the current one:
- A static single-file HTML dashboard (`azure-finops-dashboard.html`) fed by a
  direct-zip-deploy pipeline stage
- A second ASP.NET Core backend variant (`Program-Dynamic.cs`, `DynamicFinOpsController.cs`,
  `SubscriptionDiscoveryService.cs`) that did live ARM subscription scanning per request
  instead of querying pre-aggregated ADX data — and referenced an `AggregationService`
  class that didn't exist anywhere in the package, so it would not have compiled.

**Fix:** both were dropped. The ADX + ASP.NET Core API + React track is the only one
carried forward, since it's the one all three feature modules were actually built against.

## 2. Schema fragmentation across the four packages — resolved

Each package defined its own version of the same concepts:

| Concept | Names found | Canonical name kept |
|---|---|---|
| Cost fact | `CostFact`, `FinOpsCostFact`, `CostAnalysisFact` | `CostAnalysisFact` (most complete: adds SKU, Region, Tags) |
| Budget | `FinOpsBudgetFact`, `CostBudgetFact` | `CostBudgetFact` |
| Forecast | `FinOpsForecastFact`, `CostForecastFact` | `CostForecastFact` |
| Anomaly | `FinOpsAnomalyFact`, `CostAnomalyFact` | `CostAnomalyFact` |
| Activity | `ActivityLog`, `AzureActivityFact` | `AzureActivityFact` |

**Fix:** consolidated into one file, `adx/schema.csl`, which is now the single source of
truth (the four original `.csl` files were deleted; a `SCHEMA-MOVED.md` pointer was left in
each module folder). `finops/kql/finops-views.kql` and `FinOpsController.cs` were repointed
at the surviving table names.

## 3. `OverviewController` queried a table that was never defined — resolved

It queried `ResourceAdoptionMaster` with lowercase-camelCase columns (`usageStatus`) and
SCREAMING_CASE values (`ACTIVE`, `LOW_UTILIZATION`, `NO_USAGE`, `ORPHANED`) — a naming
convention inconsistent with every other table in the platform, and a table that doesn't
exist in any of the four source packages' schema files. The Overview tiles and the Usage &
Activity page were structurally guaranteed to disagree with each other.

**Fix:** `OverviewController` now computes its adoption breakdown directly from
`ResourceUsageFact` joined with `OrphanResourceFact`, using the platform's real
`UsageStatus` values.

## 4. The mockup's "Low Usage" tile had no matching data value — resolved

The original dashboard mockup has four resource-status tiles: Active, Low Usage, No Usage,
Orphaned. But `ResourceUsageFact.UsageStatus` only ever had three values (`Active`,
`Inactive`, `NeverUsed`) — there was no way to produce a "Low Usage" count at all.

**Fix:** added `LowUsage` as a fourth `UsageStatus` value in `finops/usage-activity/
STATUS-RULES.md`, and updated `OverviewController` and `UsageActivityController.Overview()`
to report it. **What's still open:** the PowerShell collection script that actually
populates `UsageStatus` per resource still needs the threshold logic to assign `LowUsage`
(vs `Active`) — the rule definition exists now, the classification code implementing it
does not.

## 5. Two pipeline data paths, only one connected to the new modules — resolved

The original pipeline's `PublishData` stage zip-deployed the collector's raw JSON straight
to a web app — a leftover from the static-HTML-dashboard era. Meanwhile the three new
modules are built entirely as ADX-backed API endpoints with no static-HTML equivalent, so
that stage was serving a dashboard that couldn't show any of the new modules' data.

**Fix:** removed the `PublishData` stage. Added a `LandAndIngest` stage that runs
`Upload-Json-ToStorage.ps1` and then ingestion into ADX (see item 7 below for what's still
a stub there).

## 6. Pipeline schedule didn't match the stated cadence — resolved

The cron trigger ran hourly (`0 * * * *`) while `runMode` defaulted to `Daily`. Given the
number of API calls a full Resource Graph + Cost Management + Activity Log pass makes
across four subscriptions, hourly was very likely unintentional.

**Fix:** cron changed to daily (`0 2 * * *`), independent of the `runMode` parameter so
manual `Hourly`/`Weekly`/`Baseline` runs are still possible without touching the schedule.

## 7. `appservice.bicep` existed but was never deployed by the pipeline — resolved

The Bicep template for the App Service was written and correct, but no pipeline stage ever
ran `az deployment group create` against it. The `DeployToProduction` stage's `AzureWebApp`
task just deployed code to an app named `finops-api-<tenantName>`, silently assuming that
app already existed — there was no step that actually created it, and the site's name (and
therefore its URL) wasn't a single variable anywhere; it was a literal string repeated in
two places in the pipeline.

**Fix:** added a `ProvisionInfra` stage that deploys `appservice.bicep`, added a `webAppName`
parameter (blank by default, resolving to `finops-api-<tenantName>`), and introduced one
`webAppNameResolved` pipeline variable that every stage — provisioning, code deploy, and app
settings — now reads instead of three independently hardcoded copies of the name.

**What's still open:** the React frontend build (`webapp/frontend`) still has no deploy step
in the pipeline at all — `DEPLOYMENT.md` documents building it and publishing `dist/`
manually. If it's meant to be served from the same App Service as the API, that needs a
pipeline step too.

## 8. Existing Azure services were split across a checked-in config file AND a separately
maintained Azure DevOps variable group — resolved

`variables/environments/<tenant>/config.json` already had `adx.clusterUrl`, `adx.database`,
`storage.accountName`, `webapp.name`, etc. — but the pipeline's `ProvisionInfra` and
`DeployToProduction` stages read `$(ADX_CLUSTER_URL)`, `$(AZURE_AD_TENANT_ID)`, etc. from an
Azure DevOps variable group that had to be populated separately, and the resource group name
was a third, independent thing — a hardcoded `rg-finops-<tenantName>` pattern baked into the
YAML, which breaks the moment an existing resource group doesn't happen to follow that naming
convention.

**Fix:** the tenant config file is now the single source for all of it. A new `LoadConfig`
step in the `Validate` stage reads `config.json` once and exposes every value (including two
new fields, `adx.resourceGroup` and `webapp.resourceGroup`, added to the schema) as proper
Azure DevOps **stage output variables** — which every downstream stage (`LandAndIngest`,
`ProvisionInfra`, `DeployToProduction`) now pulls in via `stageDependencies.Validate.
ValidateConfig.outputs[...]`. This is a real Azure DevOps mechanic, not just a naming
convention — a plain `##vso[task.setvariable variable=X]` (without `isOutput=true`) only
survives within the same job, so this needed the stage-output wiring, not just a rename.

`webAppName` remains an optional pipeline parameter that overrides the config's `webapp.name`
when you explicitly pass one (e.g. to stand up a parallel/staging site), but otherwise the
site name — and therefore its URL — comes entirely from the tenant config you already filled
in. Same for the ADX database name: the `adxDatabaseName` parameter was removed since
`adx.database` in config now covers it without a redundant second input.

## 9. A static, no-build preview was added — not a replacement for the real portal

`docs/preview/azure-finops-report-preview.html` is a single self-contained HTML file (open
it directly in any browser, no `npm install` needed) that reproduces the visual style of the
original mockup with working left-nav tabs for all four modules, sub-report tabs within
Usage & Activity / Cost Analysis / Orphaned Resources, and the same environment filter
pattern — but every number in it is **mock data embedded in the file**, not a live query.
It exists so the report layout and navigation can be reviewed before ADX ingestion (item 7)
and Overview's live-data wiring (also item 7) are finished. It is not built from — and will
drift from — the real React components in `webapp/frontend/src/`; once those are live, this
preview file should be deleted rather than kept in sync by hand.

## 10. Four Overview panels existed in the frontend mock but had no live endpoint
behind them, and several UI glyphs were corrupted bytes — resolved

`main.tsx` already had hardcoded mock sections for "Resources by Status," "Top 10
Services by Resource Count," "Service Adoption (% Active Resources)," and "Resources by
Location" — so they weren't structurally missing from the page, but three of the four had
**no backing API endpoint**: `OverviewController` only ever implemented the single
adoption-counts query. The underlying data was never the gap — `serviceName` and `location`
are already columns on `ResourceInventory`, collected by the existing PowerShell script via
Resource Graph — only the ADX query layer to serve them was missing.

**Fix:** added `GET /api/overview/top-services`, `/service-adoption`, and `/locations` to
`OverviewController`, querying `ResourceInventory` (joined with `ResourceUsageFact` for the
adoption-percent case) directly — no new collection script needed.

Separately, several UI glyphs in `main.tsx` were literal corrupted bytes (`\x95` for the
sidebar nav icon; bare `?` standing in for the ₹ symbol in four places and for dropdown/
calendar icons in five more) — likely lost during an earlier generation or zip/encoding
step, not an intentional gap. Replaced all of them with inline SVG icons and the correct ₹
symbol; verified the file round-trips as valid UTF-8 afterward.

## 11. The preview's charts didn't match the reference mockup's visual style — resolved

The first version of `docs/preview/azure-finops-report-preview.html` used Chart.js doughnuts
for the Overview donuts, which render a visible border between segments by default — not
present in the reference mockup, which uses plain CSS conic-gradient rings (see `RingChart`
in `webapp/frontend/src/main.tsx`). The preview's "Resources by Location" panel was also
downgraded to a plain table, dropping the stylized world-map-with-dots visual the mockup and
the real React component both use.

**Fix:** ported the real app's exact CSS (ring donuts, vertical/horizontal bar charts, and
the world-map-with-dots) directly into the preview, replacing the Chart.js versions for
Overview. Chart.js is now only used for the three new modules' trend/line charts, which have
no equivalent in the original mockup to match against; its one remaining doughnut
(Orphaned Resources' "by reason" chart) had `borderWidth:0` added for the same reason.

## 12. Preview rebuilt: full filter bar, denser layout, map made unmissable, far more
report tabs per module

Following further review, the preview was rebuilt rather than patched again:
- Added the Subscription / Resource Group / Resource Type / Date Range filter dropdowns
  next to the Environment pills — previously only the environment filter existed, missing
  the rest of the filter row the reference mockup shows.
- Tightened spacing throughout (smaller padding, gaps, font sizes) so more report content
  is visible without scrolling — the earlier version's spacing was noticeably looser than
  the reference.
- The world map is now visibly larger with glowing markers and location labels directly on
  the map, not just a hover tooltip — the previous version's map was easy to miss even
  though the markup was present.
- Usage & Activity grew from 5 to 13 sub-report tabs, Cost Analysis from 7 to 20, matching
  much closer to the real API's 18 and 18+ endpoints respectively; Orphaned Resources grew
  from 4 to 5 of its 6.

## 13. Verified the map bug by actually executing the file, not just reading it

After repeated reports that the map was "missing," it was verified directly with a headless
DOM (jsdom) rather than reasoning about the markup again — this confirmed the `.world-map`
element and its 10 location pins were genuinely present in the rendered DOM. The real
problem was recognizability: the abstract organic "landmass" blobs had too little contrast
against the dark background to read as a map at a glance.

**Fix:** replaced the blob shapes with labeled continent regions (North America, South
America, Europe, Africa, Asia, Australia, positioned proportionally) plus a graticule
(latitude/longitude grid line) background — both are common, reliable techniques for making
an abstract shape field unambiguously register as "a map" without needing precise coastline
path data. Re-verified via the same headless-DOM approach afterward rather than assuming the
fix worked.

## 14. Replaced the stylized map with a real one, matching the reference screenshot exactly

The reference screenshot shows an actual recognizable world map (real country outlines,
visible internal borders) with circles sized proportionally to resource count — not the
abstract labeled-region approach used in the previous fix. Rather than hand-approximate
continent coastlines, a real public-domain world map SVG was sourced (Al MacDonald /
Fritz Lekschas, `flekschas/simple-world-map` on GitHub, CC BY-SA 3.0 — attribution included
in the preview) with 314 country paths, and the 10 Azure region markers were positioned
using coordinates found by parsing the actual path geometry for reference countries
(US/India/Australia/UK/Japan/Brazil/Canada) rather than guessing a lat/long projection
formula. Marker circles are now sized proportionally to resource count (18px down to 5px
across the 10 locations), matching the reference's bubble-map style exactly — no text
floating on the map itself, matching the reference, with names/values only in the legend
table below.

## 15. Overview row layout didn't match the reference's row grouping

Top 10 Services, Service Adoption, and Resources by Location were split across a 2-column
row plus a separate full-width map panel, instead of the reference's single 3-column row.
The bottom row (Top Unused Resources / Recommendations / Environment Comparison) was three
stacked full-width panels instead of one compact 3-column row.

**Fix:** both rows now use the same `grid-3` layout as the row above them, matching the
reference exactly. Tables with more columns than fit comfortably in a third-width panel
(Environment Comparison's 6 columns) scroll horizontally within their own panel rather than
forcing the whole grid wider — added `overflow-x:auto` to `.panel` for this. The map's
height and location-card grid were both reduced to fit a one-third-width column instead of
a full-width one.

## 16. Cost Analysis and Orphaned Resources had complete API routes but incomplete data
behind several of them — resolved

Comparing every report each module's controller exposes against what actually populates
the tables behind them turned up three real gaps, all in the same shape: the controller
endpoint and ADX schema existed, but nothing ever wrote data into the table.

- **`CostBudgetFact` and `CostForecastFact`** (Cost Analysis's Budget vs Actual and Forecast
  reports) had no collection script at all — `finops/cost-analysis/DEPLOYMENT.md` listed
  "Populate CostBudgetFact and CostForecastFact" as a step with nothing behind it.
- **`CostAnomalyFact`** (Cost Analysis's Anomalies report, and FinOps Scorecard's open-
  anomalies count) — same gap, "Populate CostAnomalyFact from your anomaly detection
  process" was the entire instruction.
- **`OrphanResourceFact`** was worse than just missing data: `orphan-rules.kql` existed but
  was pure documentation — nothing in the repo ever executed it against ADX, and even if
  it had been run manually, six of the columns `OrphansController` actually queries
  (`AgeDays`, `SnapshotDateUtc`, `Owner`, `Application`, `DependencyStatus`,
  `ReviewStatus`) were never produced by the rule at all, so the "By Age" report and half
  of "Top Orphans" would have come back empty regardless.

**Fix:**
- `scripts/Collect-CostBudgets.ps1` — new script, reads real Azure consumption budgets via
  `Get-AzConsumptionBudget` per subscription (this is genuinely a different data source
  from ADX, not something to derive from cost history).
- `finops/cost-analysis/forecast-rule.kql` + `scripts/Collect-CostForecast.ps1` — a
  documented, deliberately simple linear-trend forecast (15-day-vs-prior-15-day growth
  rate projected 30 days out) computed from cost history already in ADX. Matches
  FORECAST-RUNBOOK.md's steps 1 and 4; does not attempt steps 2–3 (flagging one-time
  events, accounting for committed future workloads) since those need human judgment.
- `finops/cost-analysis/anomaly-rule.kql` + `scripts/Detect-CostAnomalies.ps1` — baseline
  (prior 30 days, excluding the most recent week) vs. actual (most recent 7 days) variance
  detection, flagging anything ≥40% deviation and banding severity by how far past that.
  Matches ANOMALY-RUNBOOK.md's steps 1–2; stops there by design — root-causing and
  remediating an anomaly needs a human, so `Status`/`Owner`/`RootCause` are left for that
  workflow to fill in, not guessed at.
- `finops/orphan-detection/orphan-rules.kql` rewritten to also join in `AgeDays` (via each
  resource's earliest seen snapshot — see the cold-start caveat below), `Owner` and
  `Application` (from the `ApplicationOwner`/`Application` tags `finops/governance/
  TAGGING-STANDARD.md` already defines), and default `SnapshotDateUtc`/`DependencyStatus`/
  `ReviewStatus` values. Also fixed to dedupe to each resource's latest snapshot before
  evaluating candidates — the original scanned every historical snapshot row as a separate
  candidate.
- `scripts/Invoke-OrphanDetection.ps1` — new script that actually runs the KQL rule.
- `scripts/AdxHelper.psm1` — shared `Invoke-AdxSetOrAppend` helper (a `.set-or-append`
  management command against the ADX REST endpoint), used by all three KQL-rule scripts
  instead of three copies of the same REST call.
- All four new/changed scripts wired into a new `EnrichFinOps` pipeline stage (budgets
  collect alongside the main collector in the `Collect` stage instead, since it's ordinary
  JSON output like everything else there).

**What's still open:**
- These three KQL-rule scripts have a real dependency on the "Ingest JSON into ADX" step
  (item 7, further down) actually being implemented — they query `ResourceInventory` and
  `CostAnalysisFact`, which only exist in ADX once that stub is filled in. They're wired
  into the pipeline now so no further change is needed there once ingestion works.
- `AgeDays` in orphan detection is a cold-start metric: on a fresh ADX with no history yet,
  every resource's "first seen" date is today, so every `AgeDays` reads 0 until enough
  daily snapshots accumulate. Not fixable without actual history — documented in the KQL
  file rather than hidden.
- The forecast and anomaly methodologies are both deliberately simple statistical models,
  not machine learning or Azure's native forecast/anomaly features — the `Model`/reasoning
  is recorded in the data itself (`Model: "SimpleLinearTrend30D"`) so this is visible to
  anyone querying the table, not just documented here.
- `Recommendation` and `AdoWorkItemId` on `OrphanResourceFact` are still intentionally
  blank — per the module's own `DEPLOYMENT.md`, wiring these to Azure DevOps needs
  authorization/field-mapping approval that's an organizational decision, not a default to
  script past.

## 17. Audited every report against its data source — Usage & Activity's entire
foundation and two more tables had no collection code at all

Following on from item 16 (Cost Analysis / Orphaned Resources), the same audit was done
for the remaining modules: for every ADX table a controller actually queries, is there
code anywhere that populates it? Three more real gaps turned up — one of them large.

- **`ResourceUsageFact`** — the table `UsageActivityController`'s 13+ endpoints query, and
  that `OverviewController`'s adoption breakdown ultimately depends on — had **no
  transform at all**. `Run-Dynamic-Assessment.ps1` collects raw metric rows
  (`resource-metrics.json`) and raw activity rows (`activity-log.json`), but nothing ever
  reshaped either into `ResourceUsageFact`'s columns (`ActivityCount`, `CPUPercent`,
  `UsageStatus`, `LastActivityUtc`, etc.). The entire Usage & Activity module's data
  foundation was missing, not just one report within it.
- **`AzureActivityFact`** — same story: raw activity rows were collected but never
  reshaped into this table's columns (`CallerType`, `ResourceProvider`, etc.), so the
  Identity Activity, Failures, and Heatmap reports had nothing behind them.
- **`FinOpsGovernanceFact`** — `FinOpsController.Governance()` queries tag compliance data
  that nothing computed, even though the required tag list already exists in
  `finops/governance/TAGGING-STANDARD.md` and the tags themselves are already collected on
  `ResourceInventory`.

Two further tables were missing for a different reason — not an uncomputed transform, but
a genuinely uncollected external data source:

- **`ResourceHealthFact`** — Azure Resource Health isn't part of Resource Graph or any bulk
  query; it has to be read per-resource.
- **`DeploymentActivityFact`** — deployment history lives in Azure DevOps, not Azure
  Resource Manager, so nothing in the Azure-facing collection scripts could ever have
  produced it.

**Fix:**
- `scripts/UsageDataHelper.psm1` — new module with `Build-ResourceUsageFact`,
  `Build-AzureActivityFact`, and `Build-GovernanceFact`, wired into
  `Run-Dashboard-Assessment.ps1` to produce `adx-resource-usage.json`, `adx-activity.json`,
  and `adx-governance.json` alongside the files it already wrote. `Get-UsageStatusForResource`
  in this module implements the four-tier Active/LowUsage/Inactive/NeverUsed classification
  `STATUS-RULES.md` calls for — distinct from the older three-tier classifier used
  elsewhere for orphan detection, because that one can't tell "has activity log entries but
  no metric signal" apart from "never touched at all."
- `variables/shared/metric-mapping.json` extended with two more signal mappings
  (`failedRequests` for App Service, `transactions` for Storage) — without these, two of
  `ResourceUsageFact`'s columns would have stayed null even with the transform in place.
- `scripts/Collect-ResourceHealth.ps1` — new script, one Resource Health API call per
  resource (capped via `-MaxResources`, since this is the slow part of a run at scale).
- `scripts/Collect-DeploymentActivity.ps1` — new script, pulls Azure DevOps build history
  via the pipeline's own OAuth token. Needed a new `devops.organization`/`devops.project`
  pair added to the tenant config schema, since nothing in the existing config had
  anywhere to record which DevOps project to read from.
- All wired into `pipeline/azure-adoption-no-csv.yml`'s `Collect` stage, and their output
  files added to the ADX ingestion mapping.

**What's still open:**
- `PolicyState` and `BudgetState` on `FinOpsGovernanceFact` are intentionally left as
  `"NotEvaluated"` — computing them needs Azure Policy compliance data and budget-vs-actual
  comparison respectively, neither of which this script has access to; recorded honestly
  rather than guessed at.
- Resource Health and Deployment Activity both still depend on the same ADX ingestion stub
  as everything else in this list (item 18) before their data actually lands anywhere
  queryable.
- `Collect-ResourceHealth.ps1`'s one-call-per-resource approach doesn't scale indefinitely —
  fine for hundreds of resources, worth revisiting (e.g. sampling, or skipping resource
  types Resource Health doesn't cover) if your estate is in the tens of thousands.

- `CollectorHealth` was already produced (`adx-collector-health.json`) but never included
  in the pipeline's ADX ingestion mapping — added it alongside the others above; no new
  script needed, just a one-line omission.

**Confirmed NOT a gap:** `ResourceMetrics` (raw per-resource metric values) has no
controller endpoint querying it anywhere — it's an intermediate granularity nothing in the
API surfaces directly, so leaving it unpopulated in ADX doesn't break any report. Flagging
this explicitly rather than silently — the audit checked it and found nothing depends on it,
as opposed to the tables above where something did.

## 18. What's still genuinely open

- **ADX cluster/database provisioning is not in Bicep.** `webapp/infra/appservice.bicep`
  only provisions the App Service; the ADX cluster and database are assumed to already
  exist. An always-on ADX cluster has continuous cost — worth a deliberate sizing decision,
  not just a default SKU, before provisioning it.
- **ADX ingestion is a documented step, not automated code.** The `LandAndIngest` pipeline
  stage now has a real "Ingest JSON into ADX" step, but its body is an explicit `TODO` —
  actually queuing ingestion (via `Az.Kusto` or the Kusto ingest client) was left unwritten
  rather than fabricated, since doing it correctly needs the ADX cluster/database (previous
  bullet) to exist first, plus real ingestion mappings per table.
- **Collector output field names don't match the ADX schema.** `Run-Dynamic-Assessment.ps1`
  passes Azure Resource Graph / Cost Management API results through mostly as-is (native
  ARM camelCase field names), while `adx/schema.csl` uses PascalCase. A mapping/transform
  step is needed between "what the collector produces" and "what ADX ingestion expects."
- **The Overview page still renders hardcoded demo data.** `main.tsx`'s KPI tiles,
  environment breakdown, and tables are the literal numbers from the original mockup, not a
  live `fetch("/api/overview")` call. The three new module pages (Usage/Cost/Orphans) do
  call their APIs live — Overview is the one page still owed that wiring.
- **`OrphanActionsController.WorkItem` doesn't create an Azure DevOps work item.** It
  returns a `READY_FOR_ADO_INTEGRATION` payload the frontend can act on, but the actual ADO
  REST call was intentionally left unbuilt in the source package pending "authorization/
  field mapping approval" (per its own `DEPLOYMENT.md`) — that approval step is an
  organizational decision, not something to default past.
- **No dedicated module yet** for `Resources`, `Recommendations` (beyond FinOps
  optimization), `Service Adoption` (beyond Usage & Activity's own adoption endpoint),
  `Reports`, or `Data Dictionary` — all five are nav items in `main.tsx` with no backing
  controller; the app currently falls back to Overview for all of them.
- **Azure OpenAI narrative summaries are explicitly deferred**, per your own instruction —
  not a gap, just noted here so it isn't mistaken for one later.

## What consolidation intentionally did NOT change

- The three modules' own KQL rule logic (`orphan-rules.kql`, `usage-reports.kql`,
  `cost-reports.kql`) was left as-is — it's sound and doesn't reference any of the dropped
  tables.
- `OrphanResourceFact`'s `Confidence` and `DependencyStatus` fields, and `autoDelete: false`
  as the default — these were correct in the source package and are unchanged.
- The multi-tenant `variables/` configuration system — already tenant-agnostic and
  placeholder-driven; only two vestigial, unused loose files at `variables/environments/`
  root (`subscriptions.json`, `tenant-config.json` — not referenced by `ConfigHelper.psm1`'s
  actual `variables/environments/<tenant>/` loading path) were removed.
