# 🏢 Azure Landing Zone Inventory & Assessment Tool

A comprehensive web-based inventory and assessment dashboard for Azure Landing Zone environments. This tool provides real-time visibility into your Azure infrastructure and evaluates compliance against Microsoft Cloud Adoption Framework (CAF) and Well-Architected Framework (WAF) best practices.

![Azure Landing Zone](https://img.shields.io/badge/Azure-Landing%20Zone-0078D4?style=for-the-badge&logo=microsoft-azure)
![PowerShell](https://img.shields.io/badge/PowerShell-7+-5391FE?style=for-the-badge&logo=powershell)
![Version](https://img.shields.io/badge/Version-1.4.0-blue?style=for-the-badge)
![License](https://img.shields.io/badge/License-MIT-green?style=for-the-badge)

## 🌟 Overview

The Azure Landing Zone Inventory Tool automatically collects and analyzes your Azure environment to provide:
- **Complete Infrastructure Inventory**: All resources across management groups and subscriptions
- **CAF Compliance Assessment**: Automated evaluation against Cloud Adoption Framework principles
- **WAF Alignment Scoring**: Assessment across 5 pillars (Reliability, Security, Cost, Operations, Performance)
- **Professional PDF Reports**: GetToTheCloud-branded documentation with tables, assessments, and recommendations
- **Real-Time Dashboard**: Interactive web interface with detailed resource information
- **Automatic Module Management**: Installs missing required PowerShell modules

**Version:** 1.4.0
**Created by:** Alex ter Neuzen for [GetToTheCloud](https://www.gettothe.cloud)

## ✨ Key Features

### 📊 Comprehensive Inventory
- **Management Groups**: Full hierarchy with parent-child relationships
- **Subscriptions**: State, tags, and placement tracking
- **Azure Policy**: Definitions (custom + built-in), initiatives, and assignments
- **RBAC**: Complete role assignment mapping with principal details
- **Networking**: 
  - Virtual Networks and flat subnet inventory with address prefixes, service endpoints, delegations, route tables, and NSGs
  - Route tables with user-defined routes, next hops, BGP propagation, and associated subnets
  - VNet Peerings with connectivity status and traffic settings
  - Virtual WANs and Virtual Hubs with hub-to-VNet connections and routing state
  - VPN Gateways with SKUs, BGP, and active-active settings
  - ExpressRoute Circuits with bandwidth and provider details
  - Azure Firewalls with tier and threat intelligence modes
  - Firewall Policies with rule collection statistics and IDS/IPS
  - Network Security Groups with complete custom/default rules and **associated subnets and NICs**
  - Private DNS Zones with **VNet links and record sets**
  - Private Endpoints with **connected PaaS resources, subnet placement, and private IPs**
- **Compute**: Virtual Machines with power states and network details
- **Governance**: 
  - Cost Management Budgets with thresholds and alerts
  - Resource Locks at subscription, resource group, and resource levels
  - Tags collected from subscriptions, resource groups, and resources
  - Diagnostic Settings configuration

### 🎯 Assessment & Scoring
- **Cloud Adoption Framework (CAF)**: Evaluates 7 design areas
  - Management Group Hierarchy
  - Policy-Driven Governance
  - Identity and Access Management (RBAC)
  - Network Topology and Connectivity
  - Security Governance
  - Cost Management
  - Resource Organization
  
- **Well-Architected Framework (WAF)**: Scores 5 pillars
  - Reliability (network redundancy, resource locks)
  - Security (policies, RBAC, NSGs, firewalls)
  - Cost Optimization (budgets, tagging strategies)
  - Operational Excellence (management hierarchy, automation)
  - Performance Efficiency (network topology, connectivity)

### ⚙️ Customizable Scoring Configuration

Both CAF and WAF assessment scoring are now **fully configurable** through external JSON configuration files, making it easy to:
- **View Scoring Rules**: See exactly how each category and pillar is scored
- **Understand Thresholds**: View the percentage thresholds for Excellent/Good/Fair/Needs Improvement ratings
- **Customize Calculations**: Modify point values, conditions, and recommendations to match your organization's requirements
- **Add New Rules**: Extend the assessment with additional criteria
- **Adjust Weights**: Change the importance of different categories

#### Configuration Files

**`scoring-config.json`** - Cloud Adoption Framework (CAF) Assessment
- **Categories**: 7 assessment categories (Management Groups, Policies, IAM, Network, Security, Cost, Resources)
- **Rules**: Individual scoring rules with conditions and point values
- **Partial Points**: Rules that can award partial credit if main conditions aren't met
- **Thresholds**: Percentage breakpoints for overall ratings
- **Recommendations**: Actionable guidance when rules aren't met

**`waf-config.json`** - Well-Architected Framework (WAF) Assessment  
- **Pillars**: 5 WAF pillars (Reliability, Security, Cost Optimization, Operational Excellence, Performance Efficiency)
- **Checks**: Assessment checks with conditions and weights
- **Messages**: Pass/fail messages with dynamic placeholder support (e.g., `{policyAssignmentCount}`)
- **Descriptions**: Pillar descriptions and assessment guidance
- **Thresholds**: Color-coded scoring thresholds for each rating level

#### Viewing Scoring Configuration

Navigate to the **"⚙️ CAF/WAF Scoring Configuration"** section in the dashboard to see:

**For CAF (Cloud Adoption Framework):**
- Current configuration version and last update date
- All scoring categories with their maximum possible scores
- Individual rules with conditions, point values, and recommendations
- Partial point opportunities
- Rating thresholds and their associated messages

**For WAF (Well-Architected Framework):**
- Configuration version and metadata
- All 5 pillars with their assessment focus
- Individual checks per pillar with conditions and weights
- Pass/fail messages for each check
- Overall pillar scoring methodology

#### Customizing the Scoring

To modify the assessment calculations:

**For CAF Scoring:**
1. **Edit the configuration file**: `azurelandingzone-inventory/scoring-config.json`
2. **Adjust values**:
   - Change `points` to increase/decrease rule importance
   - Modify `condition` expressions to change when points are awarded
   - Update `maxScore` for categories to adjust weighting
   - Edit `recommendations` to provide specific guidance
3. **Update thresholds**: Change the minimum percentage for each rating level
4. **Refresh inventory**: Re-run the data collection to see updated scores

**For WAF Scoring:**
1. **Edit the configuration file**: `azurelandingzone-inventory/waf-config.json`
2. **Adjust values**:
   - Change `weight` to increase/decrease check importance
   - Modify `condition` expressions to change when checks pass
   - Update `passMessage` and `failMessage` for custom feedback
   - Edit `description` and `assessment` text for pillar context
3. **Update thresholds**: Modify the scoring thresholds in the `thresholds` section
4. **Refresh inventory**: Re-run the data collection to see updated scores

#### Example Rule Configuration

```json
{
  "id": "pol-002",
  "name": "Policy Assignments at Scale",
  "description": "Comprehensive policy assignments across the organization",
  "condition": "policyAssigns >= 5",
  "points": 10,
  "partialPoints": {
    "condition": "policyAssigns > 0",
    "points": 5
  },
  "recommendation": "Assign Azure Policy initiatives (e.g., Azure Security Benchmark)"
}
```

**Condition Syntax** for rules:
- **Comparison operators**: `>`, `>=`, `<`, `<=`, `==`, `!=`
- **Logical operators**: `AND`, `OR`
- **Examples**:
  - Simple: `vnetCount >= 2`
  - With AND: `peeringCount > 0 AND vnetCount >= 2`
  - With OR: `vpnCount > 0 OR fwCount > 0`
  - Boolean: `hasPrivilegedRoles == true`

**Available Metrics** in conditions:
- `mgCount` - Number of management groups
- `subCount` - Number of subscriptions
- `policyDefs` - Custom policy definitions
- `policyInits` - Policy initiatives
- `policyAssigns` - Policy assignments
- `roleAssigns` - RBAC role assignments
- `vnetCount` - Virtual networks
- `peeringCount` - VNet peerings
- `vpnCount` - VPN gateways
- `fwCount` - Azure Firewalls
- `expressRouteCount` - ExpressRoute circuits
- `privateDnsCount` - Private DNS zones
- `defenderCount` - Defender for Cloud pricing plans
- `locks` - Resource locks
- `nsgCount` - Network security groups
- `budgets` - Cost management budgets
- `tagCount` - Unique tag keys
- `hasPrivilegedRoles` - Boolean for Owner/Contributor roles

### 📄 Advanced Reporting & Data Export
- **Professional PDF Export**: Multi-page reports with:
  - Executive summary with key metrics and scores
  - CAF compliance assessment with detailed findings
  - WAF pillar analysis with individual scores
  - Management Groups hierarchy table
  - Subscriptions with state and tags
  - Virtual Networks and peering relationships
  - Virtual WANs, VPN Gateways, and ExpressRoute circuits
  - Azure Firewalls and Firewall Policies with rule statistics
  - Policy definitions and assignments
  - Role assignments distribution
  - Governance resources (budgets, locks, tags)
  - Actionable recommendations
  - Custom watermark on every page
  
- **JSON Data Export**: Raw inventory data export for:
  - Offline analysis and processing
  - Integration with other tools and platforms
  - Historical comparison and trending
  - Custom reporting and automation
  - Data archiving and compliance
  - Machine learning and analytics
  - **Format**: Beautifully formatted, indented JSON
  - **Filename**: Timestamped (e.g., `azure-resources-export-2026-03-06T14-30-45.json`)
  - **Contains**: **Only Azure resources and their details** (no assessments or summary calculations)
    - Management Groups with hierarchy
    - Subscriptions with state and tags
    - Policy definitions, initiatives, and assignments
    - RBAC role assignments
    - Networking resources (VNets, peerings, firewalls, VPN gateways, etc.)
    - Virtual machines with configuration
    - Governance resources (budgets, locks, tags)
    - Metadata with resource counts and export timestamp

- **Live Dashboard**: Real-time view with:
  - Progress bar during data collection
  - Interactive navigation between categories
  - Sortable data tables
  - Summary cards with key statistics

## 📋 Prerequisites

### Required Software
- **PowerShell 7.0 or higher** (pwsh)
  - Download: [https://aka.ms/powershell](https://aka.ms/powershell)
  - Verify: `pwsh --version`

### Required Azure PowerShell Modules

The tool **automatically checks and installs missing** modules on startup (Scope: CurrentUser):

- **Az.Accounts** - Azure authentication and context management
- **Az.Resources** - Resource, policy, and management group operations
- **Az.Network** - Virtual networks, VPN gateways, firewalls, DNS
- **Az.PolicyInsights** - Policy compliance and remediation data

**Note:** Missing modules are installed automatically on startup. Already-installed modules are **never** updated automatically — if a newer version is available, the server prints a notice and you can update manually with `Update-Module <name>`.

### Manual Installation (Optional)

If you prefer to install modules manually before running:

```powershell
# Install required modules
Install-Module -Name Az.Accounts -Scope CurrentUser -Force
Install-Module -Name Az.Resources -Scope CurrentUser -Force
Install-Module -Name Az.Network -Scope CurrentUser -Force
Install-Module -Name Az.PolicyInsights -Scope CurrentUser -Force

# Update to latest versions
Update-Module -Name Az.Accounts -Force
Update-Module -Name Az.Resources -Force
Update-Module -Name Az.Network -Force
Update-Module -Name Az.PolicyInsights -Force
```

## 🔐 Azure Permissions Requirements

### Minimum Required Permissions

For **complete inventory** including management groups:

1. **Management Group Reader** role:
   - Scope: Tenant Root Management Group
   - Purpose: Read management group hierarchy
   - **Critical**: Without this, management groups will not be collected

2. **Reader** role:
   - Scope: Subscriptions or Management Groups you want to inventory
   - Purpose: Read all resources, policies, and configurations

### Permission Details

| Resource Type | Required Permission | Scope | Notes |
|--------------|-------------------|-------|-------|
| Management Groups | Management Group Reader | Tenant Root | Tenant-level permission required |
| Subscriptions | Reader | Subscription(s) | Or inherited from Management Group |
| Policies | Reader or Policy Reader | Subscription/MG | Built into Reader role |
| RBAC Roles | Reader | Subscription/MG | View role assignments |
| Networking | Reader | Subscription(s) | VNets, Firewalls, VPN, etc. |
| VMs & Compute | Reader | Subscription(s) | Virtual machines |
| Governance | Reader | Subscription(s) | Budgets, locks, tags |

### Checking Your Permissions

```powershell
# Check your current Azure context
Get-AzContext

# List role assignments for your account
Get-AzRoleAssignment -SignInName your.email@domain.com

# Check management group access
Get-AzManagementGroup
```

### Common Permission Issues

**Problem:** "Management Groups: 0" displayed even though they exist

**Cause:** Missing "Management Group Reader" role at tenant level

**Solution:**
1. Contact your Azure Global Administrator or Privileged Role Administrator
2. Request "Management Group Reader" role assignment at "/" (tenant root) scope
3. PowerShell command for admin to grant access:
   ```powershell
   New-AzRoleAssignment -SignInName user@domain.com `
       -RoleDefinitionName "Management Group Reader" `
       -Scope "/"
   ```

**Problem:** "Limited access to Management Groups" warning

**Cause:** Subscription-level resource provider registration check (misleading error)

**Solution:** The tool automatically handles this - uses tenant-level API calls to bypass subscription checks

## 🚀 Quick Start

### Step 1: Download or Clone

```bash
git clone https://github.com/GetToThe-Cloud/documenter-azure-landingzone.git
cd AzureDocumenter/azurelandingzone-inventory
```

### Step 2: Start the Server

#### macOS/Linux
```bash
chmod +x start.sh
./start.sh
```

#### Windows
```cmd
start.cmd
```

#### PowerShell (Any Platform)
```powershell
pwsh -File Start-AzureLandingZoneServer.ps1
```

### Step 3: Use the Tool

1. **Server Startup**: 
   - PowerShell 7 version check
   - Automatic module installation/update (2-5 minutes first time)
   - Azure authentication status check
   - Server starts on http://localhost:8080
    - Press Ctrl+C in the same terminal to stop the server cleanly

2. **Web Interface**:
   - Open browser to `http://localhost:8080`
   - Click "Sign in to Azure" button
   - Follow device code authentication flow
   - Wait for data collection (2-10 minutes depending on tenant size)
   - Navigate through categories in sidebar

3. **Export Data**:
   - Click "💾 Export JSON" button for clean resource data export (no assessments - pure resource details)
   - Click "📄 Export PDF" button for comprehensive assessment report
   - PDF includes all tables, CAF/WAF assessments, scores, and recommendations
   - JSON includes only resource configurations and metadata for processing/integration

## 🗂️ Project Structure

```
azurelandingzone-inventory/
├── Start-AzureLandingZoneServer.ps1    # HTTP server with auto module management
├── Get-AzureLandingZoneInventory.ps1   # Data collection engine (v1.3.0)
├── scoring-config.json                  # CAF scoring rules configuration
├── waf-config.json                      # WAF pillar assessment configuration
├── index.html                           # Dashboard interface with progress bar
├── styles.css                           # UI styling
├── app.js                               # Frontend logic, PDF & JSON export
├── gettothecloud-logo.webp              # Packaged PDF report wordmark
├── start.sh                            # Unix startup script
├── start.cmd                           # Windows startup script
└── README.md                           # This file
```

### File Details

**Start-AzureLandingZoneServer.ps1**
- PowerShell 7+ requirement check
- Automatic module installation and updates
- Management group access validation
- HTTP listener on localhost:8080
- Device authentication support
- RESTful API endpoints

**Get-AzureLandingZoneInventory.ps1**
- Module dependency validation
- Comprehensive resource collection
- CAF/WAF assessment logic
- Smart error handling for tenant-level resources
- Progress logging with colored output

**index.html**
- Responsive single-page application
- Category navigation sidebar
- Progress overlay during collection
- Data tables for all resource types
- PDF export button

**app.js**
- Frontend application logic (v1.3.0)
- REST API integration
- Dynamic table rendering
- Multi-stage progress simulation
- jsPDF-based report generation

## 📊 Dashboard Categories

### 📈 Overview
- Summary cards with key metrics
- CAF compliance score with percentage
- WAF pillar scores (5 pillars)
- Resource count statistics
- Quick access to all categories

### 🗂️ Management Groups
- Hierarchical structure table
- Parent management group references
- Child object counts (MGs + subscriptions)
- Tenant ID display

### 💳 Subscriptions
- Complete subscription inventory
- State tracking (Enabled/Disabled/ProvisioningState)
- Tag collections
- Management group placement
- Tenant association

### 📋 Policies
Three-tier policy governance:
- **Definitions**: Custom and built-in policy rules with descriptions
- **Initiatives**: Policy sets (bundles) with member policies
- **Assignments**: Active policy enforcement at all scopes (MG/Sub/RG)

### 👥 Role Assignments
- RBAC role mappings
- Principal identification (User/Group/ServicePrincipal)
- Role definition names
- Scope hierarchy display
- Role distribution analytics

### 🌐 Networking
Complete network infrastructure visibility:
- **Virtual Networks**: Address spaces, subnet counts, locations
- **VNet Peerings**: Source/remote VNets, states, traffic settings
- **Virtual WANs**: Hub counts, branch-to-branch, VNet-to-VNet traffic
- **VPN Gateways**: Gateway types, SKUs, VPN types, Active-Active, BGP
- **ExpressRoute Circuits**: Providers, peering locations, bandwidth, states
- **Azure Firewalls**: Tiers, threat intel modes, rule counts, policy references
- **Firewall Policies**: Total rules, collection breakdowns, IDS/IPS status
- **Network Security Groups**: Security rule counts, **connected subnets (VNet/Subnet), connected NICs**
- **Private DNS Zones**: Record set counts, **linked VNets with registration status**
- **Private Endpoints**: **Connected resources (resource name), VNet/subnet placement, private IP addresses, connection states**

### 💻 Virtual Machines
- VM inventory with computer names
- Power states (Running/Deallocated/Stopped)
- VM sizes and OS types
- Network connectivity (VNet/Subnet)
- Private IP addresses
- Availability sets

### ⚖️ Governance
- **Budgets**: Cost thresholds, time periods, alert configurations
- **Resource Locks**: 
  - Subscription-level locks
  - Resource group-level locks
  - Resource-level locks
  - Lock types (CanNotDelete/ReadOnly)
- **Tags**: 
  - Unique tag keys discovered
  - Tag values collected from subscriptions
  - Tag values from resource groups
  - Sample tag values from resources (first 100)
- **Diagnostic Settings**: Monitoring configuration tracking

## 📄 PDF Export Features

Generated reports include:

### 📑 Cover Page
- Tool name and version (v1.3.0)
- Generation timestamp
- Tenant ID
- Azure Landing Zone branding

### 📊 Executive Summary
- Management groups, subscriptions, policies overview
- Networking resource counts
- Governance resource counts
- VM inventory summary

### 🏆 CAF Assessment (7 Categories)
Detailed evaluation with scores and findings:
1. **Management Group Hierarchy**: Structure depth and organization
2. **Policy Governance**: Built-in vs custom policies, coverage
3. **Identity & Access (RBAC)**: Role assignment distribution
4. **Network Topology**: Hub-spoke patterns, connectivity
5. **Security**: NSGs, firewalls, policies, private endpoints
6. **Cost Management**: Budget coverage, tagging strategies
7. **Resource Organization**: Tagging maturity, structure

Each category includes:
- Score percentage
- Status indicators (✓ / ✗ / ⚠)
- Detailed findings
- Specific recommendations

### 🎯 WAF Alignment (5 Pillars)
Individual pillar scoring:
- **Reliability**: Network redundancy, locks, hybrid connectivity
- **Security**: Policies, RBAC, firewalls, NSGs  
- **Cost Optimization**: Budgets, tagging, resource organization
- **Operational Excellence**: Management hierarchy, automation potential
- **Performance Efficiency**: Network topology, connectivity options

### 📋 Detailed Resource Tables
Structured data tables for:
- Management Groups (name, parent, children, type)
- Subscriptions (name, state, tags, MG)
- Virtual Networks (name, location, address space, subnets)
- VNet Peerings (source, remote, state, traffic settings)
- Virtual WANs (name, location, hubs, traffic policies)
- VPN Gateways (name, SKU, type, BGP, Active-Active)
- ExpressRoute Circuits (name, provider, bandwidth, state)
- **Private DNS Zones** (name, location, record count, VNet links, linked VNets)
- **Network Security Groups** (name, location, custom rules, connected subnets/NICs)
- **Private Endpoints** (name, connected resource, VNet/subnet, private IP, state)
- Azure Firewalls (name, tier, threat intel, rules/policy)
- Firewall Policies (name, tier, rules, collections, IDS)
- Role Assignments (principal, role, scope)
- Policy Assignments (name, scope, enforcement)

### 📚 References & Resources
- Microsoft CAF documentation links
- WAF guidance
- Best practice references

### 🔖 Report Branding
- Navy interior page headers with the report name
- Azure divider rules and responsive page numbers
- GetToTheCloud footer on every page

## 🔧 Configuration

### Custom Port
```powershell
./Start-AzureLandingZoneServer.ps1 -Port 3000
```

### Module Updates
Modules are automatically checked and updated on every server start. To force update manually:
```powershell
Update-Module -Name Az.Accounts -Force
Update-Module -Name Az.Resources -Force  
Update-Module -Name Az.Network -Force
Update-Module -Name Az.PolicyInsights -Force
```

### Collection Scope
By default, collects from ALL subscriptions. To limit scope, edit `Get-AzureLandingZoneInventory.ps1`:

```powershell
# Line ~310: Limit subscriptions for detailed resource collection
$subs = Get-AzSubscription | Where-Object { $_.Name -like "Prod*" }

# Or use specific subscription IDs
$subs = Get-AzSubscription -SubscriptionId "sub-id-1", "sub-id-2"
```

### UI Customization
- **Styling**: Modify `styles.css` for colors, fonts, layouts
- **Tables**: Edit column definitions in `index.html`
- **Data Display**: Update render functions in `app.js`
- **PDF Content**: Customize `exportToPDF()` function in `app.js`
- **JSON Export**: Modify `exportToJSON()` function in `app.js` for custom data filtering

### JSON Export Use Cases

The JSON export provides clean resource data (without assessment scores) for advanced scenarios:

1. **Automation & CI/CD Integration**
   ```bash
   # Example: Process resource data in pipelines
   curl http://localhost:8080/api/inventory/latest > resources.json
   jq '.resources.virtualMachines | length' resources.json
   ```

2. **Historical Tracking & Drift Detection**
   ```powershell
   # Archive daily snapshots to track resource changes
   $date = Get-Date -Format "yyyy-MM-dd"
   Copy-Item "resources.json" "archive/resources-$date.json"
   
   # Compare with previous day to detect drift
   Compare-Object (Get-Content "archive/resources-$date.json") `
                  (Get-Content "archive/resources-yesterday.json")
   ```

3. **Custom Reporting with Python/PowerShell**
   ```python
   import json
   with open('resources.json') as f:
       data = json.load(f)
       # Analyze resource configurations
       vnets = data['resources']['networking']['virtualNetworks']
       for vnet in vnets:
           print(f"{vnet['name']}: {vnet['addressSpace']}")
   ```

4. **Integration with CMDB/ServiceNow**
   ```powershell
   # Load resources and sync to external systems
   $export = Get-Content resources.json | ConvertFrom-Json
   foreach ($vm in $export.resources.virtualMachines) {
       # Push to CMDB API
       Invoke-RestMethod -Uri "$cmdbUrl/api/vm" -Method Post -Body ($vm | ConvertTo-Json)
   }
   ```

5. **Compliance Auditing & Change Control**
   - Store JSON in Git for version control and audit trail
   - Compare snapshots to validate change requests
   - Generate compliance reports from versioned resource data
   - Track who made changes and when (via Git history)

## 🛠️ Troubleshooting

### PowerShell Version Issues
```powershell
# Check version
pwsh --version

# Should be 7.0 or higher
# If not, download from: https://aka.ms/powershell
```

**Error Message:**
```
❌ ERROR: PowerShell 7 or higher is required.
   Current version: 5.1.xxxxx
   Download PowerShell 7+: https://aka.ms/powershell
```

**Solution:** Install PowerShell 7+ and run with `pwsh` command instead of `powershell`

### Module Installation Failures
```powershell
# Clear module cache
Remove-Module Az.* -Force -ErrorAction SilentlyContinue

# Reinstall manually
Install-Module -Name Az.Accounts -Force -Scope CurrentUser -AllowClobber
Install-Module -Name Az.Resources -Force -Scope CurrentUser -AllowClobber
Install-Module -Name Az.Network -Force -Scope CurrentUser -AllowClobber
Install-Module -Name Az.PolicyInsights -Force -Scope CurrentUser -AllowClobber
```

### Authentication Issues
```powershell
# Clear and reconnect
Disconnect-AzAccount
Clear-AzContext -Force  
Connect-AzAccount -UseDeviceAuthentication

# Verify connection
Get-AzContext
Get-AzSubscription
```

**Symptoms:**
- "Not authenticated" message
- Empty inventory data
- Connection timeout errors

**Solution:**
1. Ensure device code authentication completes
2. Check network proxy settings
3. Verify Azure AD sign-in works in browser

### Management Group Permission Errors

**Error Message:**
```
⚠️  Error accessing Management Groups: ...does not have authorization 
     to perform action 'Microsoft.Management/register/action'...
```

**This is a MISLEADING error!** The cmdlet checks subscription-level permissions first, but management groups are tenant-level resources.

**Solution:**
- The tool automatically handles this error
- Uses `-ErrorAction SilentlyContinue` to bypass false permission check
- Ensure you have "Management Group Reader" role at **tenant root** level
- Contact Azure Global Admin if management groups still show 0

**Verification:**
```powershell
# Should return management groups (not error)
Get-AzManagementGroup

# Check your role assignments
Get-AzRoleAssignment -SignInName your.email@domain.com | 
    Where-Object { $_.RoleDefinitionName -like "*Management Group*" }
```

### Port Already in Use

```bash
# macOS/Linux: Find and kill process
lsof -ti:8080 | xargs kill -9

# Windows: Kill PowerShell processes
taskkill /F /IM pwsh.exe

# Use alternate port
./Start-AzureLandingZoneServer.ps1 -Port 8081
```

### Slow Collection Performance

**Causes:**
- Large tenant (50+ subscriptions)
- Many resources (1000+ VNets, policies, etc.)
- Network latency to Azure APIs

**Solutions:**
1. **Be Patient**: 5-15 minutes is normal for large tenants
2. **Limit Scope**: Edit collection script to target specific MGs/subscriptions
3. **Watch Progress**: Console shows real-time collection status
4. **Check Output**: Look for errors in PowerShell console

### Firewall Policy Collection Errors

If you see input prompts during collection:

```powershell
# Update Az.Network to latest version
Update-Module -Name Az.Network -Force

# Restart server
```

The tool properly handles firewall policy rule collections without user input.

### Missing Data in Tables

**Problem:** Tables show "No X found" but you know they exist

**Causes & Solutions:**
- **Permissions**: Verify Reader access to subscription/MG
- **Scope**: Check if resources are in subscriptions being scanned
- **Errors**: Review PowerShell console for API errors
- **Filters**: Remove any resource filters in collection script

### Network Connectivity Issues

**Error Message:**
```
⚠️  Network connectivity issue for subscription: YourSub - Skipping
WARNING: Unable to acquire token for tenant 'xxx' with error 'No such host is known. (management.azure.com:443)'
```

**Causes:**
- DNS resolution failure for Azure management endpoints
- Network proxy/firewall blocking Azure APIs
- VPN disconnection or network interruption
- Corporate network restrictions

**Solutions:**
1. **Check DNS Resolution**:
   ```bash
   # macOS/Linux
   nslookup management.azure.com
   
   # Windows
   nslookup management.azure.com
   ```

2. **Verify Network Connectivity**:
   ```bash
   # Test HTTPS connectivity to Azure
   curl -I https://management.azure.com
   ```

3. **Check Proxy Settings**:
   ```powershell
   # View current proxy configuration
   [System.Net.WebRequest]::DefaultWebProxy
   
   # Set proxy if needed
   $env:HTTPS_PROXY = "http://proxy.company.com:8080"
   ```

4. **VPN Connection**: Ensure your VPN is connected if required for Azure access

5. **Firewall Rules**: Verify that Azure management endpoints are allowed:
   - `*.azure.com`
   - `*.windows.net`
   - `management.azure.com`

**Note:** The tool will automatically skip problematic subscriptions and continue collecting data from accessible ones. This does not stop the entire inventory process.

### PDF Export Not Working

**Symptoms:**
- Button doesn't respond
- JavaScript console errors
- Blank/incomplete PDF

**Solutions:**
1. **Check jsPDF Library**: Ensure CDN loads correctly
2. **Browser Console**: Check for JavaScript errors (F12)
3. **Large Data**: Reduce data size if browser memory exhausted
4. **Try Another Browser**: Chrome/Edge recommended

## 🔐 Security

- **localhost Only**: Server binds to 127.0.0.1 (no network exposure); `HttpListener` also validates the Host header
- **Same-Origin Only**: No CORS headers are sent — cross-origin pages cannot read the inventory API
- **CSRF Protection**: State-changing endpoints (`/api/auth/login`, `/api/inventory/refresh`) require a POST request with the `X-Requested-With: XMLHttpRequest` header; plain GET/link/form requests are rejected with 403
- **Device Code Auth**: Secure Azure authentication flow
- **Protected Token Handling**: The Az context used by the background collector is written to `~/.documenter-azure-landingzone/` (directory `0700`, file `0600` on macOS/Linux), deleted immediately after the collector imports it, and again on server shutdown — never placed in the shared system temp directory
- **No Dynamic Code Evaluation**: Scoring and WAF conditions from `scoring-config.json` / `waf-config.json` are parsed with a strict, safe evaluator (tokens, comparison operators, AND/OR only) — no `Invoke-Expression` in PowerShell and no `eval()` in JavaScript
- **XSS Protection**: All Azure-derived values (resource names, tags, descriptions, scopes, etc.) are HTML-escaped before being rendered in the dashboard
- **Hardened Frontend**: CDN scripts/styles are pinned with Subresource Integrity (SRI) hashes + `crossorigin="anonymous"`, and a Content-Security-Policy meta tag restricts sources; responses include `X-Content-Type-Options: nosniff`
- **No Silent Module Updates**: Required Az modules are installed only if missing; the server never force-updates installed modules (it notifies you when an update is available so you can run `Update-Module` yourself)
- **Generic Error Responses**: API errors return generic messages; full exception details are only written to the server console
- **Read-Only**: Only queries resources, never modifies
- **Session-Based**: Authentication per browser session
- **No External APIs**: All data stays on your local machine (only the CDN assets for the diagram/PDF libraries are fetched)

> Note: the dashboard itself has no login — anything running on the same machine can reach `http://localhost:<port>`. Run it only on trusted, single-user machines.

## 📊 Performance Characteristics

### Collection Time
- **Small Tenant** (1-5 subscriptions): 1-2 minutes
- **Medium Tenant** (5-20 subscriptions): 2-5 minutes  
- **Large Tenant** (20-50 subscriptions): 5-15 minutes
- **Enterprise Tenant** (50+ subscriptions): 15-30 minutes

*Factors affecting speed:*
- Number of subscriptions
- Resources per subscription (especially policies, role assignments)
- Network latency to Azure APIs
- Management group hierarchy depth

### Resource Collection Scope
**Version 1.3.0 removes all artificial limits:**
- ✅ **All** Management Groups
- ✅ **All** Subscriptions  
- ✅ **All** Policy Definitions (custom & built-in)
- ✅ **All** Policy Initiatives (custom & built-in)
- ✅ **All** Policy Assignments
- ✅ **All** Role Assignments
- ✅ **All** VNets, Peerings, Firewalls
- ✅ **All** Virtual WANs, VPN Gateways, ExpressRoute Circuits
- ✅ **All** Virtual Machines
- ✅ **All** Locks (subscription/RG/resource levels)
- ✅ **All** Tags (from subscriptions, resource groups, sample from resources)

### Browser Requirements
- Modern browser (Chrome, Edge, Firefox, Safari)
- JavaScript enabled
- Recommended: Chrome or Edge for best PDF export performance
- Memory: 4GB+ RAM recommended for large tenants (10,000+ resources)

### Progress Tracking
9-stage progress indicator shows:
1. Management Groups
2. Subscriptions
3. Policy Definitions
4. Policy Initiatives & Assignments
5. Role Assignments
6. Networking (VNets, Peerings, Virtual WAN, VPN, ExpressRoute, Firewalls)
7. Virtual Machines
8. Governance (Budgets, Locks, Tags)
9. Assessment (CAF/WAF scoring)

## 🤝 Contributing

### Publishing Releases

The `release.yml` workflow creates the GitHub Release and publishes the module version from `documenter-azure-landingzone.psd1` to PowerShell Gallery.

Before the first release, create a PowerShell Gallery API key with package push permission, then add it to the GitHub repository at **Settings > Secrets and variables > Actions** as a repository secret named `PSGALLERY_API_KEY`. Never commit the key to the workflow or repository.

The workflow skips versions already present in PowerShell Gallery, so failed publication runs can be retried with **Actions > Create Release > Run workflow** after the secret is configured.

### Adding New Azure Resources
1. **Collection**: Update `Get-AzureLandingZoneInventory.ps1`
   ```powershell
   # Example: Add Azure SQL Databases
   Write-Host "Collecting SQL Databases..." -ForegroundColor Cyan
   $sqlDatabases = @()
   foreach ($sub in $allSubscriptions) {
       Set-AzContext -SubscriptionId $sub.Id -ErrorAction SilentlyContinue
       $sqlDatabases += Get-AzSqlDatabase -ErrorAction SilentlyContinue
   }
   
   # Add to inventory object
   $inventory.databases = @{
       sqlDatabases = $sqlDatabases
   }
   ```

2. **UI**: Add table in `index.html`
   ```html
   <div class="subsection">
       <h3>SQL Databases</h3>
       <table class="data-table" id="sqlDatabasesTable">
           <thead>
               <tr>
                   <th>Name</th>
                   <th>Subscription</th>
                   <th>Location</th>
                   <th>Tier</th>
               </tr>
           </thead>
           <tbody></tbody>
       </table>
   </div>
   ```

3. **Display**: Update `app.js`
   ```javascript
   function populateSqlDatabases() {
       const table = document.querySelector('#sqlDatabasesTable tbody');
       table.innerHTML = '';
       
       if (!inventoryData.databases?.sqlDatabases?.length) {
           table.innerHTML = '<tr><td colspan="4">No SQL databases found</td></tr>';
           return;
       }
       
       inventoryData.databases.sqlDatabases.forEach(db => {
           const row = table.insertRow();
           row.insertCell(0).textContent = db.DatabaseName;
           row.insertCell(1).textContent = db.ResourceGroupName;
           row.insertCell(2).textContent = db.Location;
           row.insertCell(3).textContent = db.SkuName;
       });
   }
   
   // Call in populateData()
   populateSqlDatabases();
   ```

4. **PDF Export**: Add section in `app.js` `exportToPDF()`
   ```javascript
   // Add after networking section
   if (inventoryData.databases?.sqlDatabases?.length > 0) {
       doc.addPage();
       doc.setFontSize(16);
       doc.text('SQL Databases', 105, yPos, { align: 'center' });
       yPos += 10;
       
       // Create table...
   }
   ```

### Adding Assessment Criteria

**CAF Scoring Rules** - Edit `scoring-config.json`:
```json
{
  "version": "1.3.0",
  "categories": [
    {
      "name": "Management Group Hierarchy",
      "maxScore": 15,
      "threshold": 10,
      "rules": [
        {
          "id": "mgExists",
          "name": "Management Groups Exist",
          "condition": "$mgCount -gt 0",
          "points": 5,
          "recommendation": "Implement management group hierarchy"
        }
      ]
    }
  ]
}
```

**WAF Pillar Checks** - Edit `waf-config.json`:
```json
{
  "version": "1.3.0",
  "pillars": [
    {
      "name": "Reliability",
      "order": 1,
      "checks": [
        {
          "id": "vnetPeerings",
          "name": "VNet Peerings for Redundancy",
          "condition": "{peeringCount} -gt 0",
          "weight": 20,
          "passMessage": "{peeringCount} peerings configured",
          "failMessage": "No VNet peerings found"
        }
      ]
    }
  ]
}
```

**How Configuration Works:**
- PowerShell loads JSON config files at runtime
- Conditions use PowerShell syntax with metrics as placeholders
- Scoring is dynamically calculated based on configuration
- No code changes needed for new rules - just edit JSON
- Both `scoring-config.json` and `waf-config.json` support versioning

```powershell
# Example: Add new CAF category for Data Management
$dataManagementScore = 0
$dataManagementFindings = @()
$dataManagementRecs = @()

# Check for SQL TDE encryption
$sqlServers = Get-AzSqlServer
if ($sqlServers | Where-Object { $_.MinimalTlsVersion -eq '1.2' }) {
    $dataManagementScore += 15
    $dataManagementFindings += "✓ SQL Servers enforce TLS 1.2"
} else {
    $dataManagementFindings += "✗ SQL Servers not enforcing TLS 1.2"
    $dataManagementRecs += "Enable TLS 1.2 on all SQL Servers"
}

# Add to assessment
$assessment.caf.categories += @{
    name = "Data Management"
    score = [math]::Min($dataManagementScore, 100)
    findings = $dataManagementFindings
    recommendations = $dataManagementRecs
}
```

### Code Style Guidelines
- **PowerShell**: Use `PascalCase` for functions, `$camelCase` for variables
- **JavaScript**: Use `camelCase` for functions/variables
- **Comments**: Add inline explanations for complex logic
- **Error Handling**: Always include `-ErrorAction SilentlyContinue` for Azure cmdlets
- **Output**: Use `Write-Host` with colors (Cyan for info, Yellow for warnings, Red for errors)

## 📝 License

MIT License - Free to use, modify, and distribute.

See [LICENSE](LICENSE) file for full terms.

## 🙏 Acknowledgments

### Technologies & Libraries
- **Microsoft Azure PowerShell SDK**: Core data collection
- **jsPDF Library**: PDF generation functionality
- **vis-network**: Network visualization support (available in codebase)

### Inspiration & Standards
- Microsoft Azure Cloud Adoption Framework (CAF)
- Microsoft Azure Well-Architected Framework (WAF)
- Azure Landing Zone reference implementations
- Azure community best practices

### Special Thanks
- Azure PowerShell SDK maintainers
- Microsoft Cloud Adoption Framework team
- Azure architecture and governance community

## 🔗 Related Resources

### Microsoft Official Documentation
- [Azure Landing Zones](https://learn.microsoft.com/azure/cloud-adoption-framework/ready/landing-zone/) - Foundational landing zone concepts
- [Cloud Adoption Framework](https://learn.microsoft.com/azure/cloud-adoption-framework/) - Complete adoption methodology
- [Well-Architected Framework](https://learn.microsoft.com/azure/architecture/framework/) - Five-pillar architecture guidance
- [Azure Policy](https://learn.microsoft.com/azure/governance/policy/) - Policy-driven governance
- [Management Groups](https://learn.microsoft.com/azure/governance/management-groups/) - Hierarchical organization
- [Azure RBAC](https://learn.microsoft.com/azure/role-based-access-control/) - Identity and access management

### Network Architecture Patterns
- [Hub-Spoke Network Topology](https://learn.microsoft.com/azure/architecture/reference-architectures/hybrid-networking/hub-spoke) - Core networking pattern
- [Azure Firewall Architecture](https://learn.microsoft.com/azure/architecture/example-scenario/firewalls/) - Central firewall design
- [Private Link and DNS Integration](https://learn.microsoft.com/azure/private-link/private-endpoint-dns) - Private connectivity
- [Virtual WAN Documentation](https://learn.microsoft.com/azure/virtual-wan/) - Global transit network
- [VPN Gateway Planning](https://learn.microsoft.com/azure/vpn-gateway/vpn-gateway-about-vpngateways) - Hybrid connectivity

### Governance & Best Practices
- [Azure Policy Samples](https://github.com/Azure/azure-policy) - Community policy definitions
- [Azure Enterprise Scaffold](https://learn.microsoft.com/azure/cloud-adoption-framework/ready/enterprise-scale/) - Enterprise-scale architecture
- [Tagging Strategy](https://learn.microsoft.com/azure/cloud-adoption-framework/ready/azure-best-practices/resource-tagging) - Resource organization
- [Cost Management Best Practices](https://learn.microsoft.com/azure/cost-management-billing/costs/cost-mgt-best-practices) - Budget and optimization

### Tools & Automation
- [Azure PowerShell Documentation](https://learn.microsoft.com/powershell/azure/) - Complete cmdlet reference
- [Azure Resource Graph](https://learn.microsoft.com/azure/governance/resource-graph/) - Advanced querying at scale
- [Azure CLI](https://learn.microsoft.com/cli/azure/) - Alternative command-line tool
- [Terraform Azure Provider](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs) - Infrastructure as Code

## 👨‍💻 Author

**Alex ter Neuzen**  
IT Consultant with experience in Azure Local, Azure Landing Zones and Azure Virtual Desktop

🌐 Website: [GetToTheCloud](https://www.gettothe.cloud)  
📧 Contact: Through website  
💼 Specialties: Azure Landing Zones, Cloud Adoption, Infrastructure as Code

---

<div align="center">

**Version 1.3.0** | Built with PowerShell 7+ | Last Updated: 2026

*Empowering Azure Landing Zone visibility and governance through automated inventory and assessment*

⭐ If this tool helps your Azure journey, consider sharing it with your team!

</div>
