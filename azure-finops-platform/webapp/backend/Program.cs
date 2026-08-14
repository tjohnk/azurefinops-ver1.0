using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.Identity.Web;
using Microsoft.AspNetCore.Cors.Infrastructure;

var builder = WebApplication.CreateBuilder(args);

// Configure logging
builder.Logging.ClearProviders();
builder.Logging.AddConsole();
builder.Logging.AddDebug();
if (!builder.Environment.IsDevelopment())
{
    builder.Logging.AddFilter("Microsoft", LogLevel.Warning);
}

using var startupLoggerFactory = LoggerFactory.Create(logging =>
{
    logging.AddConsole();
    logging.AddDebug();
    if (!builder.Environment.IsDevelopment())
    {
        logging.AddFilter("Microsoft", LogLevel.Warning);
    }
});

var logger = startupLoggerFactory.CreateLogger("Program");
logger.LogInformation("Starting Azure Estate FinOps Intelligence Platform API");
logger.LogInformation("Environment: {Environment}", builder.Environment.EnvironmentName);

// Validate required configuration (skip strict checks in Development to allow local testing)
if (!builder.Environment.IsDevelopment())
{
    try
    {
        var config = builder.Configuration;

        // Validate Azure AD configuration
        var tenantId = config["AzureAd:TenantId"];
        var clientId = config["AzureAd:ClientId"];
        var instance = config["AzureAd:Instance"];

        if (string.IsNullOrWhiteSpace(tenantId))
            throw new InvalidOperationException("AzureAd:TenantId is not configured");
        if (string.IsNullOrWhiteSpace(clientId))
            throw new InvalidOperationException("AzureAd:ClientId is not configured");
        if (string.IsNullOrWhiteSpace(instance))
            throw new InvalidOperationException("AzureAd:Instance is not configured");

        // Validate ADX configuration
        var adxClusterUrl = config["ADX:ClusterUrl"];
        var adxDatabase = config["ADX:Database"];

        if (string.IsNullOrWhiteSpace(adxClusterUrl))
            throw new InvalidOperationException("ADX:ClusterUrl is not configured");
        if (string.IsNullOrWhiteSpace(adxDatabase))
            throw new InvalidOperationException("ADX:Database is not configured");

        // Validate URL formats
        if (!Uri.TryCreate(adxClusterUrl, UriKind.Absolute, out _))
            throw new InvalidOperationException($"Invalid ADX cluster URL format: {adxClusterUrl}");
        if (!Uri.TryCreate(instance, UriKind.Absolute, out _))
            throw new InvalidOperationException($"Invalid Azure AD instance URL format: {instance}");

        logger.LogInformation("Configuration validation successful");
        logger.LogInformation("Azure AD Tenant: {TenantId}", tenantId);
        logger.LogInformation("ADX Database: {Database}", adxDatabase);
    }
    catch (Exception ex)
    {
        logger.LogCritical(ex, "Configuration validation failed. Application cannot start.");
        throw;
    }
}

// Configure authentication
builder.Services.AddAuthentication(JwtBearerDefaults.AuthenticationScheme)
    .AddMicrosoftIdentityWebApi(builder.Configuration.GetSection("AzureAd"));

logger.LogDebug("Authentication configured");

// Configure authorization
builder.Services.AddAuthorization();

// Configure CORS
var allowedOrigins = builder.Configuration.GetSection("Cors:AllowedOrigins").Get<string[]>() 
    ?? new[] { "http://localhost:3000" };

builder.Services.AddCors(options =>
{
    options.AddPolicy("AllowFrontend", corsPolicyBuilder =>
    {
        corsPolicyBuilder
            .WithOrigins(allowedOrigins)
            .AllowAnyMethod()
            .AllowAnyHeader()
            .AllowCredentials();
    });
});

logger.LogInformation("CORS configured with origins: {Origins}", 
    string.Join(", ", allowedOrigins));

// Add services
builder.Services.AddControllers();

// Register a mock AdxService in Development so the backend can run without ADX.
if (builder.Environment.IsDevelopment())
{
    builder.Services.AddSingleton<AdxService, MockAdxService>();
}
else
{
    builder.Services.AddSingleton<AdxService>();
}

logger.LogDebug("Services registered");

// Build the app
var app = builder.Build();

logger.LogInformation("Building application middleware");

// Configure middleware
if (app.Environment.IsDevelopment())
{
    app.UseDeveloperExceptionPage();
    logger.LogDebug("Developer exception page enabled");
}

app.UseHttpsRedirection();
app.UseCors("AllowFrontend");
// In Development use the mock ADX service and skip authentication to simplify local testing
if (!app.Environment.IsDevelopment())
{
    app.UseAuthentication();
    app.UseAuthorization();
}

// Add request logging middleware
app.UseMiddleware<RequestLoggingMiddleware>();

app.MapControllers();

logger.LogInformation("Application startup complete");
app.Run();

/// <summary>
/// Middleware for logging HTTP requests and responses
/// </summary>
public class RequestLoggingMiddleware
{
    private readonly RequestDelegate _next;
    private readonly ILogger<RequestLoggingMiddleware> _logger;

    public RequestLoggingMiddleware(RequestDelegate next, ILogger<RequestLoggingMiddleware> logger)
    {
        _next = next;
        _logger = logger;
    }

    public async Task InvokeAsync(HttpContext context)
    {
        var requestId = context.TraceIdentifier;
        var startTime = DateTime.UtcNow;

        _logger.LogInformation(
            "Request started: {Method} {Path} [{RequestId}]",
            context.Request.Method,
            context.Request.Path,
            requestId);

        try
        {
            await _next(context);

            var duration = DateTime.UtcNow - startTime;
            _logger.LogInformation(
                "Request completed: {Method} {Path} - Status: {StatusCode}, Duration: {DurationMs}ms [{RequestId}]",
                context.Request.Method,
                context.Request.Path,
                context.Response.StatusCode,
                duration.TotalMilliseconds,
                requestId);
        }
        catch (Exception ex)
        {
            var duration = DateTime.UtcNow - startTime;
            _logger.LogError(ex,
                "Request failed: {Method} {Path}, Duration: {DurationMs}ms [{RequestId}]",
                context.Request.Method,
                context.Request.Path,
                duration.TotalMilliseconds,
                requestId);
            throw;
        }
    }
}
