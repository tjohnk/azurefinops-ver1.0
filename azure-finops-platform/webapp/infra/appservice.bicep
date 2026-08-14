param location string = resourceGroup().location
param appName string
param adxClusterUrl string
param adxDatabase string
param tenantId string = ''
param clientId string = ''
param corsOrigins array = ['http://localhost:3000']
param skuName string = 'P1v3'
param skuTier string = 'PremiumV3'
param minTlsVersion string = '1.2'
param httpsOnly bool = true
param alwaysOn bool = true

// Validation
var validSkuSizes = ['B1', 'B2', 'B3', 'S1', 'S2', 'S3', 'P1v2', 'P2v2', 'P3v2', 'P1v3', 'P2v3', 'P3v3']

@description('App Service Plan resource')
resource plan 'Microsoft.Web/serverfarms@2024-04-01' = {
  name: '${appName}-plan'
  location: location
  kind: 'linux'
  sku: {
    name: skuName
    tier: skuTier
  }
  properties: {
    reserved: true
  }
}

@description('App Service web app with system-assigned managed identity')
resource app 'Microsoft.Web/sites@2024-04-01' = {
  name: appName
  location: location
  kind: 'app,linux'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: plan.id
    httpsOnly: httpsOnly
    virtualNetworkSubnetId: null
    clientAffinityEnabled: false
    siteConfig: {
      linuxFxVersion: 'DOTNETCORE|8.0'
      alwaysOn: alwaysOn
      minTlsVersion: minTlsVersion
      ftpsState: 'Disabled'
      http20Enabled: true
      managedPipelineMode: 'Integrated'

      appSettings: [
        {
          name: 'ASPNETCORE_ENVIRONMENT'
          value: 'Production'
        }
        {
          name: 'ADX__ClusterUrl'
          value: adxClusterUrl
        }
        {
          name: 'ADX__Database'
          value: adxDatabase
        }
        {
          name: 'AzureAd__Instance'
          value: 'https://login.microsoftonline.com/'
        }
        {
          name: 'AzureAd__TenantId'
          value: tenantId
        }
        {
          name: 'AzureAd__ClientId'
          value: clientId
        }
        {
          name: 'Cors__AllowedOrigins__0'
          value: corsOrigins[0]
        }
        {
          name: 'Logging__LogLevel__Default'
          value: 'Information'
        }
        {
          name: 'Logging__LogLevel__Microsoft'
          value: 'Warning'
        }
      ]

      connectionStrings: []

      defaultDocuments: []

      ipSecurityRestrictions: [
        {
          ipAddress: 'Any'
          action: 'Allow'
          priority: 2147483647
          name: 'Allow all'
          description: 'Allow all access'
        }
      ]

      cors: {
        allowedOrigins: corsOrigins
        supportCredentials: true
      }
    }
  }
}

@description('Diagnostic settings for app insights')
resource diagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: '${appName}-diagnostics'
  scope: app
  properties: {
    workspaceId: ''
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: 30
        }
      }
    ]
    logs: [
      {
        category: 'AppServiceHTTPLogs'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: 30
        }
      }
      {
        category: 'AppServiceConsoleLogs'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: 30
        }
      }
      {
        category: 'AppServicePlatformLogs'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: 30
        }
      }
    ]
  }
}

@description('Web app outputs for downstream configuration')
output webAppName string = app.name
output webAppId string = app.id
output principalId string = app.identity.principalId
output hostName string = app.properties.defaultHostName
output appServicePlanId string = plan.id
