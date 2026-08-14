using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

[ApiController]
[Authorize]
[Route("api/finops")]
public class FinOpsController : ControllerBase
{
    private readonly AdxService _adx;
    public FinOpsController(AdxService adx) => _adx = adx;

    [HttpGet("scorecard")]
    public async Task<IActionResult> Scorecard()
    {
        var query = @"
let spend = CostAnalysisFact
| where Date >= startofday(ago(30d))
| where Currency =~ 'USD'
| summarize Spend=sum(PreTaxCost) by Environment;
let opt = FinOpsOptimizationFact
| summarize PotentialSavings=sum(EstimatedSavings), RealizedSavings=sum(ValidatedSavings)
  by Environment;
spend
| join kind=fullouter opt on Environment
| project Environment, Spend=coalesce(Spend,0.0),
          PotentialSavings=coalesce(PotentialSavings,0.0),
          RealizedSavings=coalesce(RealizedSavings,0.0)";
        return Ok(await _adx.QueryAsync(query));
    }

    [HttpGet("anomalies")]
    public async Task<IActionResult> Anomalies()
        => Ok(await _adx.QueryAsync(
            "CostAnomalyFact | where Status !in ('Closed','Rejected') | order by VariancePercent desc"));

    [HttpGet("optimization")]
    public async Task<IActionResult> Optimization()
        => Ok(await _adx.QueryAsync(
            "FinOpsOptimizationFact | summarize Opportunities=count(), PotentialSavings=sum(EstimatedSavings), RealizedSavings=sum(ValidatedSavings) by State,RecommendationType,Environment"));

    [HttpGet("governance")]
    public async Task<IActionResult> Governance()
        => Ok(await _adx.QueryAsync(
            "FinOpsGovernanceFact | summarize Resources=count(), Compliant=countif(TagCompliancePercent >= 100), Owners=countif(OwnerPresent) by Environment"));
}
