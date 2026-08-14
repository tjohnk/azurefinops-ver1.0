import * as React from "react";
import { createRoot } from "react-dom/client";

const stylesheetId = "finops-dashboard-theme";
if (!document.getElementById(stylesheetId)) {
  const link = document.createElement("link");
  link.id = stylesheetId;
  link.rel = "stylesheet";
  link.href = "./src/styles.css";
  document.head.appendChild(link);
}

type Kpi = {
  label: string;
  value: string;
  subtitle: string;
  tone: "blue" | "green" | "amber" | "red" | "purple" | "cyan";
  icon: keyof typeof KPI_ICONS;
};

// Small inline SVG icons — kept as plain JSX (no icon-library dependency) so this
// file has no new build-time dependency. These replace the "?" placeholders that
// shipped in the original package (a lost/corrupted glyph, not an intentional gap).
const KPI_ICONS = {
  box: (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8">
      <path d="M3 7l9-4 9 4-9 4-9-4z" />
      <path d="M3 7v10l9 4 9-4V7" />
      <path d="M12 11v10" />
    </svg>
  ),
  check: (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8">
      <circle cx="12" cy="12" r="9" />
      <path d="M8 12l3 3 5-6" />
    </svg>
  ),
  bars: (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8">
      <path d="M5 19V10M12 19V5M19 19v-7" />
    </svg>
  ),
  noEntry: (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8">
      <circle cx="12" cy="12" r="9" />
      <path d="M6 12h12" />
    </svg>
  ),
  user: (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8">
      <circle cx="12" cy="8" r="3.5" />
      <path d="M5 20c1.2-3.5 4-5.5 7-5.5s5.8 2 7 5.5" />
    </svg>
  ),
  wallet: (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8">
      <rect x="3" y="6" width="18" height="13" rx="2" />
      <path d="M3 10h18" />
      <circle cx="16" cy="14" r="1.2" fill="currentColor" stroke="none" />
    </svg>
  ),
} as const;

function Chevron() {
  return (
    <svg viewBox="0 0 24 24" width="12" height="12" fill="none" stroke="currentColor" strokeWidth="2">
      <path d="M6 9l6 6 6-6" />
    </svg>
  );
}

function AzureMark() {
  return (
    <svg viewBox="0 0 64 64" width="28" height="28" aria-hidden="true">
      <defs>
        <linearGradient id="azureMarkPrimary" x1="0%" y1="0%" x2="100%" y2="100%">
          <stop offset="0%" stopColor="#74d0ff" />
          <stop offset="100%" stopColor="#3d7cff" />
        </linearGradient>
        <linearGradient id="azureMarkSecondary" x1="0%" y1="0%" x2="100%" y2="100%">
          <stop offset="0%" stopColor="#b6dcff" />
          <stop offset="100%" stopColor="#5b8dff" />
        </linearGradient>
      </defs>
      <path d="M14 52 27 10c.7-2.2 3.8-2.5 4.9-.5L50 52H38.8l-2.9-9.8H24.7L22 52Z" fill="url(#azureMarkPrimary)" />
      <path d="M34.4 18.6 45.7 52H29.8l4.7-14.9-6.9-8.2Z" fill="url(#azureMarkSecondary)" opacity=".95" />
    </svg>
  );
}

function CalendarIcon() {
  return (
    <svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" strokeWidth="1.8">
      <rect x="3" y="5" width="18" height="16" rx="2" />
      <path d="M3 10h18M8 3v4M16 3v4" />
    </svg>
  );
}

type DistributionItem = {
  name: string;
  value: string;
  percent: string;
  color: string;
};

type BarItem = {
  name: string;
  value: number;
  label: string;
  colorClass: string;
};

const environmentButtons = [
  { label: "All", className: "all" },
  { label: "Sandbox", className: "sandbox" },
  { label: "Dev", className: "dev" },
  { label: "Staging", className: "staging" },
  { label: "Production", className: "production" }
];

const navigation = [
  "Overview",
  "Resources",
  "Usage & Activity",
  "Cost Analysis",
  "Recommendations",
  "Service Adoption",
  "Environment Comparison",
  "Orphaned Resources",
  "Reports",
  "Data Dictionary"
];

