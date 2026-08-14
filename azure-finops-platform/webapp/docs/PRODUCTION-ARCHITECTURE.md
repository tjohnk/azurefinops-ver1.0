# Production architecture

Users -> Microsoft Entra ID -> Azure App Service -> ASP.NET Core API -> ADX.

Collector -> Azure DevOps WIF -> Azure APIs -> ADLS -> ADX.

Use a separate identity for the collector and the web application. The web application's managed identity should receive read-only access to the ADX database. The collector identity retains Azure collection permissions.

For a hardened enterprise deployment, consider VNet integration/private endpoints and Application Gateway/WAF. Azure Architecture Center documents a baseline App Service architecture using App Gateway/WAF, Private Link, VNet integration, Entra ID and Azure Monitor.
