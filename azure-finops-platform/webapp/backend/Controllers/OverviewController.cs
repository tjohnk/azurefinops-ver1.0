using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using System.Text.RegularExpressions;

/// <summary>
/// Controller for Azure resource adoption overview and analytics
/// Provides aggregated resource usage statistics across environments
/// </summary>
[ApiController]
[Authorize]
[Route("api/overview")]
public class OverviewController : ControllerBase
{
    private readonly AdxService _adx;
    private readonly ILogger<OverviewController> _logger;

    public OverviewController(AdxService adx, ILogger<OverviewController> logger)
    {
        _adx = adx ?? throw new ArgumentNullException(nameof(adx));
        _logger = logger ?? throw new ArgumentNullException(nameof(logger));
    }

    /// <summary>
    /// Gets resource adoption statistics, optionally filtered by environment
    /// </summary>
    /// <param name="environment">Optional environment filter (validated against allowed values)</param>
    /// <returns>Resource adoption metrics with usage status breakdown</returns>
    [HttpGet]
    [ProducesResponseType(typeof(IEnumerable<object>), 200)]
    [ProducesResponseType(400)]
    [ProducesResponseType(500)]
    public async Task<IActionResult> Get([FromQuery] string? environment = null)
    {
        try
        {
            _logger.LogInformation("Overview requested for environment: {Environment}", 
                environment ?? "all");

            // Validate and sanitize environment parameter
            var filter = string.Empty;
            if (!string.IsNullOrWhiteSpace(environment))
            {
                // Whitelist validation: only allow alphanumeric, hyphens, and underscores
                if (!IsValidEnvironmentName(environment))
                {
                    _logger.LogWarning("Invalid environment name requested: {Environment}", environment);
                    return BadRequest(new { error = "Invalid environment name format" });
                }

                // Use parameterized approach instead of string interpolation.
                // Column name matches the canonical schema (PascalCase "Environment").
                filter = $" | where Environment == '{EscapeKustoLiteral(environment)}'";
            }

            // Build KQL query with safe concatenation.
            // NOTE: this previously queried a table called "ResourceAdoptionMaster"
            // that was never defined in any schema file in the source packages.
            // It is now computed directly from the two tables that actually carry
            // this information: ResourceUsageFact (Active/LowUsage/Inactive/NeverUsed)
            // and OrphanResourceFact (orphan status is a separate concept, layered
            // on top rather than being one more UsageStatus value).
            var query = $@"
let usage = ResourceUsageFact
| summarize arg_max(TimestampUtc, *) by ResourceId
{filter}
| project ResourceId, Environment, UsageStatus;
let orphans = OrphanResourceFact
| summarize arg_max(SnapshotDateUtc, *) by ResourceId
{filter}
| where ReviewStatus !in ('Closed','Rejected')
| project ResourceId, IsOrphaned=true;
usage
| join kind=leftouter orphans on ResourceId
| extend Bucket = case(
    isnotempty(IsOrphaned), 'Orphaned',
    UsageStatus == 'Active', 'Active',
    UsageStatus == 'LowUsage', 'LowUsage',
    'NoUsage')
| summarize TotalResources=count(),
    Active=countif(Bucket == 'Active'),
    LowUsage=countif(Bucket == 'LowUsage'),
    NoUsage=countif(Bucket == 'NoUsage'),
    Orphaned=countif(Bucket == 'Orphaned')
| extend AdoptionPercent=round(100.0*todouble(Active)/TotalResources,2)";

            _logger.LogDebug("Executing overview query for environment: {Environment}", 
                environment ?? "all");

            var result = await _adx.QueryAsync(query);

            _logger.LogInformation("Overview query completed. Rows returned: {RowCount}", 
                result?.Count ?? 0);

            return Ok(result);
        }
        catch (InvalidOperationException ex)
        {
            _logger.LogError(ex, "Query execution failed");
            return StatusCode(500, new { error = "Failed to retrieve adoption overview" });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Unexpected error in overview endpoint");
            return StatusCode(500, new { error = "An unexpected error occurred" });
        }
    }