const kpis: Kpi[] = [
  { label: "Total Resources", value: "7,842", subtitle: "All Environments", tone: "blue", icon: "box" },
  { label: "Active Resources", value: "5,392", subtitle: "68.76% of Total", tone: "green", icon: "check" },
  { label: "Low Usage Resources", value: "1,367", subtitle: "17.43% of Total", tone: "amber", icon: "bars" },
  { label: "No Usage Resources", value: "683", subtitle: "8.72% of Total", tone: "red", icon: "noEntry" },
  { label: "Orphaned Resources", value: "400", subtitle: "5.10% of Total", tone: "purple", icon: "user" },
  { label: "Total Monthly Cost", value: "\u20B918.76M", subtitle: "All Environments", tone: "cyan", icon: "wallet" }
];

const environmentDistribution: DistributionItem[] = [
  { name: "Production", value: "3,125", percent: "39.86%", color: "var(--accent-red)" },
  { name: "Staging", value: "1,843", percent: "23.51%", color: "var(--accent-amber)" },
  { name: "Dev", value: "1,672", percent: "21.33%", color: "var(--accent-blue)" },
  { name: "Sandbox", value: "1,202", percent: "15.31%", color: "var(--accent-green)" }
];

const statusDistribution: DistributionItem[] = [
  { name: "Active", value: "5,392", percent: "68.76%", color: "var(--accent-green)" },
  { name: "Low Usage", value: "1,367", percent: "17.43%", color: "var(--accent-amber)" },
  { name: "No Usage", value: "683", percent: "8.72%", color: "var(--accent-red)" },
  { name: "Orphaned", value: "400", percent: "5.10%", color: "var(--accent-purple)" }
];

const monthlyCostBars: BarItem[] = [
  { name: "Production", value: 8.45, label: "$8.45M", colorClass: "red" },
  { name: "Staging", value: 4.32, label: "$4.32M", colorClass: "amber" },
  { name: "Dev", value: 3.43, label: "$3.43M", colorClass: "blue" },
  { name: "Sandbox", value: 2.56, label: "$2.56M", colorClass: "green" }
];

const topServices: BarItem[] = [
  { name: "Microsoft.Compute", value: 1386, label: "1,386", colorClass: "blue" },
  { name: "Microsoft.Storage", value: 1124, label: "1,124", colorClass: "blue" },
  { name: "Microsoft.Web", value: 874, label: "874", colorClass: "blue" },
  { name: "Microsoft.Sql", value: 742, label: "742", colorClass: "blue" },
  { name: "Microsoft.Network", value: 640, label: "640", colorClass: "blue" },
  { name: "Microsoft.ContainerService", value: 478, label: "478", colorClass: "blue" },
  { name: "Microsoft.KeyVault", value: 332, label: "332", colorClass: "blue" },
  { name: "Microsoft.DBforPostgreSQL", value: 298, label: "298", colorClass: "blue" },
  { name: "Microsoft.AppServiceEnvironment", value: 186, label: "186", colorClass: "blue" },
  { name: "Microsoft.Functions", value: 152, label: "152", colorClass: "blue" }
];

const serviceAdoption: BarItem[] = [
  { name: "App Service", value: 92.3, label: "92.3%", colorClass: "green" },
  { name: "Storage Accounts", value: 89.7, label: "89.7%", colorClass: "green" },
  { name: "Azure SQL Database", value: 86.1, label: "86.1%", colorClass: "green" },
  { name: "Virtual Machines", value: 84.5, label: "84.5%", colorClass: "green" },
  { name: "Key Vault", value: 78.4, label: "78.4%", colorClass: "green" },
  { name: "Azure Functions", value: 76.2, label: "76.2%", colorClass: "green" },
  { name: "AKS (Kubernetes)", value: 73.6, label: "73.6%", colorClass: "green" },
  { name: "Load Balancers", value: 72.8, label: "72.8%", colorClass: "green" },
  { name: "App Service Environment", value: 65.4, label: "65.4%", colorClass: "green" },
  { name: "Recovery Services Vault", value: 61.7, label: "61.7%", colorClass: "green" }
];

