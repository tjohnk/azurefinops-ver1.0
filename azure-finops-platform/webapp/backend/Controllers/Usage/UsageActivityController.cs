
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

[ApiController,Authorize,Route("api/usage")]
public class UsageActivityController : ControllerBase {
    private readonly AdxService _adx;
    public UsageActivityController(AdxService adx)=>_adx=adx;
    private sealed record TrendRangeDefinition(int? Days, string BucketUnit);
    private string F(string? e)=>string.IsNullOrWhiteSpace(e)||e=="All"?"":
        $" | where Environment =~ '{e.Replace("'","''")}'";
    private static TrendRangeDefinition ResolveTrendRange(string? range)=>range?.Trim().ToLowerInvariant() switch{
        "30"=>new TrendRangeDefinition(30,"day"),
        "365"=>new TrendRangeDefinition(365,"month"),
        "all"=>new TrendRangeDefinition(null,"year"),
        _=>new TrendRangeDefinition(90,"day")
    };

    [HttpGet("overview")] public async Task<IActionResult> Overview(string? e=null)=>Ok(await _adx.QueryAsync($"""
    ResourceUsageFact | summarize arg_max(TimestampUtc,*) by ResourceId {F(e)}
    | summarize TotalResources=dcount(ResourceId),ActiveResources=dcountif(ResourceId,UsageStatus=="Active"),
      LowUsageResources=dcountif(ResourceId,UsageStatus=="LowUsage"),
      InactiveResources=dcountif(ResourceId,UsageStatus=="Inactive"),NeverUsedResources=dcountif(ResourceId,UsageStatus=="NeverUsed"),
      ActivityEvents=sum(ActivityCount),RequestEvents=sum(RequestCount),FailedRequests=sum(FailedRequestCount)
    """));

    [HttpGet("last-activity")] public async Task<IActionResult> LastActivity(string? e=null)=>Ok(await _adx.QueryAsync($"""
    ResourceUsageFact | summarize arg_max(TimestampUtc,*) by ResourceId {F(e)}
    | extend DaysSinceActivity=iff(isnull(LastActivityUtc),99999,datetime_diff("day",now(),LastActivityUtc))
    | project ResourceId,ResourceName,ServiceName,Environment,Owner,LastActivityUtc,DaysSinceActivity,UsageStatus,ActivityCount
    | order by DaysSinceActivity desc
    """));

    [HttpGet("environment")] public async Task<IActionResult> Environment()=>Ok(await _adx.QueryAsync("""
    ResourceUsageFact | summarize arg_max(TimestampUtc,*) by ResourceId
    | summarize Total=dcount(ResourceId),Active=dcountif(ResourceId,UsageStatus=="Active"),
      Inactive=dcountif(ResourceId,UsageStatus=="Inactive"),NeverUsed=dcountif(ResourceId,UsageStatus=="NeverUsed") by Environment
    | extend ActivePercent=iff(Total>0,100.0*Active/Total,0.0)
    """));

    [HttpGet("adoption")] public async Task<IActionResult> Adoption(string? e=null)=>Ok(await _adx.QueryAsync($"""
    ResourceUsageFact | summarize arg_max(TimestampUtc,*) by ResourceId {F(e)}
    | summarize Deployed=dcount(ResourceId),Active=dcountif(ResourceId,UsageStatus=="Active"),
      Inactive=dcountif(ResourceId,UsageStatus in ("Inactive","NeverUsed")) by ServiceName
    | extend AdoptionPercent=iff(Deployed>0,100.0*Active/Deployed,0.0)
    """));

    [HttpGet("never-used")] public async Task<IActionResult> NeverUsed(string? e=null)=>Ok(await _adx.QueryAsync($"""
    ResourceUsageFact | summarize arg_max(TimestampUtc,*) by ResourceId {F(e)}
    | where UsageStatus=="NeverUsed" or ActivityCount==0
    | project ResourceId,ResourceName,ServiceName,Environment,ResourceGroup,Owner,Application,LastActivityUtc,UsageStatus
    """));

    [HttpGet("inactive")] public async Task<IActionResult> Inactive(string? e=null)=>Ok(await _adx.QueryAsync($"""
    ResourceUsageFact | summarize arg_max(TimestampUtc,*) by ResourceId {F(e)}
    | extend DaysSinceActivity=iff(isnull(LastActivityUtc),99999,datetime_diff("day",now(),LastActivityUtc))
    | where DaysSinceActivity>90
    | project ResourceId,ResourceName,ServiceName,Environment,Owner,DaysSinceActivity,UsageStatus
    | order by DaysSinceActivity desc
    """));

    [HttpGet("trend")] public async Task<IActionResult> Trend(string? e=null,string? range="90"){
        var tr=ResolveTrendRange(range);
        var dateFilter=tr.Days.HasValue?$"| where Date>=startofday(ago({tr.Days.Value}d))":"";
        var bucket=tr.BucketUnit switch{
            "month"=>"startofmonth(Date)",
            "year"=>"startofyear(Date)",
            _=>"startofday(Date)"
        };
        return Ok(await _adx.QueryAsync($"""
    ResourceUsageFact
    | where isnotnull(Date)
    {dateFilter}
    {F(e)}
    | summarize Activity=sum(ActivityCount),Requests=sum(RequestCount) by TimelineDate={bucket}
    | order by TimelineDate asc
    """));
    }

