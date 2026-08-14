
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

[ApiController, Authorize, Route("api/cost")]
public class CostAnalysisController : ControllerBase
{
    private readonly AdxService _adx;
    public CostAnalysisController(AdxService adx) => _adx = adx;
    private const string UsdFilter = "| where Currency =~ \"USD\"";

    private string Filter(string? environment)
        => string.IsNullOrWhiteSpace(environment) || environment == "All"
        ? ""
        : $" | where Environment =~ '{environment.Replace("'", "''")}'";

    [HttpGet("overview")]
    public async Task<IActionResult> Overview(string? environment = null)
    {
        var f = Filter(environment);
        var q = $"""
        CostAnalysisFact
        | where Date >= startofday(ago(90d))
        {UsdFilter}
        {f}
        | summarize Cost90D=sum(PreTaxCost),
                    Resources=dcount(ResourceId)
        | extend AnnualizedCost=Cost90D*4
        """;
        return Ok(await _adx.QueryAsync(q));
    }

    [HttpGet("trend")]
    public async Task<IActionResult> Trend(string? environment = null, int days = 90)
    {
        days = Math.Clamp(days, 7, 365);
        var f = Filter(environment);
        var q = $"""
        CostAnalysisFact
        | where Date >= startofday(ago({days}d))
        {UsdFilter}
        {f}
        | summarize Cost=sum(PreTaxCost) by Date
        | order by Date asc
        """;
        return Ok(await _adx.QueryAsync(q));
    }

    [HttpGet("environment")]
    public async Task<IActionResult> Environment()
        => Ok(await _adx.QueryAsync("""
        CostAnalysisFact
        | where Date >= startofday(ago(90d))
        | where Currency =~ "USD"
        | summarize Cost90D=sum(PreTaxCost),Resources=dcount(ResourceId) by Environment
        | order by Cost90D desc
        """));

    [HttpGet("service")]
    public async Task<IActionResult> Service(string? environment = null)
        => Ok(await _adx.QueryAsync($"""
        CostAnalysisFact
        | where Date >= startofday(ago(90d))
        {UsdFilter}
        {Filter(environment)}
        | summarize Cost90D=sum(PreTaxCost),Resources=dcount(ResourceId) by ServiceName
        | order by Cost90D desc
        """));

    [HttpGet("resource")]
    public async Task<IActionResult> Resource(string? environment = null, int top = 100)
    {
        top = Math.Clamp(top, 10, 500);
        return Ok(await _adx.QueryAsync($"""
        CostAnalysisFact
        | where Date >= startofday(ago(90d))
        {UsdFilter}
        {Filter(environment)}
        | summarize Cost90D=sum(PreTaxCost) by ResourceId,ResourceName,ServiceName,Environment,SubscriptionName
        | extend AnnualizedCost=Cost90D*4
        | top {top} by Cost90D desc
        """));
    }

    [HttpGet("resource-group")]
    public async Task<IActionResult> ResourceGroup(string? environment = null)
        => Ok(await _adx.QueryAsync($"""
        CostAnalysisFact
        | where Date >= startofday(ago(90d))
        {UsdFilter}
        {Filter(environment)}
        | summarize Cost90D=sum(PreTaxCost) by ResourceGroup,Environment
        | order by Cost90D desc
        """));

    [HttpGet("application")]
    public async Task<IActionResult> Application(string? environment = null)
        => Ok(await _adx.QueryAsync($"""
        CostAnalysisFact
        | where Date >= startofday(ago(90d))
        {UsdFilter}
        {Filter(environment)}
        | summarize Cost90D=sum(PreTaxCost) by Application,Environment
        | order by Cost90D desc
        """));

    [HttpGet("business-unit")]
    public async Task<IActionResult> BusinessUnit(string? environment = null)
        => Ok(await _adx.QueryAsync($"""
        CostAnalysisFact
        | where Date >= startofday(ago(90d))
        {UsdFilter}
        {Filter(environment)}
        | summarize Cost90D=sum(PreTaxCost) by BusinessUnit
        | order by Cost90D desc
        """));

    [HttpGet("owner")]
    public async Task<IActionResult> Owner(string? environment = null)
        => Ok(await _adx.QueryAsync($"""
        CostAnalysisFact
        | where Date >= startofday(ago(90d))
        {UsdFilter}
        {Filter(environment)}
        | summarize Cost90D=sum(PreTaxCost),Resources=dcount(ResourceId) by Owner
        | order by Cost90D desc
        """));

    [HttpGet("unallocated")]
    public async Task<IActionResult> Unallocated(string? environment = null)
        => Ok(await _adx.QueryAsync($"""
        CostAnalysisFact
        | where Date >= startofday(ago(90d))
        {UsdFilter}
        {Filter(environment)}
        | extend AllocationIssue=case(
            isempty(Application) or Application=="Unknown","Missing Application",
            isempty(CostCenter) or CostCenter=="Unknown","Missing Cost Center",
            isempty(Owner) or Owner=="Unknown","Missing Owner",
            "Allocated")
        | summarize Cost90D=sum(PreTaxCost),Resources=dcount(ResourceId) by AllocationIssue
        | order by Cost90D desc
        """));