const unusedResources = [
  ["vm-sbx-test-01", "Virtual Machine", "Sandbox", "rg-sbx-test", "-", "12,450"],
  ["app-dev-oldapi", "App Service", "Dev", "rg-dev-apps", "-", "8,750"],
  ["sql-stg-unused", "SQL Database", "Staging", "rg-stg-data", "-", "6,230"],
  ["stacc-dev-backup", "Storage Account", "Dev", "rg-dev-storage", "-", "4,120"],
  ["vm-sbx-demo-02", "Virtual Machine", "Sandbox", "rg-sbx-demo", "-", "11,980"],
  ["func-dev-unused", "Function App", "Dev", "rg-dev-func", "-", "1,870"],
  ["kv-stg-old", "Key Vault", "Staging", "rg-stg-security", "-", "2,450"],
  ["nic-sbx-unused", "Network Interface", "Sandbox", "rg-sbx-network", "-", "980"],
  ["disk-dev-old", "Disk", "Dev", "rg-dev-storage", "-", "1,150"],
  ["pip-sbx-unused", "Public IP", "Sandbox", "rg-sbx-network", "-", "760"]
];

const recommendations = [
  ["Right-size", "1,245", "3,45,000"],
  ["Shutdown (Schedule)", "982", "2,76,000"],
  ["Delete", "683", "1,92,000"],
  ["Move to Lower Tier", "421", "1,15,000"],
  ["Reserved Instances", "312", "2,35,000"],
  ["Total", "3,643", "11,63,000"]
];

const comparisonRows = [
  ["Total Resources", "1,202", "1,672", "1,843", "3,125", "7,842"],
  ["Active Resources", "652", "1,152", "1,387", "2,201", "5,392"],
  ["Low Usage Resources", "247", "311", "362", "447", "1,367"],
  ["No Usage Resources", "173", "128", "142", "240", "683"],
  ["Orphaned Resources", "130", "81", "87", "102", "400"],
  ["Monthly Cost ($)", "2.56M", "3.43M", "4.32M", "8.45M", "18.76M"]
];

const mapLocations = [
  { name: "East US", value: "2,450", left: "10%", top: "33%" },
  { name: "West Europe", value: "1,245", left: "46%", top: "29%" },
  { name: "Southeast Asia", value: "986", left: "73%", top: "52%" },
  { name: "Central India", value: "742", left: "64%", top: "46%" },
  { name: "Australia East", value: "615", left: "86%", top: "72%" },
  { name: "UK South", value: "420", left: "48%", top: "25%" },
  { name: "Japan East", value: "398", left: "81%", top: "40%" },
  { name: "Brazil South", value: "330", left: "29%", top: "70%" }
];

function RingChart({ items, totalLabel }: { items: DistributionItem[]; totalLabel: string }) {
  const gradient = `conic-gradient(${items
    .map((item, index) => {
      const percentage = Number.parseFloat(item.percent);
      const start = items.slice(0, index).reduce((sum, current) => sum + Number.parseFloat(current.percent), 0);
      const end = start + percentage;
      return `${item.color} ${start}% ${end}%`;
    })
    .join(", ")})`;

  return (
    <div className="ring-layout">
      <div className="ring" style={{ backgroundImage: gradient }}>
        <div className="ring-center">
          <strong>7,842</strong>
          <span>{totalLabel}</span>
        </div>
      </div>
      <div className="ring-legend">
        {items.map((item) => (
          <div className="legend-row" key={item.name}>
            <span className="legend-dot" style={{ backgroundColor: item.color }} />
            <span className="legend-name">{item.name}</span>
            <span className="legend-value">{item.value}</span>
            <span className="legend-percent">({item.percent})</span>
          </div>
        ))}
      </div>
    </div>
  );
}

function HorizontalBars({ items, max, percentMode = false }: { items: BarItem[]; max: number; percentMode?: boolean }) {
  return (
    <div className="hbars">
      {items.map((item) => (
        <div className="hbar-row" key={item.name}>
          <div className="hbar-label">{item.name}</div>
          <div className="hbar-track">
            <div className={`hbar-fill ${item.colorClass}`} style={{ width: `${(item.value / max) * 100}%` }} />
          </div>
          <div className="hbar-value">{item.label}</div>
        </div>
      ))}
      <div className="hbar-axis">
        <span>0</span>
        <span>{percentMode ? "50%" : "500"}</span>
        <span>{percentMode ? "100%" : "1,000"}</span>
        {!percentMode && <span>1,500</span>}
      </div>
    </div>
  );
}