    [HttpGet("identities")] public async Task<IActionResult> Identities(string? e=null)=>Ok(await _adx.QueryAsync($"""
    AzureActivityFact | where TimestampUtc>=ago(30d) {F(e)}
    | extend IdentityType=case(CallerType in ("ServicePrincipal","ManagedIdentity"),CallerType,isempty(Caller),"Unknown","Human")
    | summarize Operations=count(),Resources=dcount(ResourceId) by Caller,IdentityType | order by Operations desc
    """));

    [HttpGet("failures")] public async Task<IActionResult> Failures(string? e=null)=>Ok(await _adx.QueryAsync($"""
    AzureActivityFact | where TimestampUtc>=ago(30d) {F(e)}
    | where ActivityStatus in ("Failed","Failure")
    | summarize Failures=count(),Resources=dcount(ResourceId) by OperationName,ResourceProvider
    | top 50 by Failures desc
    """));

    [HttpGet("changes")] public async Task<IActionResult> Changes(string? e=null)=>Ok(await _adx.QueryAsync($"""
    AzureActivityFact | where TimestampUtc>=ago(30d) {F(e)}
    | where OperationName has_any ("/write","/action","/update")
    | summarize Changes=count() by ResourceName,ResourceId,Environment,Caller
    | top 100 by Changes desc
    """));

    [HttpGet("deployments")] public async Task<IActionResult> Deployments(string? e=null)=>Ok(await _adx.QueryAsync($"""
    DeploymentActivityFact | where TimestampUtc>=ago(30d) {F(e)}
    | summarize Deployments=count(),Successful=countif(Status=="Succeeded"),Failed=countif(Status=="Failed") by Environment
    | extend SuccessPercent=iff(Deployments>0,100.0*Successful/Deployments,0.0)
    """));

    [HttpGet("vm-utilization")] public async Task<IActionResult> Vm(string? e=null)=>Ok(await _adx.QueryAsync($"""
    ResourceUsageFact | summarize arg_max(TimestampUtc,*) by ResourceId {F(e)}
    | where ResourceType =~ "microsoft.compute/virtualmachines"
    | project ResourceName,Environment,Owner,CPUPercent,MemoryPercent,NetworkBytes,PowerState,LastActivityUtc,UsageStatus
    | order by CPUPercent asc
    """));

    [HttpGet("app-service")] public async Task<IActionResult> App(string? e=null)=>Ok(await _adx.QueryAsync($"""
    ResourceUsageFact | summarize Requests=sum(RequestCount),FailedRequests=sum(FailedRequestCount),
      CPUAvg=avg(CPUPercent),LastActivity=max(LastActivityUtc) by ResourceId,ResourceName,Environment
    | where ResourceId has "/microsoft.web/sites/" {F(e)}
    | extend FailurePercent=iff(Requests>0,100.0*FailedRequests/Requests,0.0) | order by Requests asc
    """));

    [HttpGet("storage")] public async Task<IActionResult> Storage(string? e=null)=>Ok(await _adx.QueryAsync($"""
    ResourceUsageFact | summarize Transactions=sum(TransactionCount),NetworkBytes=sum(NetworkBytes),
      LastActivity=max(LastActivityUtc) by ResourceId,ResourceName,Environment {F(e)}
    | where ServiceName contains "Storage" | order by Transactions asc
    """));

    [HttpGet("sql")] public async Task<IActionResult> Sql(string? e=null)=>Ok(await _adx.QueryAsync($"""
    ResourceUsageFact | summarize Requests=sum(RequestCount),CPUAvg=avg(CPUPercent),
      LastActivity=max(LastActivityUtc) by ResourceId,ResourceName,Environment {F(e)}
    | where ServiceName contains "SQL" | order by Requests asc
    """));

    [HttpGet("health")] public async Task<IActionResult> Health(string? e=null)=>Ok(await _adx.QueryAsync($"""
    ResourceHealthFact | summarize arg_max(TimestampUtc,*) by ResourceId {F(e)}
    | summarize Count=count() by HealthStatus,Environment
    """));

    [HttpGet("heatmap")] public async Task<IActionResult> Heatmap(string? e=null)=>Ok(await _adx.QueryAsync($"""
    AzureActivityFact | where TimestampUtc>=ago(30d) {F(e)}
    | extend DayOfWeek=format_datetime(TimestampUtc,"ddd"),Hour=toint(format_datetime(TimestampUtc,"HH"))
    | summarize Events=count() by DayOfWeek,Hour
    """));

    [HttpGet("environment-service")] public async Task<IActionResult> EnvironmentService()=>Ok(await _adx.QueryAsync("""
    ResourceUsageFact | summarize Activity=sum(ActivityCount),Requests=sum(RequestCount),
      ActiveResources=dcountif(ResourceId,UsageStatus=="Active") by Environment,ServiceName
    | order by Environment,Activity desc
    """));

    [HttpGet("usage-cost")] public async Task<IActionResult> UsageCost(string? e=null)=>Ok(await _adx.QueryAsync($"""
    let u=ResourceUsageFact | where Date>=startofday(ago(90d)) {F(e)}
    | summarize Activity=sum(ActivityCount),Requests=sum(RequestCount),ActiveDays=dcountif(Date,ActivityCount>0)
      by ResourceId,ResourceName,Environment;
    let c=CostAnalysisFact | where Date>=startofday(ago(90d))
    | summarize Cost90D=sum(PreTaxCost) by ResourceId;
    u | join kind=leftouter c on ResourceId
    | extend Cost90D=coalesce(Cost90D,0.0),CostPerActivity=iff(Activity>0,Cost90D/Activity,0.0)
    | order by Cost90D desc
    """));
}