    /// <summary>
    /// Top 10 services by resource count (the "Top 10 Services by Resource Count" panel).
    /// The PowerShell collector already gathers serviceName per resource via Resource
    /// Graph — this was previously computed only inside DashboardDataHelper.psm1's
    /// dashboardServiceAdoption output, with no live API endpoint serving it. This
    /// queries the same underlying data (ResourceInventory) directly from ADX instead.
    /// </summary>
    [HttpGet("top-services")]
    public async Task<IActionResult> TopServices([FromQuery] string? environment = null, [FromQuery] int top = 10)
    {
        top = Math.Clamp(top, 1, 50);
        var filter = EnvironmentFilter(environment, out var badRequest);
        if (badRequest != null) return badRequest;

        var query = $@"
ResourceInventory
| summarize arg_max(snapshotDateUtc, *) by resourceId
{filter}
| summarize ResourceCount=count() by ServiceName=serviceName
| top {top} by ResourceCount desc";
        return Ok(await _adx.QueryAsync(query));
    }

    /// <summary>
    /// Adoption % (share of Active resources) per service — the "Service Adoption
    /// (% Active Resources)" panel. Joins ResourceInventory (for serviceName) with
    /// ResourceUsageFact (for UsageStatus), same join pattern as the main Get() query.
    /// </summary>
    [HttpGet("service-adoption")]
    public async Task<IActionResult> ServiceAdoption([FromQuery] string? environment = null, [FromQuery] int top = 10)
    {
        top = Math.Clamp(top, 1, 50);
        var filter = EnvironmentFilter(environment, out var badRequest);
        if (badRequest != null) return badRequest;

        var query = $@"
let inventory = ResourceInventory
| summarize arg_max(snapshotDateUtc, *) by resourceId
{filter}
| project resourceId, ServiceName=serviceName;
let usage = ResourceUsageFact
| summarize arg_max(TimestampUtc, *) by ResourceId
| project ResourceId, UsageStatus;
inventory
| join kind=leftouter usage on $left.resourceId == $right.ResourceId
| summarize TotalResources=count(), ActiveResources=countif(UsageStatus == 'Active') by ServiceName
| extend AdoptionPercent=round(100.0*todouble(ActiveResources)/TotalResources,2)
| top {top} by TotalResources desc";
        return Ok(await _adx.QueryAsync(query));
    }

    /// <summary>
    /// Resource count by Azure region — the "Resources by Location (Top 10)" panel.
    /// </summary>
    [HttpGet("locations")]
    public async Task<IActionResult> Locations([FromQuery] string? environment = null, [FromQuery] int top = 10)
    {
        top = Math.Clamp(top, 1, 50);
        var filter = EnvironmentFilter(environment, out var badRequest);
        if (badRequest != null) return badRequest;

        var query = $@"
ResourceInventory
| summarize arg_max(snapshotDateUtc, *) by resourceId
{filter}
| summarize ResourceCount=count() by Location=location
| top {top} by ResourceCount desc";
        return Ok(await _adx.QueryAsync(query));
    }

    /// <summary>
    /// Shared environment-filter builder used by every endpoint above, so the same
    /// validation/escaping logic (and the same bad-request response) isn't duplicated
    /// four times. Returns the KQL filter clause, or sets badRequest and returns "".
    /// </summary>
    private string EnvironmentFilter(string? environment, out IActionResult? badRequest)
    {
        badRequest = null;
        if (string.IsNullOrWhiteSpace(environment))
            return string.Empty;

        if (!IsValidEnvironmentName(environment))
        {
            _logger.LogWarning("Invalid environment name requested: {Environment}", environment);
            badRequest = BadRequest(new { error = "Invalid environment name format" });
            return string.Empty;
        }

        return $" | where environment == '{EscapeKustoLiteral(environment)}'";
    }

    /// <summary>
    /// Validates environment name format (alphanumeric, hyphen, underscore only)
    /// </summary>
    private static bool IsValidEnvironmentName(string? name)
    {
        if (string.IsNullOrWhiteSpace(name))
            return false;

        // Allow only alphanumeric characters, hyphens, and underscores
        // Maximum 50 characters to prevent abuse
        return name.Length <= 50 && Regex.IsMatch(name, @"^[a-zA-Z0-9_-]+$");
    }

    /// <summary>
    /// Escapes single quotes in Kusto literal strings to prevent injection
    /// </summary>
    private static string EscapeKustoLiteral(string value)
    {
        if (string.IsNullOrEmpty(value))
            return string.Empty;

        // In KQL, single quotes are escaped by doubling them
        return value.Replace("'", "''");
    }
}
