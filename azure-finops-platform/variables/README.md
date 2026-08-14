# Tenant Variables Configuration

This folder contains all configuration variables for multi-tenant Azure Estate FinOps Intelligence Platform deployments.

## Folder Structure

### `/shared`
Contains mappings and configurations that are **tenant-agnostic** and should be identical across all tenants:
- `service-mapping.json` - Maps Azure resource types to service categories and names
- `metric-mapping.json` - Defines metrics collected from each resource type

### `/environments`
Contains **tenant-specific** configurations:
- `subscriptions.json` - List of Azure subscriptions to monitor
- `tenant-config.json` - Tenant-specific settings for storage, ADX, and web app

### `/templates`
Contains **templates** for quick setup of new tenants:
- `tenant-template.json` - Complete template with all required configuration fields

## How to Use for a New Tenant

1. **Create a new tenant folder** under `/environments`:
   ```
   mkdir variables/environments/my-tenant
   ```

2. **Copy template files** to your tenant folder:
   ```
   cp variables/templates/tenant-template.json variables/environments/my-tenant/config.json
   ```

3. **Edit the configuration** with your tenant-specific values:
   - Replace all `<REPLACE-*>` placeholders
   - Update Azure subscription IDs
   - Configure ADX cluster details
   - Set storage account names

4. **Reference in scripts** via environment variable or parameter:
   ```powershell
   $configPath = "./variables/environments/my-tenant"
   $tenantConfig = Get-Content "$configPath/config.json" -Raw | ConvertFrom-Json
   ```

## Example Multi-Tenant Setup

```
variables/
├── shared/
│   ├── service-mapping.json
│   └── metric-mapping.json
├── environments/
│   ├── subscriptions.json        (shared across all tenants in this deployment)
│   ├── tenant-config.json
│   ├── acme-corp/               (tenant-specific)
│   │   └── config.json
│   └── contoso-inc/             (tenant-specific)
│       └── config.json
└── templates/
	└── tenant-template.json
```

## Security Best Practices

⚠️ **IMPORTANT**: These files contain sensitive configuration data. 

- **Never commit secrets** to source control
- Use **Azure Key Vault** for sensitive values in production
- Use **environment variables** or **Azure Pipeline secrets** for CI/CD
- Restrict **file permissions** on configuration directories
- Consider using **Azure App Configuration Service** for centralized management

## Environment Variables for Scripts

For PowerShell scripts, set these environment variables before execution:

```powershell
$env:TENANT_CONFIG_PATH = ".\variables\environments\my-tenant\config.json"
$env:SHARED_CONFIG_PATH = ".\variables\shared"
```

Then scripts will automatically load configuration from these paths.

## Deployment Pipeline Integration

The Azure Pipeline (azure-adoption-no-csv.yml) should:

1. Reference the correct tenant configuration path
2. Use pipeline variables for secret values (stored in Azure DevOps)
3. Pass configuration to PowerShell scripts and web app settings

See `DEPLOYMENT_GUIDE.md` for detailed pipeline configuration.
