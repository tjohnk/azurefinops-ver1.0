import * as React from "react";
import { createRoot } from "react-dom/client";
import { OverviewPage } from "./main";
import UsageActivityPage from "./usage/UsageActivityPage";
import CostAnalysisPage from "./cost/CostAnalysisPage";
import OrphansPage from "./orphans/OrphansPage";

// Maps the left-nav labels (defined in main.tsx's `navigation` array) to the
// page component that should render for each. Nav items with no module yet
// (Resources, Recommendations, Service Adoption, Reports, Data Dictionary)
// fall back to the Overview page rather than a blank screen — see
// GAP-ANALYSIS.md for which of these still need their own module.
const pages: Record<string, React.ComponentType> = {
  "Usage & Activity": UsageActivityPage,
  "Cost Analysis": CostAnalysisPage,
  "Orphaned Resources": OrphansPage,
};

function App() {
  const [activeNav, setActiveNav] = React.useState("Overview");
  const ActivePage = pages[activeNav];

  return (
    <OverviewPage activeNav={activeNav} onNavigate={setActiveNav}>
      {ActivePage ? <ActivePage /> : undefined}
    </OverviewPage>
  );
}

createRoot(document.getElementById("root")!).render(<App />);
