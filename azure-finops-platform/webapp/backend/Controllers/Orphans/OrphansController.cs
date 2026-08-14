
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

[ApiController,Authorize,Route("api/orphans")]
public class OrphansController : ControllerBase {
 private readonly AdxService _adx;
 public OrphansController(AdxService adx)=>_adx=adx;

 [HttpGet("summary")]
 public async Task<IActionResult> Summary(string? environment=null) {
  var f=string.IsNullOrWhiteSpace(environment)?"":$" | where Environment =~ '{environment.Replace("'","''")}'";
  return Ok(await _adx.QueryAsync($@"OrphanResourceFact{f}
 | summarize Total=count(),HighConfidence=countif(Confidence>=90),
 Production=countif(Environment =~ 'Production'),Over90Days=countif(AgeDays>90),
 Cost90D=sum(Cost90D),PotentialAnnualSaving=sum(AnnualizedCost)"));
 }

 [HttpGet("by-environment")]
 public async Task<IActionResult> ByEnvironment()=>Ok(await _adx.QueryAsync(
  "OrphanResourceFact | summarize Orphans=count(),Cost90D=sum(Cost90D),PotentialSaving=sum(AnnualizedCost) by Environment"));

 [HttpGet("by-type")]
 public async Task<IActionResult> ByType()=>Ok(await _adx.QueryAsync(
  "OrphanResourceFact | summarize Count=count(),Cost90D=sum(Cost90D),PotentialSaving=sum(AnnualizedCost) by ServiceName,OrphanReason | order by PotentialSaving desc"));

 [HttpGet("age")]
 public async Task<IActionResult> Age()=>Ok(await _adx.QueryAsync(
  "OrphanResourceFact | extend AgeBand=case(AgeDays<=30,'0-30',AgeDays<=60,'31-60',AgeDays<=90,'61-90',AgeDays<=180,'91-180','180+') | summarize Count=count(),Cost90D=sum(Cost90D) by AgeBand"));

 [HttpGet("top")]
 public async Task<IActionResult> Top(string? environment=null) {
  var f=string.IsNullOrWhiteSpace(environment)?"":$" | where Environment =~ '{environment.Replace("'","''")}'";
  return Ok(await _adx.QueryAsync($@"OrphanResourceFact{f}
 | where ReviewStatus !in ('Closed','Rejected') | top 50 by AnnualizedCost desc
 | project ResourceId,ResourceName,ServiceName,Environment,AgeDays,Cost90D,AnnualizedCost,
 Confidence,OrphanReason,DependencyStatus,Owner,Application,Recommendation,AdoWorkItemId"));
 }

 [HttpGet("resource/{resourceId}")]
 public async Task<IActionResult> Resource(string resourceId) {
  var id=resourceId.Replace("'","''");
  return Ok(await _adx.QueryAsync($"OrphanResourceFact | where ResourceId=='{id}' | top 1 by SnapshotDateUtc desc"));
 }
}
