
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

[ApiController,Authorize,Route("api/orphans/actions")]
public class OrphanActionsController : ControllerBase {
 [HttpPost("work-item-request")]
 public IActionResult WorkItem([FromBody] Request r)=>Ok(new {
   status="READY_FOR_ADO_INTEGRATION",
   title=$"Review orphaned Azure resource: {r.ResourceName}",
   resourceId=r.ResourceId, environment=r.Environment,
   reason=r.OrphanReason, estimatedAnnualCost=r.AnnualizedCost
 });
}
public record Request(string ResourceId,string ResourceName,string Environment,string OrphanReason,decimal AnnualizedCost);