function VerticalBars() {
  const max = Math.max(...monthlyCostBars.map((item) => item.value));
  return (
    <div className="vchart-wrap">
      <div className="vchart-axis-left">
        <span>8M</span>
        <span>6M</span>
        <span>4M</span>
        <span>2M</span>
        <span>0M</span>
      </div>
      <div className="vchart">
        {monthlyCostBars.map((item) => (
          <div className="vbar-group" key={item.name}>
            <span className="vbar-top">{item.label}</span>
            <div className="vbar-track">
              <div className={`vbar-fill ${item.colorClass}`} style={{ height: `${(item.value / max) * 100}%` }} />
            </div>
            <span className="vbar-name">{item.name}</span>
          </div>
        ))}
      </div>
    </div>
  );
}

// NOTE: the KPI/panel content below renders demo/mock values (see the
// hardcoded `kpis`, `distribution`, etc. arrays above) rather than calling
// the API. Wiring this to GET /api/overview (see OverviewController.cs) is
// tracked in GAP-ANALYSIS.md. The sidebar shell here is shared by all pages
// (see App.tsx): `activeNav`/`onNavigate` drive which nav item is
// highlighted and clickable, and `children`, when provided, replaces this
// component's own Overview content with whichever page App.tsx selected.
type OverviewPageProps = {
  activeNav?: string;
  onNavigate?: (item: string) => void;
  children?: React.ReactNode;
};