    [HttpGet("sku")]
    public async Task<IActionResult> Sku(string? environment = null)
        => Ok(await _adx.QueryAsync($"""
        CostAnalysisFact
        | where Date >= startofday(ago(90d))
        {UsdFilter}
        {Filter(environment)}
        | summarize Cost90D=sum(PreTaxCost),Resources=dcount(ResourceId) by ServiceName,SKU
        | order by Cost90D desc
        """));

    [HttpGet("region")]
    public async Task<IActionResult> Region(string? environment = null)
        => Ok(await _adx.QueryAsync($"""
        CostAnalysisFact
        | where Date >= startofday(ago(90d))
        {UsdFilter}
        {Filter(environment)}
        | summarize Cost90D=sum(PreTaxCost) by Region
        | order by Cost90D desc
        """));

    [HttpGet("categories/{category}")]
    public async Task<IActionResult> Category(string category, string? environment = null)
    {
        var safe = category.Replace("'", "''");
        var condition = safe.ToLowerInvariant() switch
        {
            "compute" => """ServiceName in~ ("Virtual Machines","Azure Kubernetes Service","App Service","Container Instances","Container Apps")""",
            "storage" => """ServiceName contains "Storage" or ServiceName contains "Disk" or ServiceName contains "Backup" """,
            "networking" => """ServiceName contains "Network" or ServiceName contains "Firewall" or ServiceName contains "Gateway" or ServiceName contains "Private" or ServiceName contains "VPN" """,
            "monitoring" => """ServiceName contains "Monitor" or ServiceName contains "Application Insights" or ServiceName contains "Sentinel" or MeterCategory contains "Log" """,
            _ => "true"
        };
        return Ok(await _adx.QueryAsync($"""
        CostAnalysisFact
        | where Date >= startofday(ago(90d))
        {UsdFilter}
        {Filter(environment)}
        | where {condition}
        | summarize Cost90D=sum(PreTaxCost) by ServiceName,MeterCategory
        | order by Cost90D desc
        """));
    }

    [HttpGet("anomalies")]
    public async Task<IActionResult> Anomalies(string? environment = null)
        => Ok(await _adx.QueryAsync($"""
        CostAnomalyFact
        | where Status !in ("Closed","Rejected")
        {Filter(environment)}
        | order by VariancePercent desc
        """));

    [HttpGet("budget")]
    public async Task<IActionResult> Budget()
        => Ok(await _adx.QueryAsync("""
        let actual=CostAnalysisFact
        | where Date >= startofday(ago(30d))
        | where Currency =~ "USD"
        | summarize Actual=sum(PreTaxCost) by Environment;
        CostBudgetFact
        | where Currency =~ "USD"
        | join kind=leftouter actual on Environment
        | extend Actual=coalesce(Actual,0.0),
                 Variance=Actual-BudgetAmount,
                 VariancePercent=iff(BudgetAmount>0,100.0*(Actual-BudgetAmount)/BudgetAmount,0.0),
                 BudgetUsedPercent=iff(BudgetAmount>0,100.0*Actual/BudgetAmount,0.0)
        """));

    [HttpGet("forecast")]
    public async Task<IActionResult> Forecast()
        => Ok(await _adx.QueryAsync("""
        CostForecastFact
        | where Currency =~ "USD"
        | where ForecastDate >= startofday(now())
        | summarize Forecast=sum(ForecastAmount),Lower=sum(LowerBound),Upper=sum(UpperBound)
          by Environment
        """));

    [HttpGet("increases")]
    public async Task<IActionResult> Increases(string? environment = null)
        => Ok(await _adx.QueryAsync($"""
        let c=CostAnalysisFact
        | where Date >= startofday(ago(60d))
        {UsdFilter}
        {Filter(environment)}
        | summarize Cost=sum(PreTaxCost) by ResourceId,ResourceName,Environment,ServiceName,
          Period=iff(Date >= startofday(ago(30d)),"Current","Previous");
        c
        | summarize Current=sumif(Cost,Period=="Current"),Previous=sumif(Cost,Period=="Previous")
          by ResourceId,ResourceName,Environment,ServiceName
        | extend Increase=Current-Previous,
                 IncreasePercent=iff(Previous>0,100.0*(Current-Previous)/Previous,100.0)
        | top 50 by Increase desc
        """));

    [HttpGet("environment-service")]
    public async Task<IActionResult> EnvironmentService()
        => Ok(await _adx.QueryAsync("""
        CostAnalysisFact
        | where Date >= startofday(ago(90d))
        | where Currency =~ "USD"
        | summarize Cost90D=sum(PreTaxCost) by Environment,ServiceName
        | order by Environment,Cost90D desc
        """));
}
