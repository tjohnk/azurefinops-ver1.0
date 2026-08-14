using Kusto.Data;
using Kusto.Data.Common;
using Kusto.Data.Net.Client;
using System.Diagnostics;

/// <summary>
/// Service for querying Azure Data Explorer (ADX/Kusto) cluster
/// Handles connection management, query execution, and result parsing with error handling
/// </summary>
public class AdxService
{
    private readonly IConfiguration _config;
    private readonly ILogger<AdxService> _logger;
    private string? _clusterUrl;
    private string? _database;

    // Allow a protected parameterless constructor so test/mocks can derive without requiring ADX config
    protected AdxService() { }

    public AdxService(IConfiguration config, ILogger<AdxService> logger)
    {
        _config = config ?? throw new ArgumentNullException(nameof(config));
        _logger = logger ?? throw new ArgumentNullException(nameof(logger));
        ValidateConfiguration();
    }

    /// <summary>
    /// Validates that required ADX configuration is present
    /// </summary>
    private void ValidateConfiguration()
    {
        try
        {
            _clusterUrl = _config["ADX:ClusterUrl"];
            _database = _config["ADX:Database"];

            if (string.IsNullOrWhiteSpace(_clusterUrl))
                throw new InvalidOperationException("ADX:ClusterUrl is not configured");

            if (string.IsNullOrWhiteSpace(_database))
                throw new InvalidOperationException("ADX:Database is not configured");

            // Validate URL format
            if (!Uri.TryCreate(_clusterUrl, UriKind.Absolute, out _))
                throw new InvalidOperationException($"Invalid ADX cluster URL format: {_clusterUrl}");

            _logger.LogInformation("ADX configuration validated. Cluster: {ClusterUrl}, Database: {Database}", 
                MaskUrl(_clusterUrl), _database);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to validate ADX configuration");
            throw;
        }
    }

    /// <summary>
    /// Executes a KQL (Kusto Query Language) query against the ADX cluster
    /// </summary>
    /// <param name="query">The KQL query to execute</param>
    /// <param name="cancellationToken">Cancellation token for async operation</param>
    /// <returns>List of result rows as dictionaries</returns>
    public virtual async Task<List<Dictionary<string, object?>>> QueryAsync(
        string query, 
        CancellationToken cancellationToken = default)
    {
        if (string.IsNullOrWhiteSpace(query))
            throw new ArgumentException("Query cannot be null or empty", nameof(query));

        var stopwatch = Stopwatch.StartNew();
        var queryId = Guid.NewGuid().ToString("N")[..8]; // Short ID for logging

        try
        {
            _logger.LogInformation("ADX Query [{QueryId}] started. Database: {Database}", 
                queryId, _database);

            // Create connection with managed identity
            var kcsb = new KustoConnectionStringBuilder(_clusterUrl!)
                .WithAadSystemManagedIdentity();

            using var client = KustoClientFactory.CreateCslQueryProvider(kcsb);

            // Execute query
            using var reader = await client.ExecuteQueryAsync(
                _database!,
                query,
                new ClientRequestProperties(),
                cancellationToken);

            // Parse results
            var result = new List<Dictionary<string, object?>>();
            int rowCount = 0;

            while (reader.Read())
            {
                var row = new Dictionary<string, object?>();

                for (int i = 0; i < reader.FieldCount; i++)
                {
                    var fieldName = reader.GetName(i);
                    var fieldValue = reader.IsDBNull(i) ? null : reader.GetValue(i);
                    row[fieldName] = fieldValue;
                }

                result.Add(row);
                rowCount++;
            }

            stopwatch.Stop();
            _logger.LogInformation(
                "ADX Query [{QueryId}] completed successfully. Rows: {RowCount}, Duration: {DurationMs}ms",
                queryId, rowCount, stopwatch.ElapsedMilliseconds);

            return result;
        }
        catch (OperationCanceledException ex)
        {
            stopwatch.Stop();
            _logger.LogWarning(ex, "ADX Query [{QueryId}] was cancelled after {DurationMs}ms", 
                queryId, stopwatch.ElapsedMilliseconds);
            throw;
        }
        catch (Exception ex) when (IsAuthenticationFailure(ex))
        {
            stopwatch.Stop();
            _logger.LogError(ex, "ADX Query [{QueryId}] failed: Authentication error", queryId);
            throw new InvalidOperationException(
                "Failed to authenticate with ADX cluster. Ensure managed identity has appropriate permissions.", ex);
        }
        catch (Exception ex) when (IsPartialQueryFailure(ex))
        {
            stopwatch.Stop();
            _logger.LogError(ex,
                "ADX Query [{QueryId}] failed with partial results: {ErrorMessage}",
                queryId, ex.Message);
            throw new InvalidOperationException(
                $"ADX query failed: {ex.Message}. Please check your query syntax and table names.", ex);
        }
        catch (Exception ex)
        {
            stopwatch.Stop();
            _logger.LogError(ex, "ADX Query [{QueryId}] failed with unexpected error", queryId);
            throw new InvalidOperationException(
                $"Unexpected error querying ADX: {ex.Message}", ex);
        }
    }

    private static bool IsAuthenticationFailure(Exception exception) =>
        exception.Message.Contains("authentication", StringComparison.OrdinalIgnoreCase)
        || exception.Message.Contains("managed identity", StringComparison.OrdinalIgnoreCase)
        || exception.Message.Contains("token", StringComparison.OrdinalIgnoreCase)
        || exception.Message.Contains("AAD", StringComparison.OrdinalIgnoreCase);

    private static bool IsPartialQueryFailure(Exception exception) =>
        exception.Message.Contains("partial", StringComparison.OrdinalIgnoreCase)
        && exception.Message.Contains("query", StringComparison.OrdinalIgnoreCase);

    /// <summary>
    /// Helper method to mask sensitive URL parts in logs
    /// </summary>
    private static string MaskUrl(string? url)
    {
        if (string.IsNullOrEmpty(url)) return "(empty)";
        try
        {
            var uri = new Uri(url);
            return $"{uri.Scheme}://{uri.Host}";
        }
        catch
        {
            return "(invalid-url)";
        }
    }
}
