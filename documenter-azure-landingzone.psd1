@{
    # Module metadata
    RootModule        = 'documenter-azure-landingzone.psm1'
    ModuleVersion     = '1.1.1'
    GUID              = 'd3d0da85-9b23-4c31-9861-2cad60ef45f5'
    Author            = 'Alex ter Neuzen'
    CompanyName       = 'GetToTheCloud'
    Copyright         = '(c) 2025 Alex ter Neuzen. All rights reserved.'
    Description       = 'Comprehensive inventory and documentation tool for Azure Landing Zone environments. Collects management groups, subscriptions, policies, RBAC, networking, and governance settings and presents them in a local web-based dashboard with CAF compliance assessment, WAF scoring across 5 pillars, and professional PDF export.'
    PowerShellVersion = '7.0'

    # Required modules (installed from PSGallery on demand by the module)
    RequiredModules = @(
        @{ ModuleName = 'Az.Accounts';      ModuleVersion = '2.0.0' }
        @{ ModuleName = 'Az.Resources';     ModuleVersion = '6.0.0' }
        @{ ModuleName = 'Az.Network';       ModuleVersion = '5.0.0' }
        @{ ModuleName = 'Az.PolicyInsights'; ModuleVersion = '1.0.0' }
    )

    # Exports
    FunctionsToExport = @('Get-AzureLandingZoneInventory', 'Start-AzureLandingZoneServer')
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()

    # All files that are part of the module package
    FileList = @(
        'documenter-azure-landingzone.psd1'
        'documenter-azure-landingzone.psm1'
        'Get-AzureLandingZoneInventory.ps1'
        'Start-AzureLandingZoneServer.ps1'
        'index.html'
        'app.js'
        'styles.css'
        'scoring-config.json'
        'waf-config.json'
        'LICENSE'
        'README.md'
        'changes.md'
        'start.sh'
        'start.cmd'
    )

    PrivateData = @{
        PSData = @{
            Tags        = @(
                'Azure'
                'LandingZone'
                'AzureLandingZone'
                'CloudAdoptionFramework'
                'CAF'
                'WAF'
                'WellArchitectedFramework'
                'Inventory'
                'Governance'
                'Policy'
                'RBAC'
                'Dashboard'
                'Documentation'
                'Documenter'
                'ManagementGroups'
                'Subscriptions'
                'Networking'
            )
            LicenseUri   = 'https://github.com/GetToThe-Cloud/documenter-azure-landingzone/blob/main/LICENSE'
            ProjectUri   = 'https://github.com/GetToThe-Cloud/documenter-azure-landingzone'
            IconUri      = ''
            ReleaseNotes = @'
v1.1.1 (policy and RBAC assignment inventory fix — see changes.md)
  - Scoped policy and role assignment collection to management groups and subscriptions
  - De-duplicated inherited policy assignments by PolicyAssignmentId

v1.1.0 (security hardening — see changes.md)
  - Removed wildcard CORS header; API is now same-origin only
  - CSRF protection: /api/auth/login and /api/inventory/refresh require POST + X-Requested-With header
  - Az context file moved to ~/.documenter-azure-landingzone (0700/0600), deleted after use and on shutdown
  - Replaced Invoke-Expression / eval() condition evaluation with a strict safe parser
  - All Azure-derived values HTML-escaped in the dashboard (XSS fix)
  - Subresource Integrity + Content-Security-Policy for CDN assets; X-Content-Type-Options: nosniff
  - Az modules are no longer auto-updated (install-if-missing only; manual Update-Module advised)
  - API errors return generic messages; details go to the server console only

v1.0.0
  - Initial release of the Azure Landing Zone Inventory & Assessment Tool
  - Comprehensive inventory collection: management groups, subscriptions, policies, RBAC, networking
  - CAF compliance assessment with automated scoring
  - WAF alignment scoring across 5 pillars (Reliability, Security, Cost, Operations, Performance)
  - Interactive local web dashboard with real-time data
  - Professional PDF export with tables, charts, and recommendations
  - Automatic module management (auto-install required Az modules)
  - Cross-subscription scanning across all accessible Azure subscriptions
  - Graceful Ctrl+C / server shutdown handling
'@
        }
    }
}