export function OverviewPage({ activeNav = "Overview", onNavigate, children }: OverviewPageProps = {}) {
  return (
    <div className="app-shell">
      <aside className="sidebar">
        <div className="brand-card">
          <div className="brand-logo"><AzureMark /></div>
          <div>
            <div className="brand-title">Azure Estate FinOps Intelligence</div>
            <div className="brand-subtitle">Report Preview</div>
            <div className="brand-refresh">Sample data — no live backend</div>
          </div>
        </div>

        <div className="preview-note">
          <strong>Static preview with mock data.</strong>
          <span>Once ADX ingestion is wired up, the real portal shows live numbers here instead.</span>
          <small>Last Refresh: 18-May-2025 08:30 AM</small>
        </div>

        <nav className="sidebar-nav">
          {navigation.map((item) => (
            <button
              className={`nav-item ${item === activeNav ? "active" : ""}`}
              key={item}
              onClick={() => onNavigate?.(item)}
            >
              <span className="nav-icon" aria-hidden="true">
                <svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" strokeWidth="2">
                  <rect x="4" y="4" width="16" height="16" rx="3" />
                </svg>
              </span>
              <span>{item}</span>
            </button>
          ))}
        </nav>
      </aside>

      <main className="main-area">
        {children ? children : (
        <>
        <section className="overview-header">
          <div className="overview-intro panel">
            <h1>Overview</h1>
            <p>Resource adoption across all environments</p>
          </div>
          <div className="overview-meta">Preview styling aligned to the reference dashboard</div>
        </section>
        <section className="filters-grid reference-filters">
          <div className="filter-block environment-block">
            <label>Environment</label>
            <div className="pill-row">
              {environmentButtons.map((button, index) => (
                <button className={`env-pill ${button.className} ${index === 0 ? "active" : ""}`} key={button.label}>
                  {button.label}
                </button>
              ))}
            </div>
          </div>

          <div className="filter-block select-block">
            <label>Subscription</label>
            <div className="select-shell">
              <span>All</span>
              <span><Chevron /></span>
            </div>
          </div>

          <div className="filter-block select-block">
            <label>Resource Group</label>
            <div className="select-shell">
              <span>All</span>
              <span><Chevron /></span>
            </div>
          </div>

          <div className="filter-block select-block">
            <label>Resource Type</label>
            <div className="select-shell">
              <span>All</span>
              <span><Chevron /></span>
            </div>
          </div>

          <div className="filter-block select-block date-block">
            <label>Date Range (Usage)</label>
            <div className="select-shell with-icon">
              <span className="calendar-icon"><CalendarIcon /></span>
              <span>Last 90 Days</span>
              <span><Chevron /></span>
            </div>
          </div>
        </section>

        <section className="kpi-grid">
          {kpis.map((kpi) => (
            <article className="panel kpi-card" key={kpi.label}>
              <div className={`kpi-icon ${kpi.tone}`}>{KPI_ICONS[kpi.icon]}</div>
              <div className="kpi-content">
                <div className="kpi-label">{kpi.label}</div>
                <div className={`kpi-value ${kpi.tone}`}>{kpi.value}</div>
                <div className="kpi-subtitle">{kpi.subtitle}</div>
              </div>
            </article>
          ))}
        </section>

        <section className="content-grid top-grid">
          <article className="panel chart-panel">
            <h3>Resources by Environment</h3>
            <RingChart items={environmentDistribution} totalLabel="Total" />
            <div className="chart-note">Segments show distribution by environment. Legend includes counts per environment.</div>
          </article>

          <article className="panel chart-panel">
            <h3>Resources by Status</h3>
            <RingChart items={statusDistribution} totalLabel="Total" />
            <div className="chart-note">Segments show distribution by resource status (Active, Low Usage, No Usage, Orphaned).</div>
          </article>

          <article className="panel chart-panel">
            <h3>Monthly Cost by Environment ($)</h3>
            <VerticalBars />
            <div className="chart-note">X-axis: Environments. Y-axis: Cost (USD). Values shown in millions.</div>
          </article>
        </section>

        <section className="content-grid middle-grid">
          <article className="panel chart-panel compact">
            <h3>Top 10 Services by Resource Count</h3>
            <HorizontalBars items={topServices} max={1500} />
            <div className="chart-note">X-axis: Resource count. Y-axis: Service name.</div>
          </article>

          <article className="panel chart-panel compact">
            <h3>Service Adoption (% Active Resources)</h3>
            <HorizontalBars items={serviceAdoption} max={100} percentMode />
            <div className="chart-note">X-axis: Percent of active resources. Y-axis: Service name.</div>
          </article>

          <article className="panel map-panel">
            <h3>Resources by Location (Top 10)</h3>
            <div className="world-map">
              <div className="map-shape one" />
              <div className="map-shape two" />
              <div className="map-shape three" />
              <div className="map-shape four" />
              {mapLocations.map((location) => (
                <div
                  className="map-point"
                  key={location.name}
                  style={{ left: location.left, top: location.top }}
                  title={`${location.name}: ${location.value}`}
                />
              ))}
            </div>
            <div className="location-summary">
              {mapLocations.slice(0, 5).map((location) => (
                <div className="location-card" key={location.name}>
                  <span>{location.name}</span>
                  <strong>{location.value}</strong>
                </div>
              ))}
            </div>
          </article>
        </section>

        <section className="content-grid bottom-grid">
          <article className="panel table-panel">
            <h3>Top 10 Unused Resources (No Activity in Last 90 Days)</h3>
            <table>
              <thead>
                <tr>
                  <th>Resource Name</th>
                  <th>Resource Type</th>
                  <th>Environment</th>
                  <th>Resource Group</th>
                  <th>Last Activity</th>
                  <th>Monthly Cost ($)</th>
                </tr>
              </thead>
              <tbody>
                {unusedResources.map((row) => (
                  <tr key={row[0]}>
                    {row.map((cell) => (
                      <td key={cell}>{cell}</td>
                    ))}
                  </tr>
                ))}
              </tbody>
            </table>
            <div className="panel-footnote">* Cost data is based on amortized costs and may not reflect real-time charges.</div>
          </article>

          <article className="panel table-panel">
            <h3>Resources by Recommendation</h3>
            <table>
              <thead>
                <tr>
                  <th>Recommendation</th>
                  <th>Resources</th>
                  <th>Potential Monthly Savings ($)</th>
                </tr>
              </thead>
              <tbody>
                {recommendations.map((row, index) => (
                  <tr className={index === recommendations.length - 1 ? "total-row" : ""} key={row[0]}>
                    {row.map((cell) => (
                      <td key={cell}>{cell}</td>
                    ))}
                  </tr>
                ))}
              </tbody>
            </table>
          </article>

          <article className="panel table-panel">
            <h3>Environment Comparison</h3>
            <table>
              <thead>
                <tr>
                  <th>Metric</th>
                  <th>Sandbox</th>
                  <th>Dev</th>
                  <th>Staging</th>
                  <th>Production</th>
                  <th>Total</th>
                </tr>
              </thead>
              <tbody>
                {comparisonRows.map((row) => (
                  <tr key={row[0]}>
                    {row.map((cell) => (
                      <td key={cell}>{cell}</td>
                    ))}
                  </tr>
                ))}
              </tbody>
            </table>
          </article>
        </section>
        </>
        )}

        <footer className="page-footer">All dates and times are in UTC</footer>
      </main>
    </div>
  );
}


