using System.Text.Json;

/// <summary>
/// Development-only mock AdxService that reads prebuilt JSON files from mock/data
/// and returns lists of dictionary rows. Register this in DI only for Development.
/// </summary>
public class MockAdxService : AdxService
{
    private readonly string _dataFolder;

    public MockAdxService(IConfiguration config = null)
    {
        // default folder relative to project root when running via `dotnet run`
        var baseDir = Directory.GetCurrentDirectory();
        _dataFolder = Path.Combine(baseDir, "mock", "data");
    }

    public override Task<List<Dictionary<string, object?>>> QueryAsync(string query, CancellationToken cancellationToken = default)
    {
        // choose file by simple heuristics on the query text
        var key = "default";
        var q = (query ?? string.Empty).ToLowerInvariant();
        if (q.Contains("orphanresourcefact")) key = "orphanresourcefact";
        else if (q.Contains("resourceusagefact")) key = "resourceusagefact";
        else if (q.Contains("costanalysisfact")) key = "costanalysisfact";
        else if (q.Contains("costbudgetfact")) key = "costbudgetfact";
        else if (q.Contains("costforecastfact")) key = "costforecastfact";
        else if (q.Contains("costanomalyfact")) key = "costanomalyfact";
        else if (q.Contains("finopsoptimizationfact")) key = "finopsoptimizationfact";

        var path = Path.Combine(_dataFolder, key + ".json");
        if (!File.Exists(path))
        {
            return Task.FromResult(new List<Dictionary<string, object?>>());
        }

        var json = File.ReadAllText(path);
        try
        {
            var doc = JsonDocument.Parse(json);
            var rows = new List<Dictionary<string, object?>>();
            if (doc.RootElement.ValueKind == JsonValueKind.Array)
            {
                foreach (var el in doc.RootElement.EnumerateArray())
                {
                    var dict = new Dictionary<string, object?>();
                    if (el.ValueKind == JsonValueKind.Object)
                    {
                        foreach (var prop in el.EnumerateObject())
                        {
                            dict[prop.Name] = prop.Value.ValueKind switch
                            {
                                JsonValueKind.Number => prop.Value.GetDouble(),
                                JsonValueKind.String => prop.Value.GetString(),
                                JsonValueKind.True => true,
                                JsonValueKind.False => false,
                                JsonValueKind.Null => null,
                                _ => prop.Value.GetRawText()
                            };
                        }
                    }
                    rows.Add(dict);
                }
            }

            return Task.FromResult(rows);
        }
        catch
        {
            return Task.FromResult(new List<Dictionary<string, object?>>());
        }
    }
}
