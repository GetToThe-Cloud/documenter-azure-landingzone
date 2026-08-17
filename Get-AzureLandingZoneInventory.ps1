#Requires -Version 7.0
<#
.SYNOPSIS
    Azure Landing Zone Inventory Collection Module
.DESCRIPTION
    Collects comprehensive inventory data from Azure Landing Zone environments including
    management groups, policies, subscriptions, networking, and governance settings.
    
    Network Requirements:
    - Internet connectivity to management.azure.com (port 443)
    - DNS resolution for Azure endpoints
    - If behind a proxy, ensure Azure endpoints are accessible
    
    The script will gracefully skip subscriptions with connectivity issues and continue
    collecting data from accessible resources.
.NOTES
    Requires PowerShell 7.0 or higher
    Required Modules: Az.Accounts, Az.Resources, Az.Network, Az.PolicyInsights
#>

# Script version
$script:Version = "1.4.0"

# Progress file path for real-time progress reporting (per-user app dir, not the shared temp dir)
$script:AppDataDir = Join-Path $HOME '.documenter-azure-landingzone'
if (-not (Test-Path $script:AppDataDir)) {
    New-Item -ItemType Directory -Path $script:AppDataDir -Force | Out-Null
}
$script:ProgressFilePath = Join-Path $script:AppDataDir "inventory-progress.json"

function Update-CollectionProgress {
    param(
        [int]$Step,
        [int]$TotalSteps,
        [string]$Status
    )
    $percentage = [math]::Round(($Step / $TotalSteps) * 95)
    $progressData = @{
        step = $Step
        totalSteps = $TotalSteps
        percentage = $percentage
        status = $Status
        timestamp = (Get-Date).ToString('o')
    } | ConvertTo-Json -Compress
    try {
        [System.IO.File]::WriteAllText($script:ProgressFilePath, $progressData)
    } catch {
        # Non-critical - continue even if progress file write fails
    }
    Write-Host "    ○ [$Step/$TotalSteps] $Status" -ForegroundColor Gray
}

# --- Safe scoring-condition evaluation (no Invoke-Expression) ---------------
# Grammar: <token> <op> <token> joined by AND / OR (AND binds tighter than OR).
# Tokens are metric names, numbers, or true/false. Operators: >= <= == != > <

function Resolve-ConditionToken {
    param(
        [string]$Token,
        [hashtable]$Metrics
    )
    $Token = $Token.Trim()
    if ($Metrics.ContainsKey($Token)) { return $Metrics[$Token] }
    if ($Token -eq 'true')  { return $true }
    if ($Token -eq 'false') { return $false }
    $num = 0.0
    if ([double]::TryParse($Token, [ref]$num)) { return $num }
    throw "Unknown token '$Token' in scoring condition"
}

function Test-ConditionComparison {
    param(
        [string]$Expression,
        [hashtable]$Metrics
    )
    if ($Expression -match '^\s*([\w.]+)\s*(>=|<=|==|!=|>|<)\s*([\w.]+)\s*$') {
        $left  = Resolve-ConditionToken -Token $Matches[1] -Metrics $Metrics
        $op    = $Matches[2]
        $right = Resolve-ConditionToken -Token $Matches[3] -Metrics $Metrics
        
        if ($left -is [bool] -or $right -is [bool]) {
            $l = [bool]$left; $r = [bool]$right
            switch ($op) {
                '==' { return $l -eq $r }
                '!=' { return $l -ne $r }
                default { throw "Operator '$op' is not valid for boolean values" }
            }
        }
        
        $l = [double]$left; $r = [double]$right
        switch ($op) {
            '>=' { return $l -ge $r }
            '<=' { return $l -le $r }
            '==' { return $l -eq $r }
            '!=' { return $l -ne $r }
            '>'  { return $l -gt $r }
            '<'  { return $l -lt $r }
        }
    }
    # Bare token — treat as a boolean metric
    return [bool](Resolve-ConditionToken -Token $Expression -Metrics $Metrics)
}

function Test-ScoringCondition {
    param(
        [string]$Condition,
        [hashtable]$Metrics
    )
    foreach ($orPart in ($Condition -split '\bOR\b')) {
        $andResult = $true
        foreach ($andPart in ($orPart -split '\bAND\b')) {
            if (-not (Test-ConditionComparison -Expression $andPart -Metrics $Metrics)) {
                $andResult = $false
                break
            }
        }
        if ($andResult) { return $true }
    }
    return $false
}

function Get-AzureLandingZoneInventory {
    [CmdletBinding()]
    param()
    
    # Verify required modules are loaded
    $requiredModules = @('Az.Accounts', 'Az.Resources', 'Az.Network', 'Az.PolicyInsights')
    $missingModules = @()
    
    foreach ($module in $requiredModules) {
        if (-not (Get-Module -Name $module)) {
            $missingModules += $module
        }
    }
    
    if ($missingModules.Count -gt 0) {
        Write-Host "❌ ERROR: Required modules not loaded: $($missingModules -join ', ')" -ForegroundColor Red
        Write-Host "Please import the required modules before running this function." -ForegroundColor Yellow
        throw "Required modules not loaded: $($missingModules -join ', ')"
    }
    
    $totalSteps = 11
    Update-CollectionProgress -Step 0 -TotalSteps $totalSteps -Status 'Initializing inventory collection...'
    Write-Host "      Note: Requires connectivity to management.azure.com and Azure endpoints" -ForegroundColor Gray
    
    $inventory = @{
        version = $script:Version
        collectionTime = (Get-Date).ToString('o')
        tenantId = (Get-AzContext).Tenant.Id
        managementGroups = @()
        subscriptions = @()
        policies = @{
            definitions = @()
            initiatives = @()
            assignments = @()
        }
        roleAssignments = @()
        networking = @{
            vnets = @()
            subnets = @()
            routeTables = @()
            peerings = @()
            vpnGateways = @()
            expressRoutes = @()
            virtualWans = @()
            virtualHubs = @()
            firewalls = @()
            firewallPolicies = @()
            networkSecurityGroups = @()
            privateDnsZones = @()
            privateEndpoints = @()
        }
        compute = @{
            virtualMachines = @()
        }
        governance = @{
            budgets = @()
            defenderPlans = @()
            tags = @{}
            locks = @()
            diagnosticSettings = @()
        }
        summary = @{
            totalManagementGroups = 0
            totalSubscriptions = 0
            totalPolicyDefinitions = 0
            totalPolicyInitiatives = 0
            totalPolicyAssignments = 0
            totalRoleAssignments = 0
            totalVNets = 0
            totalSubnets = 0
            totalRouteTables = 0
            totalPeerings = 0
            totalBudgets = 0
            totalLocks = 0
            totalVMs = 0
            totalPrivateDnsZones = 0
            totalPrivateEndpoints = 0
            totalVirtualWans = 0
            totalVirtualHubs = 0
            totalFirewalls = 0
            totalFirewallPolicies = 0
        }
        explanations = @{
            overview = @"
Azure Landing Zone is an enterprise-scale architecture pattern that provides a standardized foundation for cloud adoption. 
It implements governance, security, networking, and identity best practices aligned with the Cloud Adoption Framework (CAF).

Key Components:
• Management Groups: Hierarchical containers for organizing subscriptions
• Policies: Governance rules enforced across workloads
• Role Assignments: Identity and access management (IAM) controls
• Networking: Hub-spoke topology for secure, scalable connectivity
• Governance: Budgets, locks, tags, and diagnostic settings
"@
            managementGroups = @"
Management Groups provide a hierarchical structure for organizing subscriptions and applying governance controls at scale.

Structure:
• Root Management Group: Top-level container for the tenant
• Platform: Infrastructure services (identity, management, connectivity)
• Landing Zones: Application workloads (corp-connected, online)
• Sandboxes: Development and testing environments
• Decommissioned: Archived or sunset resources

Each management group can have policies, role assignments, and budgets applied that cascade to all child subscriptions.
"@
            policies = @"
Azure Policy helps enforce organizational standards and assess compliance at scale.

Types:
• Policy Definitions: Individual rules (e.g., "Require tag on resources")
• Policy Initiatives (Sets): Groups of related policies (e.g., "CIS Benchmark")
• Policy Assignments: Application of policies to specific scopes

Effects:
• Deny: Block non-compliant resource creation
• Audit: Log non-compliance without blocking
• DeployIfNotExists: Automatically remediate resources
• Modify: Change resource properties to comply
• Disabled: Policy exists but is not enforced

Policies enable automated compliance monitoring and enforcement across all workloads.
"@
            roleAssignments = @"
Role-Based Access Control (RBAC) manages who can access Azure resources and what they can do.

Key Concepts:
• Security Principal: User, group, service principal, or managed identity
• Role Definition: Collection of permissions (e.g., Owner, Contributor, Reader)
• Scope: Where the assignment applies (management group, subscription, resource group, resource)

Built-in Roles:
• Owner: Full access including the ability to assign roles
• Contributor: Full access except role assignment
• Reader: View-only access
• Custom Roles: Tailored permissions for specific scenarios

Best Practices:
• Use least-privilege principle
• Assign roles to groups, not individual users
• Regular access reviews and audits
• Use managed identities for service-to-service authentication
"@
            networking = @"
Azure Landing Zone networking follows a hub-spoke topology for secure, scalable connectivity.

Hub-Spoke Architecture:
• Hub VNet: Central connectivity point with shared services
  - VPN Gateway or ExpressRoute for on-premises connectivity
  - Azure Firewall for traffic inspection and filtering
  - DNS and other shared services
• Spoke VNets: Isolated workload networks
  - Application resources and services
  - Peered to hub for centralized connectivity
  - Network security groups for micro-segmentation

Connectivity Options:
• VNet Peering: High-speed Azure network connections
• VPN Gateway: Encrypted tunnels over internet
• ExpressRoute: Private dedicated connection to on-premises
• Azure Firewall: Network and application-level filtering
• Virtual WAN: Microsoft-managed hub for global connectivity

Security:
• Network Security Groups (NSGs): Subnet/NIC-level firewall rules
• Application Security Groups: Group VMs by application role
• Service Endpoints: Private connectivity to Azure services
• Private Link: Private IP access to PaaS services

Private Connectivity:
• Private DNS Zones: DNS resolution for private endpoints and custom domains
  - Integrated with VNets for automatic registration
  - Support for Azure service-specific zones (privatelink.*)
  - Centralized DNS management across landing zones
• Private Endpoints: Private IP addresses for Azure PaaS services
  - Eliminates exposure to public internet
  - Traffic stays on Microsoft backbone network
  - Integrates with Private DNS Zones for name resolution
  - Supports blob storage, SQL databases, Key Vault, and more
"@
            governance = @"
Governance ensures consistent management, security, and compliance across all Azure resources.

Budgets:
• Spending thresholds with alerting
• Forecast-based monitoring
• Action groups for automated responses

Resource Locks:
• ReadOnly: Prevents modifications
• CanNotDelete: Prevents deletion
• Applied at subscription, resource group, or resource scope
• Inherited by child resources

Tags:
• Key-value pairs for resource organization
• Enable cost tracking and allocation
• Support automation and lifecycle management
• Common tags: Environment, Owner, CostCenter, Application

Diagnostic Settings:
• Log and metric collection configuration
• Send to Log Analytics, Storage, or Event Hub
• Activity logs, resource logs, and metrics
• Enable monitoring, auditing, and troubleshooting

Blueprints (deprecated, use Template Specs):
• Declarative definition of environment
• Includes ARM templates, policies, role assignments
• Versioning and tracking of deployments
"@
            subscriptions = @"
Azure subscriptions are billing and management boundaries within the landing zone.

Placement Strategy:
• Platform Subscriptions:
  - Identity: AD DS, Azure AD Connect
  - Management: Monitoring, backup, governance tooling
  - Connectivity: Hub networking, VPN/ExpressRoute
• Landing Zone Subscriptions:
  - Corp-Connected: On-premises connectivity required
  - Online: Internet-facing workloads
  - Sandbox: Development and testing
• Decommissioned: Sunset applications

Subscription Limits:
• Resource quotas (VMs, storage, networking)
• API throttling limits
• Service-specific constraints

Move Strategy:
• Move between management groups for different governance
• Subscription transfer for billing ownership change
• Resource move for reorganization within/across subscriptions
"@
        }
    }
    
    try {
        # Get Management Groups
        Update-CollectionProgress -Step 1 -TotalSteps $totalSteps -Status 'Collecting Management Groups...'
        
        # Store current context
        $currentContext = Get-AzContext
        Write-Host "      ○ Current Context: Tenant=$($currentContext.Tenant.Id), Sub=$($currentContext.Subscription.Name)" -ForegroundColor Gray
        Write-Host "      ○ Authenticated as: $($currentContext.Account.Id)" -ForegroundColor Gray
        
        try {
            # Management groups are tenant-level resources and don't require subscription context
            # Some errors about resource provider registration can be safely ignored
            $mgList = @()
            
            try {
                $mgList = @(Get-AzManagementGroup -ErrorAction Stop)
            } catch {
                # If we get a resource provider registration error, try again with SilentlyContinue
                # This error is misleading - MGs don't need subscription-level resource provider registration
                if ($_.Exception.Message -match 'Microsoft\.Management/register/action|resource provider|does not have authorization') {
                    Write-Host "      ○ Note: Ignoring subscription-level permission check (MGs are tenant-level)..." -ForegroundColor Gray
                    $mgList = @(Get-AzManagementGroup -ErrorAction SilentlyContinue -WarningAction SilentlyContinue)
                } else {
                    # Real error, report it
                    throw
                }
            }
            
            $inventory.summary.totalManagementGroups = $mgList.Count
            Write-Host "      ○ Found $($mgList.Count) management group(s) at tenant level" -ForegroundColor Gray
            
            foreach ($mg in $mgList) {
                try {
                    $mgDetails = Get-AzManagementGroup -GroupId $mg.Name -Expand -Recurse -ErrorAction SilentlyContinue
                    $inventory.managementGroups += @{
                        id = $mg.Id
                        name = $mg.Name
                        displayName = $mg.DisplayName
                        tenantId = $mg.TenantId
                        type = $mg.Type
                        children = @($mgDetails.Children | ForEach-Object {
                            @{
                                id = $_.Id
                                name = $_.Name
                                displayName = $_.DisplayName
                                type = $_.Type
                            }
                        })
                        parentName = if ($mgDetails.ParentName) { $mgDetails.ParentName } else { "Root" }
                    }
                } catch {
                    Write-Host "      ⚠️  Could not get details for MG: $($mg.Name) - $($_.Exception.Message)" -ForegroundColor Yellow
                }
            }
            Write-Host "      ✓ Collected $($inventory.summary.totalManagementGroups) management groups" -ForegroundColor Green
        } catch {
            Write-Host "      ⚠️  Unexpected error accessing Management Groups: $($_.Exception.Message)" -ForegroundColor Yellow
            Write-Host "      ○ Error details: $($_.Exception.GetType().FullName)" -ForegroundColor Gray
            Write-Host "      ○ This is not a common subscription-level permission issue" -ForegroundColor Gray
            # Check if it's a tenant-level permissions issue  
            if ($_.Exception.Message -match 'AuthorizationFailed|Forbidden') {
                Write-Host "      ℹ️  Tip: Ensure you have 'Management Group Reader' role at tenant root level" -ForegroundColor Cyan
            }
        }
        
        # Get Subscriptions
        Update-CollectionProgress -Step 2 -TotalSteps $totalSteps -Status 'Collecting Subscriptions...'
        $subs = Get-AzSubscription
        $inventory.summary.totalSubscriptions = $subs.Count
        
        foreach ($sub in $subs) {
            try {
                # Try to set context with better error handling
                try {
                    Set-AzContext -SubscriptionId $sub.Id -ErrorAction Stop | Out-Null
                } catch {
                    if ($_.Exception.Message -match 'No such host is known|Unable to acquire token') {
                        Write-Host "      ⚠️  Network connectivity issue for subscription: $($sub.Name) - Skipping" -ForegroundColor Yellow
                        continue
                    } else {
                        throw
                    }
                }
                
                $subDetails = @{
                    id = $sub.Id
                    name = $sub.Name
                    state = $sub.State
                    subscriptionId = $sub.SubscriptionId
                    tenantId = $sub.TenantId
                    tags = @{}
                }
                
                # Get subscription tags
                try {
                    $subResource = Get-AzSubscription -SubscriptionId $sub.Id
                    if ($subResource.Tags) {
                        $subDetails.tags = $subResource.Tags
                    }
                } catch {}
                
                $inventory.subscriptions += $subDetails
            } catch {
                Write-Host "      ⚠️  Could not access subscription: $($sub.Name)" -ForegroundColor Yellow
            }
        }
        Write-Host "      ✓ Collected $($inventory.summary.totalSubscriptions) subscriptions" -ForegroundColor Green
        
        # Get Policy Definitions
        Update-CollectionProgress -Step 3 -TotalSteps $totalSteps -Status 'Collecting Policy Definitions...'
        try {
            # Collect both custom and built-in policies
            $customPolicyDefs = Get-AzPolicyDefinition -Custom -ErrorAction SilentlyContinue
            $builtInPolicyDefs = Get-AzPolicyDefinition -Builtin -ErrorAction SilentlyContinue
            $allPolicyDefs = @($customPolicyDefs) + @($builtInPolicyDefs)
            
            $inventory.summary.totalPolicyDefinitions = $customPolicyDefs.Count
            
            foreach ($policy in $allPolicyDefs) {
                # Try to get display name, falling back to name or a friendly message
                $displayName = if ($policy.Properties.DisplayName) { 
                    $policy.Properties.DisplayName 
                } elseif ($policy.DisplayName) { 
                    $policy.DisplayName 
                } elseif ($policy.Name) { 
                    $policy.Name 
                } else { 
                    'Unnamed Policy' 
                }
                
                # Try to get policy type from multiple locations
                $policyType = if ($policy.Properties.PolicyType) { 
                    $policy.Properties.PolicyType 
                } elseif ($policy.PolicyType) { 
                    $policy.PolicyType 
                } else { 
                    'Custom' 
                }
                
                $inventory.policies.definitions += @{
                    name = if ($policy.Name) { $policy.Name } else { 'Unknown' }
                    displayName = $displayName
                    description = if ($policy.Properties.Description) { $policy.Properties.Description } else { 'No description available' }
                    policyType = $policyType
                    mode = if ($policy.Properties.Mode) { $policy.Properties.Mode } else { 'All' }
                    metadata = $policy.Properties.Metadata
                }
            }
        } catch {
            Write-Host "      ⚠️  Error: $($_.Exception.Message)" -ForegroundColor Yellow
        }
        
        # Get Policy Initiatives (SetDefinitions)
        Update-CollectionProgress -Step 4 -TotalSteps $totalSteps -Status 'Collecting Policy Initiatives...'
        try {
            # Collect both custom and built-in initiatives
            $customInitiatives = Get-AzPolicySetDefinition -Custom -ErrorAction SilentlyContinue
            $builtInInitiatives = Get-AzPolicySetDefinition -Builtin -ErrorAction SilentlyContinue
            $allInitiatives = @($customInitiatives) + @($builtInInitiatives)
            
            $inventory.summary.totalPolicyInitiatives = $customInitiatives.Count
            
            foreach ($initiative in $allInitiatives) {
                # Try to get display name from multiple locations
                $displayName = if ($initiative.Properties.DisplayName) { 
                    $initiative.Properties.DisplayName 
                } elseif ($initiative.DisplayName) { 
                    $initiative.DisplayName
                } elseif ($initiative.Name) { 
                    $initiative.Name 
                } else { 
                    'Unnamed Initiative' 
                }
                
                # Try to get policy type from multiple possible locations
                $policyType = if ($initiative.Properties.PolicyType) { 
                    $initiative.Properties.PolicyType 
                } elseif ($initiative.PolicyType) { 
                    $initiative.PolicyType 
                } else { 
                    'BuiltIn' 
                }
                
                $inventory.policies.initiatives += @{
                    name = if ($initiative.Name) { $initiative.Name } else { 'Unknown' }
                    displayName = $displayName
                    description = if ($initiative.Properties.Description) { $initiative.Properties.Description } else { 'No description available' }
                    policyType = $policyType
                    metadata = $initiative.Properties.Metadata
                    policyDefinitions = @($initiative.Properties.PolicyDefinitions | ForEach-Object {
                        @{
                            policyDefinitionId = $_.policyDefinitionId
                            parameters = $_.parameters
                        }
                    })
                }
            }
        } catch {
            Write-Host "      ⚠️  Error: $($_.Exception.Message)" -ForegroundColor Yellow
        }
        
        # Get Policy Assignments
        Update-CollectionProgress -Step 5 -TotalSteps $totalSteps -Status 'Collecting Policy Assignments...'
        try {
            $assignments = @()
            $assignmentKeys = @{}

            # Policy assignments are commonly applied at management-group scope. Query
            # every management group and subscription, then remove inherited duplicates.
            $policyScopes = @(
                $mgList | ForEach-Object {
                    "/providers/Microsoft.Management/managementGroups/$($_.Name)"
                }
                $subs | ForEach-Object {
                    $subscriptionId = if ($_.Id -match '^/subscriptions/') { $_.Id } else { "/subscriptions/$($_.Id)" }
                    $subscriptionId
                }
            ) | Where-Object { $_ } | Select-Object -Unique

            foreach ($scope in $policyScopes) {
                try {
                    foreach ($assignment in @(Get-AzPolicyAssignment -Scope $scope -ErrorAction SilentlyContinue)) {
                        $assignmentScope = if ($assignment.Properties.Scope) {
                            $assignment.Properties.Scope
                        } elseif ($assignment.Scope) {
                            $assignment.Scope
                        } else {
                            'Not specified'
                        }
                        $key = if ($assignment.PolicyAssignmentId) {
                            $assignment.PolicyAssignmentId
                        } elseif ($assignment.Properties.PolicyAssignmentId) {
                            $assignment.Properties.PolicyAssignmentId
                        } elseif ($assignment.Id) {
                            $assignment.Id
                        } else {
                            "$($assignment.Name)|$assignmentScope"
                        }
                        if (-not $assignmentKeys.ContainsKey($key)) {
                            $assignmentKeys[$key] = $true
                            $assignments += $assignment
                        }
                    }
                } catch {
                    Write-Host "      ⚠️  Could not retrieve policy assignments at scope: $scope" -ForegroundColor Yellow
                }
            }
            $inventory.summary.totalPolicyAssignments = $assignments.Count
            
            foreach ($assignment in $assignments) {
                # Extract policy name from definition ID
                $policyName = 'Unknown'
                if ($assignment.Properties.PolicyDefinitionId) {
                    $policyName = Split-Path $assignment.Properties.PolicyDefinitionId -Leaf
                }
                
                # Try to get display name from multiple locations
                $displayName = if ($assignment.Properties.DisplayName) { 
                    $assignment.Properties.DisplayName 
                } elseif ($assignment.DisplayName) { 
                    $assignment.DisplayName 
                } elseif ($assignment.Name) { 
                    $assignment.Name 
                } else { 
                    "Assignment of $policyName" 
                }
                
                # Try to get scope from multiple possible locations
                $assignmentScope = if ($assignment.Properties.Scope) {
                    $assignment.Properties.Scope
                } elseif ($assignment.Scope) {
                    $assignment.Scope
                } else {
                    'Not specified'
                }
                
                $inventory.policies.assignments += @{
                    name = if ($assignment.Name) { $assignment.Name } else { 'Unknown' }
                    displayName = $displayName
                    description = if ($assignment.Properties.Description) { $assignment.Properties.Description } else { "Assignment of $policyName" }
                    enforcementMode = if ($assignment.Properties.EnforcementMode) { $assignment.Properties.EnforcementMode } else { 'Default' }
                    scope = $assignmentScope
                    policyDefinitionId = $assignment.Properties.PolicyDefinitionId
                    policyName = $policyName
                    parameters = $assignment.Properties.Parameters
                    notScopes = $assignment.Properties.NotScopes
                }
            }
        } catch {
            Write-Host "      ⚠️  Error: $($_.Exception.Message)" -ForegroundColor Yellow
        }
        
        # Get Role Assignments
        Update-CollectionProgress -Step 6 -TotalSteps $totalSteps -Status 'Collecting Role Assignments...'
        try {
            $roles = @()
            $roleKeys = @{}

            # RBAC assignments can be defined at management-group scope and inherited
            # by subscriptions, so query both levels and de-duplicate by assignment ID.
            $roleScopes = @(
                $mgList | ForEach-Object {
                    "/providers/Microsoft.Management/managementGroups/$($_.Name)"
                }
                $subs | ForEach-Object {
                    $subscriptionId = if ($_.Id -match '^/subscriptions/') { $_.Id } else { "/subscriptions/$($_.Id)" }
                    $subscriptionId
                }
            ) | Where-Object { $_ } | Select-Object -Unique

            foreach ($scope in $roleScopes) {
                try {
                    foreach ($role in @(Get-AzRoleAssignment -Scope $scope -ErrorAction SilentlyContinue)) {
                        $key = if ($role.Id) {
                            $role.Id
                        } else {
                            "$($role.Scope)|$($role.ObjectId)|$($role.RoleDefinitionId)"
                        }
                        if (-not $roleKeys.ContainsKey($key)) {
                            $roleKeys[$key] = $true
                            $roles += $role
                        }
                    }
                } catch {
                    Write-Host "      ⚠️  Could not retrieve role assignments at scope: $scope" -ForegroundColor Yellow
                }
            }
            $inventory.summary.totalRoleAssignments = $roles.Count
            
            foreach ($role in $roles) {
                $inventory.roleAssignments += @{
                    displayName = $role.DisplayName
                    signInName = $role.SignInName
                    roleDefinitionName = $role.RoleDefinitionName
                    roleDefinitionId = $role.RoleDefinitionId
                    scope = $role.Scope
                    objectType = $role.ObjectType
                    objectId = $role.ObjectId
                }
            }
        } catch {
            Write-Host "      ⚠️  Could not retrieve role assignments" -ForegroundColor Yellow
        }
        
        # Get Networking Resources (loop through subscriptions)
        Update-CollectionProgress -Step 7 -TotalSteps $totalSteps -Status 'Collecting Networking Resources...'
        foreach ($sub in $subs) {
            try {
                # Try to set context with better error handling
                try {
                    Set-AzContext -SubscriptionId $sub.Id -ErrorAction Stop | Out-Null
                } catch {
                    if ($_.Exception.Message -match 'No such host is known|Unable to acquire token') {
                        Write-Host "      ⚠️  Network connectivity issue for subscription: $($sub.Name) - Skipping" -ForegroundColor Yellow
                        continue
                    } else {
                        throw
                    }
                }
                
                # Virtual Networks
                $vnets = @(Get-AzVirtualNetwork -ErrorAction SilentlyContinue)
                foreach ($vnet in $vnets) {
                    $subnetDetails = @()
                    foreach ($subnet in @($vnet.Subnets)) {
                        $subnetId = if ($subnet.Id) { $subnet.Id } else { "$($vnet.Id)/subnets/$($subnet.Name)" }
                        $subnetAddressPrefixes = if ($subnet.AddressPrefixes) {
                            @($subnet.AddressPrefixes)
                        } elseif ($subnet.AddressPrefix) {
                            @($subnet.AddressPrefix)
                        } else {
                            @()
                        }
                        $routeTableId = if ($subnet.RouteTable -and $subnet.RouteTable.Id) { $subnet.RouteTable.Id } else { $null }
                        $networkSecurityGroupId = if ($subnet.NetworkSecurityGroup -and $subnet.NetworkSecurityGroup.Id) { $subnet.NetworkSecurityGroup.Id } else { $null }
                        $subnetDetail = @{
                            id = $subnetId
                            name = $subnet.Name
                            vnetName = $vnet.Name
                            vnetId = $vnet.Id
                            resourceGroup = $vnet.ResourceGroupName
                            location = $vnet.Location
                            addressPrefix = if ($subnet.AddressPrefix) { $subnet.AddressPrefix } elseif ($subnetAddressPrefixes.Count -gt 0) { $subnetAddressPrefixes[0] } else { $null }
                            addressPrefixes = $subnetAddressPrefixes
                            serviceEndpoints = @($subnet.ServiceEndpoints | ForEach-Object { $_.Service })
                            delegations = @($subnet.Delegations | ForEach-Object {
                                @{
                                    name = $_.Name
                                    serviceName = $_.ServiceName
                                    actions = @($_.Actions)
                                }
                            })
                            routeTableId = $routeTableId
                            routeTable = if ($routeTableId) { Split-Path $routeTableId -Leaf } else { $null }
                            networkSecurityGroupId = $networkSecurityGroupId
                            networkSecurityGroup = if ($networkSecurityGroupId) { Split-Path $networkSecurityGroupId -Leaf } else { $null }
                            privateEndpointNetworkPolicies = $subnet.PrivateEndpointNetworkPolicies
                            privateLinkServiceNetworkPolicies = $subnet.PrivateLinkServiceNetworkPolicies
                            provisioningState = $subnet.ProvisioningState
                            subscription = $sub.Name
                        }
                        $subnetDetails += $subnetDetail
                        $inventory.networking.subnets += $subnetDetail
                    }

                    $inventory.networking.vnets += @{
                        id = $vnet.Id
                        name = $vnet.Name
                        resourceGroup = $vnet.ResourceGroupName
                        location = $vnet.Location
                        addressSpace = @($vnet.AddressSpace.AddressPrefixes)
                        subnets = $subnetDetails
                        dnsServers = $vnet.DhcpOptions.DnsServers
                        tags = $vnet.Tag
                        subscription = $sub.Name
                    }
                }
                $inventory.summary.totalVNets += $vnets.Count
                $inventory.summary.totalSubnets = $inventory.networking.subnets.Count

                # Route tables and UDR routes
                try {
                    $routeTables = @(Get-AzRouteTable -ErrorAction SilentlyContinue)
                    foreach ($routeTable in $routeTables) {
                        $routeDetails = @($routeTable.Routes | ForEach-Object {
                            @{
                                id = $_.Id
                                name = $_.Name
                                addressPrefix = $_.AddressPrefix
                                nextHopType = $_.NextHopType
                                nextHopIpAddress = $_.NextHopIpAddress
                                provisioningState = $_.ProvisioningState
                            }
                        })
                        $associatedSubnets = @($inventory.networking.subnets | Where-Object {
                            $_.routeTableId -and $_.routeTableId -ieq $routeTable.Id
                        } | ForEach-Object {
                            @{
                                id = $_.id
                                name = $_.name
                                vnetName = $_.vnetName
                                vnetId = $_.vnetId
                                displayName = "$($_.vnetName)/$($_.name)"
                            }
                        })

                        $inventory.networking.routeTables += @{
                            id = $routeTable.Id
                            name = $routeTable.Name
                            resourceGroup = $routeTable.ResourceGroupName
                            location = $routeTable.Location
                            disableBgpRoutePropagation = $routeTable.DisableBgpRoutePropagation
                            routes = $routeDetails
                            routeCount = $routeDetails.Count
                            associatedSubnets = $associatedSubnets
                            tags = $routeTable.Tags
                            subscription = $sub.Name
                        }
                    }
                } catch {
                    Write-Host "      ⚠️  Error collecting Route Tables: $($_.Exception.Message)" -ForegroundColor Yellow
                }
                $inventory.summary.totalRouteTables = $inventory.networking.routeTables.Count
                
                # VNet Peerings
                foreach ($vnet in $vnets) {
                    $peerings = $vnet.VirtualNetworkPeerings
                    foreach ($peer in $peerings) {
                        $inventory.networking.peerings += @{
                            name = $peer.Name
                            id = $peer.Id
                            sourceVNet = $vnet.Name
                            sourceVNetId = $vnet.Id
                            sourceResourceGroup = $vnet.ResourceGroupName
                            remoteVNet = Split-Path $peer.RemoteVirtualNetwork.Id -Leaf
                            remoteVNetId = $peer.RemoteVirtualNetwork.Id
                            peeringState = $peer.PeeringState
                            provisioningState = $peer.ProvisioningState
                            allowForwardedTraffic = $peer.AllowForwardedTraffic
                            allowGatewayTransit = $peer.AllowGatewayTransit
                            allowVirtualNetworkAccess = $peer.AllowVirtualNetworkAccess
                            doNotVerifyRemoteGateways = $peer.DoNotVerifyRemoteGateways
                            useRemoteGateways = $peer.UseRemoteGateways
                            remoteAddressSpace = $peer.RemoteVirtualNetworkAddressSpace.AddressPrefixes
                            subscription = $sub.Name
                        }
                    }
                }
                $inventory.summary.totalPeerings = $inventory.networking.peerings.Count
                
                # VPN Gateways - use Get-AzResource to find them
                try {
                    $vpnGatewayResources = Get-AzResource -ResourceType 'Microsoft.Network/virtualNetworkGateways' -ErrorAction SilentlyContinue
                    foreach ($vpnResource in $vpnGatewayResources) {
                        try {
                            $vpn = Get-AzVirtualNetworkGateway -ResourceGroupName $vpnResource.ResourceGroupName -Name $vpnResource.Name -ErrorAction SilentlyContinue
                            if ($vpn) {
                                $inventory.networking.vpnGateways += @{
                                    name = $vpn.Name
                                    resourceGroup = $vpn.ResourceGroupName
                                    location = $vpn.Location
                                    gatewayType = $vpn.GatewayType
                                    vpnType = $vpn.VpnType
                                    sku = $vpn.Sku.Name
                                    activeActive = $vpn.ActiveActive
                                    enableBgp = $vpn.EnableBgp
                                    subscription = $sub.Name
                                }
                            }
                        } catch {}
                    }
                } catch {}
                
                # Azure Firewalls - use Get-AzResource to find them
                try {
                    $firewallResources = Get-AzResource -ResourceType 'Microsoft.Network/azureFirewalls' -ErrorAction SilentlyContinue
                    foreach ($fwResource in $firewallResources) {
                        try {
                            $fw = Get-AzFirewall -ResourceGroupName $fwResource.ResourceGroupName -Name $fwResource.Name -ErrorAction SilentlyContinue
                            if ($fw) {
                                # Check if using Firewall Policy
                                $firewallPolicyId = $null
                                $firewallPolicyName = $null
                                $totalRules = 0
                                
                                if ($fw.FirewallPolicy -and $fw.FirewallPolicy.Id) {
                                    $firewallPolicyId = $fw.FirewallPolicy.Id
                                    $firewallPolicyName = Split-Path $firewallPolicyId -Leaf
                                } else {
                                    # Classic rules (not using policy)
                                    $totalRules = $fw.ApplicationRuleCollections.Count + $fw.NetworkRuleCollections.Count + $fw.NatRuleCollections.Count
                                }
                                
                                $inventory.networking.firewalls += @{
                                    name = $fw.Name
                                    resourceGroup = $fw.ResourceGroupName
                                    location = $fw.Location
                                    tier = $fw.Sku.Tier
                                    threatIntelMode = $fw.ThreatIntelMode
                                    applicationRuleCollections = $fw.ApplicationRuleCollections.Count
                                    networkRuleCollections = $fw.NetworkRuleCollections.Count
                                    natRuleCollections = $fw.NatRuleCollections.Count
                                    totalClassicRules = $totalRules
                                    firewallPolicyId = $firewallPolicyId
                                    firewallPolicyName = $firewallPolicyName
                                    usingPolicy = ($null -ne $firewallPolicyId)
                                    subscription = $sub.Name
                                }
                            }
                        } catch {}
                    }
                    $inventory.summary.totalFirewalls += $firewallResources.Count
                } catch {}
                
                # Azure Firewall Policies
                try {
                    $firewallPolicyResources = Get-AzResource -ResourceType 'Microsoft.Network/firewallPolicies' -ErrorAction SilentlyContinue
                    foreach ($policyResource in $firewallPolicyResources) {
                        try {
                            $policy = Get-AzFirewallPolicy -ResourceGroupName $policyResource.ResourceGroupName -Name $policyResource.Name -ErrorAction SilentlyContinue
                            if ($policy) {
                                # Get rule collection groups via REST API (more reliable than cmdlets for nested data)
                                $rcgApiPath = "$($policy.Id)/ruleCollectionGroups?api-version=2023-11-01"
                                $rcgListResponse = Invoke-AzRestMethod -Path $rcgApiPath -Method GET -ErrorAction SilentlyContinue
                                $rcgList = @()
                                if ($rcgListResponse -and $rcgListResponse.StatusCode -eq 200) {
                                    $rcgListBody = $rcgListResponse.Content | ConvertFrom-Json -Depth 20 -ErrorAction SilentlyContinue
                                    if ($rcgListBody.value) {
                                        $rcgList = @($rcgListBody.value)
                                    }
                                }
                                
                                $totalRuleCollections = 0
                                $totalRules = 0
                                $applicationRuleCollections = 0
                                $networkRuleCollections = 0
                                $natRuleCollections = 0
                                $ruleCollectionGroupCount = 0
                                $ruleCollectionGroupDetails = @()
                                
                                # Parse rule details directly from the REST API response
                                foreach ($rcgItem in $rcgList) {
                                    try {
                                        $rcgProps = $rcgItem.properties
                                        if (-not $rcgProps) { continue }
                                        
                                        $ruleCollectionGroupCount++
                                        $rcgDetail = @{
                                            name            = (Split-Path $rcgItem.id -Leaf)
                                            priority        = $rcgProps.priority
                                            ruleCollections = @()
                                        }
                                        
                                        $ruleCollections = @($rcgProps.ruleCollections)
                                        if ($ruleCollections.Count -gt 0) {
                                            $totalRuleCollections += $ruleCollections.Count
                                            
                                            foreach ($rc in $ruleCollections) {
                                                $rcDetail = @{
                                                    name               = $rc.name
                                                    priority           = $rc.priority
                                                    action             = $rc.action.type
                                                    ruleCollectionType = $rc.ruleCollectionType
                                                    rules              = @()
                                                }
                                                
                                                $rules = @($rc.rules)
                                                if ($rules.Count -gt 0) {
                                                    $totalRules += $rules.Count
                                                    
                                                    foreach ($rule in $rules) {
                                                        $ruleDetail = @{
                                                            name        = $rule.name
                                                            ruleType    = $rule.ruleType
                                                            description = $rule.description
                                                        }
                                                        
                                                        if ($rule.sourceAddresses)  { $ruleDetail.sourceAddresses  = @($rule.sourceAddresses) }
                                                        if ($rule.sourceIpGroups)   { $ruleDetail.sourceIpGroups   = @($rule.sourceIpGroups) }
                                                        
                                                        if ($rule.ruleType -eq 'ApplicationRule') {
                                                            if ($rule.targetFqdns)  { $ruleDetail.targetFqdns  = @($rule.targetFqdns) }
                                                            if ($rule.fqdnTags)     { $ruleDetail.fqdnTags     = @($rule.fqdnTags) }
                                                            if ($rule.webCategories) { $ruleDetail.webCategories = @($rule.webCategories) }
                                                            if ($rule.targetUrls)   { $ruleDetail.targetUrls   = @($rule.targetUrls) }
                                                            if ($rule.protocols)    { $ruleDetail.protocols    = @($rule.protocols | ForEach-Object { "$($_.protocolType):$($_.port)" }) }
                                                        } elseif ($rule.ruleType -eq 'NetworkRule') {
                                                            if ($rule.destinationAddresses) { $ruleDetail.destinationAddresses = @($rule.destinationAddresses) }
                                                            if ($rule.destinationIpGroups)  { $ruleDetail.destinationIpGroups  = @($rule.destinationIpGroups) }
                                                            if ($rule.destinationFqdns)     { $ruleDetail.destinationFqdns     = @($rule.destinationFqdns) }
                                                            if ($rule.destinationPorts)     { $ruleDetail.destinationPorts     = @($rule.destinationPorts) }
                                                            if ($rule.ipProtocols)          { $ruleDetail.ipProtocols          = @($rule.ipProtocols) }
                                                        } elseif ($rule.ruleType -eq 'NatRule') {
                                                            if ($rule.sourceAddresses)      { $ruleDetail.sourceAddresses      = @($rule.sourceAddresses) }
                                                            if ($rule.destinationAddresses) { $ruleDetail.destinationAddresses = @($rule.destinationAddresses) }
                                                            if ($rule.destinationPorts)     { $ruleDetail.destinationPorts     = @($rule.destinationPorts) }
                                                            if ($rule.ipProtocols)          { $ruleDetail.ipProtocols          = @($rule.ipProtocols) }
                                                            if ($rule.translatedAddress)    { $ruleDetail.translatedAddress    = $rule.translatedAddress }
                                                            if ($rule.translatedPort)       { $ruleDetail.translatedPort       = $rule.translatedPort }
                                                            if ($rule.translatedFqdn)       { $ruleDetail.translatedFqdn       = $rule.translatedFqdn }
                                                        }
                                                        
                                                        $rcDetail.rules += $ruleDetail
                                                    }
                                                    
                                                    # Categorize rule collections by type
                                                    if ($rc.ruleCollectionType -eq 'FirewallPolicyFilterRuleCollection') {
                                                        if ($rules[0].ruleType -eq 'ApplicationRule') {
                                                            $applicationRuleCollections++
                                                        } elseif ($rules[0].ruleType -eq 'NetworkRule') {
                                                            $networkRuleCollections++
                                                        }
                                                    } elseif ($rc.ruleCollectionType -eq 'FirewallPolicyNatRuleCollection') {
                                                        $natRuleCollections++
                                                    }
                                                }
                                                
                                                $rcgDetail.ruleCollections += $rcDetail
                                            }
                                        }
                                        
                                        $ruleCollectionGroupDetails += $rcgDetail
                                    } catch {
                                        Write-Host "      ⚠️  Error parsing rule collection group: $($_.Exception.Message)" -ForegroundColor Yellow
                                    }
                                }
                                
                                $inventory.networking.firewallPolicies += @{
                                    name = $policy.Name
                                    id = $policy.Id
                                    resourceGroup = $policy.ResourceGroupName
                                    location = $policy.Location
                                    tier = $policy.Sku.Tier
                                    threatIntelMode = $policy.ThreatIntelMode
                                    threatIntelWhitelist = if ($policy.ThreatIntelWhitelist) { $true } else { $false }
                                    dnsSettings = if ($policy.DnsSettings) { $true } else { $false }
                                    intrusionDetection = if ($policy.IntrusionDetection) { $policy.IntrusionDetection.Mode } else { 'Off' }
                                    ruleCollectionGroups = $ruleCollectionGroupCount
                                    totalRuleCollections = $totalRuleCollections
                                    totalRules = $totalRules
                                    applicationRuleCollections = $applicationRuleCollections
                                    networkRuleCollections = $networkRuleCollections
                                    natRuleCollections = $natRuleCollections
                                    ruleCollectionGroupDetails = $ruleCollectionGroupDetails
                                    basePolicy = if ($policy.BasePolicy) { Split-Path $policy.BasePolicy.Id -Leaf } else { $null }
                                    subscription = $sub.Name
                                }
                            }
                        } catch {
                            Write-Host "      ⚠️  Error processing Firewall Policy: $($policyResource.Name)" -ForegroundColor Yellow
                        }
                    }
                    $inventory.summary.totalFirewallPolicies += $firewallPolicyResources.Count
                } catch {
                    Write-Host "      ⚠️  Error collecting Firewall Policies" -ForegroundColor Yellow
                }
                
                # Virtual Hubs
                try {
                    $virtualHubResources = @(Get-AzResource -ResourceType 'Microsoft.Network/virtualHubs' -ErrorAction Stop)
                    foreach ($hubResource in $virtualHubResources) {
                        try {
                            $hub = Get-AzVirtualHub -ResourceGroupName $hubResource.ResourceGroupName -Name $hubResource.Name -ErrorAction Stop
                            if (-not $hub) { continue }

                        $vnetConnections = @()
                        try {
                            $hubConnections = @(Get-AzVirtualHubVnetConnection -ParentObject $hub -ErrorAction SilentlyContinue)
                            foreach ($connection in $hubConnections) {
                                $remoteVNetId = if ($connection.RemoteVirtualNetwork -and $connection.RemoteVirtualNetwork.Id) { $connection.RemoteVirtualNetwork.Id } else { $null }
                                $vnetConnections += @{
                                    id = $connection.Id
                                    name = $connection.Name
                                    remoteVNetId = $remoteVNetId
                                    remoteVNet = if ($remoteVNetId) { Split-Path $remoteVNetId -Leaf } else { $null }
                                    provisioningState = $connection.ProvisioningState
                                }
                            }
                        } catch {
                            Write-Host "      ⚠️  Error collecting VNet connections for Virtual Hub $($hub.Name): $($_.Exception.Message)" -ForegroundColor Yellow
                        }

                        $virtualWanId = if ($hub.VirtualWan -and $hub.VirtualWan.Id) { $hub.VirtualWan.Id } else { $null }
                        $inventory.networking.virtualHubs += @{
                            id = $hub.Id
                            name = $hub.Name
                            resourceGroup = $hub.ResourceGroupName
                            location = $hub.Location
                            addressPrefix = $hub.AddressPrefix
                            routingState = $hub.RoutingState
                            provisioningState = $hub.ProvisioningState
                            sku = if ($hub.Sku -and $hub.Sku.Name) { $hub.Sku.Name } else { $hub.Sku }
                            hubRoutingPreference = $hub.HubRoutingPreference
                            allowBranchToBranchTraffic = $hub.AllowBranchToBranchTraffic
                            virtualWanId = $virtualWanId
                            virtualWanName = if ($virtualWanId) { Split-Path $virtualWanId -Leaf } else { $null }
                            virtualRouterAsn = $hub.VirtualRouterAsn
                            virtualRouterIps = @($hub.VirtualRouterIps)
                            vnetConnections = $vnetConnections
                            connectionCount = $vnetConnections.Count
                            tags = $hub.Tag
                            subscription = $sub.Name
                        }
                        } catch {
                            Write-Host "      ⚠️  Error processing Virtual Hub $($hubResource.Name): $($_.Exception.Message)" -ForegroundColor Yellow
                        }
                    }
                } catch {
                    Write-Host "      ⚠️  Error collecting Virtual Hubs: $($_.Exception.Message)" -ForegroundColor Yellow
                }
                $inventory.summary.totalVirtualHubs = $inventory.networking.virtualHubs.Count

                # Virtual WANs
                try {
                    $vwanResources = Get-AzResource -ResourceType 'Microsoft.Network/virtualWans' -ErrorAction SilentlyContinue
                    foreach ($vwanResource in $vwanResources) {
                        try {
                            $vwan = Get-AzVirtualWan -ResourceGroupName $vwanResource.ResourceGroupName -Name $vwanResource.Name -ErrorAction SilentlyContinue
                            if ($vwan) {
                                $hubDetails = @($inventory.networking.virtualHubs | Where-Object {
                                    $_.virtualWanId -and $_.virtualWanId -ieq $vwan.Id
                                })
                                
                                $inventory.networking.virtualWans += @{
                                    name = $vwan.Name
                                    id = $vwan.Id
                                    resourceGroup = $vwan.ResourceGroupName
                                    location = $vwan.Location
                                    type = $vwan.Type
                                    allowBranchToBranchTraffic = $vwan.AllowBranchToBranchTraffic
                                    allowVnetToVnetTraffic = $vwan.AllowVnetToVnetTraffic
                                    disableVpnEncryption = $vwan.DisableVpnEncryption
                                    virtualHubCount = $hubDetails.Count
                                    virtualHubs = $hubDetails
                                    tags = $vwan.Tag
                                    subscription = $sub.Name
                                }
                            }
                        } catch {
                            Write-Host "      ⚠️  Error processing Virtual WAN: $($vwanResource.Name)" -ForegroundColor Yellow
                        }
                    }
                    $inventory.summary.totalVirtualWans += $vwanResources.Count
                } catch {
                    Write-Host "      ⚠️  Error collecting Virtual WANs" -ForegroundColor Yellow
                }
                
                # Network Security Groups and their rules/associations
                try {
                    $nsgResources = Get-AzResource -ResourceType 'Microsoft.Network/networkSecurityGroups' -ErrorAction SilentlyContinue
                    foreach ($nsgResource in $nsgResources) {
                        try {
                            $nsg = Get-AzNetworkSecurityGroup -ResourceGroupName $nsgResource.ResourceGroupName -Name $nsgResource.Name -ErrorAction SilentlyContinue
                            if ($nsg) {
                                $associatedSubnets = @()
                                $subnetConnections = @()
                                foreach ($subnet in $nsg.Subnets) {
                                    if ($subnet.Id) {
                                        $subnetName = Split-Path $subnet.Id -Leaf
                                        $vnetId = ($subnet.Id -split '/subnets/')[0]
                                        $vnetName = Split-Path $vnetId -Leaf
                                        $associatedSubnets += "$vnetName/$subnetName"
                                        $subnetConnections += @{
                                            id = $subnet.Id
                                            name = $subnetName
                                            vnetId = $vnetId
                                            vnetName = $vnetName
                                            displayName = "$vnetName/$subnetName"
                                        }
                                    }
                                }
                                
                                $associatedNICs = @()
                                $nicConnections = @()
                                foreach ($nic in $nsg.NetworkInterfaces) {
                                    if ($nic.Id) {
                                        $nicName = Split-Path $nic.Id -Leaf
                                        $associatedNICs += $nicName
                                        $nicResourceGroup = ($nic.Id -split '/')[4]
                                        $nicConnections += @{
                                            id = $nic.Id
                                            name = $nicName
                                            resourceGroup = $nicResourceGroup
                                        }
                                    }
                                }

                                $securityRules = @($nsg.SecurityRules | ForEach-Object {
                                    @{
                                        id = $_.Id
                                        name = $_.Name
                                        description = $_.Description
                                        protocol = $_.Protocol
                                        sourcePortRange = $_.SourcePortRange
                                        sourcePortRanges = @($_.SourcePortRanges)
                                        destinationPortRange = $_.DestinationPortRange
                                        destinationPortRanges = @($_.DestinationPortRanges)
                                        sourceAddressPrefix = $_.SourceAddressPrefix
                                        sourceAddressPrefixes = @($_.SourceAddressPrefixes)
                                        destinationAddressPrefix = $_.DestinationAddressPrefix
                                        destinationAddressPrefixes = @($_.DestinationAddressPrefixes)
                                        sourceApplicationSecurityGroups = @($_.SourceApplicationSecurityGroups | ForEach-Object { $_.Id })
                                        destinationApplicationSecurityGroups = @($_.DestinationApplicationSecurityGroups | ForEach-Object { $_.Id })
                                        access = $_.Access
                                        priority = $_.Priority
                                        direction = $_.Direction
                                        provisioningState = $_.ProvisioningState
                                    }
                                })
                                $defaultSecurityRules = @($nsg.DefaultSecurityRules | ForEach-Object {
                                    @{
                                        id = $_.Id
                                        name = $_.Name
                                        description = $_.Description
                                        protocol = $_.Protocol
                                        sourcePortRange = $_.SourcePortRange
                                        sourcePortRanges = @($_.SourcePortRanges)
                                        destinationPortRange = $_.DestinationPortRange
                                        destinationPortRanges = @($_.DestinationPortRanges)
                                        sourceAddressPrefix = $_.SourceAddressPrefix
                                        sourceAddressPrefixes = @($_.SourceAddressPrefixes)
                                        destinationAddressPrefix = $_.DestinationAddressPrefix
                                        destinationAddressPrefixes = @($_.DestinationAddressPrefixes)
                                        sourceApplicationSecurityGroups = @($_.SourceApplicationSecurityGroups | ForEach-Object { $_.Id })
                                        destinationApplicationSecurityGroups = @($_.DestinationApplicationSecurityGroups | ForEach-Object { $_.Id })
                                        access = $_.Access
                                        priority = $_.Priority
                                        direction = $_.Direction
                                        provisioningState = $_.ProvisioningState
                                    }
                                })
                                
                                $inventory.networking.networkSecurityGroups += @{
                                    id = $nsg.Id
                                    name = $nsg.Name
                                    resourceGroup = $nsg.ResourceGroupName
                                    location = $nsg.Location
                                    securityRulesCount = $securityRules.Count
                                    defaultSecurityRulesCount = $defaultSecurityRules.Count
                                    securityRules = $securityRules
                                    defaultSecurityRules = $defaultSecurityRules
                                    associatedSubnets = $associatedSubnets
                                    subnetConnections = $subnetConnections
                                    associatedNICs = $associatedNICs
                                    nicConnections = $nicConnections
                                    tags = $nsg.Tags
                                    subscription = $sub.Name
                                }
                            }
                        } catch {}
                    }
                } catch {}
                
                # Private DNS Zones
                try {
                    $privateDnsZones = Get-AzPrivateDnsZone -ErrorAction SilentlyContinue
                    foreach ($zone in $privateDnsZones) {
                        try {
                            # Get virtual network links for this zone
                            $vnetLinks = Get-AzPrivateDnsVirtualNetworkLink -ResourceGroupName $zone.ResourceGroupName -ZoneName $zone.Name -ErrorAction SilentlyContinue
                            $linkedVNets = @()
                            foreach ($link in $vnetLinks) {
                                $vnetName = if ($link.VirtualNetwork.Id) { Split-Path $link.VirtualNetwork.Id -Leaf } else { 'N/A' }
                                $linkedVNets += @{
                                    linkName = $link.Name
                                    vnetName = $vnetName
                                    vnetId = $link.VirtualNetwork.Id
                                    registrationEnabled = $link.RegistrationEnabled
                                }
                            }
                            
                            # Get record sets count
                            $recordSets = Get-AzPrivateDnsRecordSet -ResourceGroupName $zone.ResourceGroupName -ZoneName $zone.Name -ErrorAction SilentlyContinue
                            
                            $inventory.networking.privateDnsZones += @{
                                name = $zone.Name
                                id = $zone.Id
                                resourceGroup = $zone.ResourceGroupName
                                location = $zone.Location
                                numberOfRecordSets = $recordSets.Count
                                numberOfVirtualNetworkLinks = $vnetLinks.Count
                                virtualNetworkLinks = $linkedVNets
                                tags = $zone.Tags
                                subscription = $sub.Name
                            }
                        } catch {
                            Write-Host "      ⚠️  Error processing Private DNS Zone: $($zone.Name)" -ForegroundColor Yellow
                        }
                    }
                    $inventory.summary.totalPrivateDnsZones += $privateDnsZones.Count
                } catch {
                    Write-Host "      ⚠️  Error collecting Private DNS Zones" -ForegroundColor Yellow
                }
                
                # Private Endpoints
                try {
                    $privateEndpoints = Get-AzPrivateEndpoint -ErrorAction SilentlyContinue
                    foreach ($pe in $privateEndpoints) {
                        try {
                            # Get private link service connection details
                            $connections = @()
                            foreach ($conn in $pe.PrivateLinkServiceConnections) {
                                $connections += @{
                                    name = $conn.Name
                                    privateLinkServiceId = $conn.PrivateLinkServiceId
                                    groupIds = $conn.GroupIds
                                    requestMessage = $conn.RequestMessage
                                    status = $conn.PrivateLinkServiceConnectionState.Status
                                }
                            }
                            
                            # Get subnet and VNet info
                            $subnetId = if ($pe.Subnet.Id) { $pe.Subnet.Id } else { $null }
                            $vnetName = if ($subnetId) { ($subnetId -split '/subnets/')[0] | Split-Path -Leaf } else { 'N/A' }
                            $subnetName = if ($subnetId) { Split-Path $subnetId -Leaf } else { 'N/A' }
                            
                            # Get private IP addresses
                            $privateIPs = @()
                            foreach ($ipConfig in $pe.NetworkInterfaces) {
                                if ($ipConfig.Id) {
                                    try {
                                        $nicRG = ($ipConfig.Id -split '/')[4]
                                        $nicName = Split-Path $ipConfig.Id -Leaf
                                        $nic = Get-AzNetworkInterface -ResourceGroupName $nicRG -Name $nicName -ErrorAction SilentlyContinue
                                        if ($nic) {
                                            foreach ($ip in $nic.IpConfigurations) {
                                                if ($ip.PrivateIpAddress) {
                                                    $privateIPs += $ip.PrivateIpAddress
                                                }
                                            }
                                        }
                                    } catch {}
                                }
                            }
                            
                            # Get connected resource name from the first connection
                            $connectedResource = 'N/A'
                            if ($connections.Count -gt 0 -and $connections[0].privateLinkServiceId) {
                                $connectedResource = Split-Path $connections[0].privateLinkServiceId -Leaf
                            }
                            
                            $inventory.networking.privateEndpoints += @{
                                name = $pe.Name
                                id = $pe.Id
                                resourceGroup = $pe.ResourceGroupName
                                location = $pe.Location
                                vnet = $vnetName
                                subnet = $subnetName
                                privateIPs = $privateIPs
                                connections = $connections
                                connectedResource = $connectedResource
                                provisioningState = $pe.ProvisioningState
                                tags = $pe.Tag
                                subscription = $sub.Name
                            }
                        } catch {
                            Write-Host "      ⚠️  Error processing Private Endpoint: $($pe.Name)" -ForegroundColor Yellow
                        }
                    }
                    $inventory.summary.totalPrivateEndpoints += $privateEndpoints.Count
                } catch {
                    Write-Host "      ⚠️  Error collecting Private Endpoints" -ForegroundColor Yellow
                }
                
            } catch {
                Write-Host "      ⚠️  Error collecting network resources in sub: $($sub.Name)" -ForegroundColor Yellow
            }
        }
        
        # Get Virtual Machines
        Update-CollectionProgress -Step 8 -TotalSteps $totalSteps -Status 'Collecting Virtual Machines...'
        foreach ($sub in $subs) {
            try {
                # Try to set context with better error handling
                try {
                    Set-AzContext -SubscriptionId $sub.Id -ErrorAction Stop | Out-Null
                } catch {
                    if ($_.Exception.Message -match 'No such host is known|Unable to acquire token') {
                        Write-Host "      ⚠️  Network connectivity issue for subscription: $($sub.Name) - Skipping" -ForegroundColor Yellow
                        continue
                    } else {
                        throw
                    }
                }
                
                $vms = Get-AzVM -Status -ErrorAction SilentlyContinue
                foreach ($vm in $vms) {
                    # Get network interfaces
                    $nics = @()
                    $vmVNet = $null
                    $vmSubnet = $null
                    $privateIPs = @()
                    $publicIPs = @()
                    
                    foreach ($nicRef in $vm.NetworkProfile.NetworkInterfaces) {
                        try {
                            $nicId = $nicRef.Id
                            $nicRG = ($nicId -split '/')[4]
                            $nicName = Split-Path $nicId -Leaf
                            $nic = Get-AzNetworkInterface -ResourceGroupName $nicRG -Name $nicName -ErrorAction SilentlyContinue
                            
                            if ($nic) {
                                $nics += $nic.Name
                                
                                foreach ($ipConfig in $nic.IpConfigurations) {
                                    if ($ipConfig.PrivateIpAddress) {
                                        $privateIPs += $ipConfig.PrivateIpAddress
                                    }
                                    
                                    if ($ipConfig.Subnet) {
                                        $subnetId = $ipConfig.Subnet.Id
                                        $vmVNet = ($subnetId -split '/subnets/')[0] | Split-Path -Leaf
                                        $vmSubnet = Split-Path $subnetId -Leaf
                                    }
                                    
                                    if ($ipConfig.PublicIpAddress) {
                                        $pipId = $ipConfig.PublicIpAddress.Id
                                        $pipRG = ($pipId -split '/')[4]
                                        $pipName = Split-Path $pipId -Leaf
                                        $pip = Get-AzPublicIpAddress -ResourceGroupName $pipRG -Name $pipName -ErrorAction SilentlyContinue
                                        if ($pip -and $pip.IpAddress) {
                                            $publicIPs += $pip.IpAddress
                                        }
                                    }
                                }
                            }
                        } catch {}
                    }
                    
                    # Get OS disk info
                    $osDiskSize = 0
                    if ($vm.StorageProfile.OsDisk.DiskSizeGB) {
                        $osDiskSize = $vm.StorageProfile.OsDisk.DiskSizeGB
                    }
                    
                    $powerState = ($vm.PowerState -replace 'PowerState/', '')
                    
                    $inventory.compute.virtualMachines += @{
                        name = $vm.Name
                        id = $vm.Id
                        resourceGroup = $vm.ResourceGroupName
                        location = $vm.Location
                        vmSize = $vm.HardwareProfile.VmSize
                        osType = $vm.StorageProfile.OsDisk.OsType
                        osDiskSizeGB = $osDiskSize
                        dataDisksCount = $vm.StorageProfile.DataDisks.Count
                        powerState = $powerState
                        provisioningState = $vm.ProvisioningState
                        networkInterfaces = $nics
                        vnet = $vmVNet
                        subnet = $vmSubnet
                        privateIPs = $privateIPs
                        publicIPs = $publicIPs
                        availabilitySet = if ($vm.AvailabilitySetReference) { Split-Path $vm.AvailabilitySetReference.Id -Leaf } else { $null }
                        tags = $vm.Tags
                        subscription = $sub.Name
                    }
                }
                $inventory.summary.totalVMs += $vms.Count
                
            } catch {
                Write-Host "      ⚠️  Error collecting VMs in sub: $($sub.Name)" -ForegroundColor Yellow
            }
        }
        
        # Get Governance Resources
        Update-CollectionProgress -Step 9 -TotalSteps $totalSteps -Status 'Collecting Governance Resources...'

        # Budgets are collected at billing-account scope because Billing Reader access
        # does not necessarily grant subscription-level Microsoft.Consumption access.
        try {
            $billingAccounts = @(Get-AzBillingAccount -ErrorAction Stop)
            foreach ($billingAccount in $billingAccounts) {
                $billingAccountName = if ($billingAccount.Name) { $billingAccount.Name } else { $billingAccount.Id.Split('/')[-1] }
                $nextLink = "https://management.azure.com/providers/Microsoft.Billing/billingAccounts/$([uri]::EscapeDataString($billingAccountName))/providers/Microsoft.Consumption/budgets?api-version=2023-05-01"

                do {
                    $budgetResponse = Invoke-AzRestMethod -Method GET -Uri $nextLink -ErrorAction Stop
                    $budgetPayload = $budgetResponse.Content | ConvertFrom-Json
                    foreach ($budget in @($budgetPayload.value)) {
                        $properties = $budget.properties
                        $inventory.governance.budgets += @{
                            name = $budget.name
                            amount = $properties.amount
                            timeGrain = $properties.timeGrain
                            timePeriod = @{
                                startDate = $properties.timePeriod.startDate
                                endDate = $properties.timePeriod.endDate
                            }
                            currentSpend = $properties.currentSpend.amount
                            billingAccount = $billingAccountName
                            scope = $budget.id
                        }
                    }
                    $nextLink = $budgetPayload.nextLink
                } while ($nextLink)
            }
            $inventory.summary.totalBudgets = @($inventory.governance.budgets).Count
            Write-Host "      ✓ Collected $($inventory.summary.totalBudgets) budget(s) from $($billingAccounts.Count) billing account(s)" -ForegroundColor Green
        } catch {
            Write-Host "      ⚠️  Could not collect billing-account budgets: $($_.Exception.Message)" -ForegroundColor Yellow
        }

        foreach ($sub in $subs) {
            try {
                # Try to set context with better error handling
                try {
                    Set-AzContext -SubscriptionId $sub.Id -ErrorAction Stop | Out-Null
                } catch {
                    if ($_.Exception.Message -match 'No such host is known|Unable to acquire token') {
                        Write-Host "      ⚠️  Network connectivity issue for subscription: $($sub.Name) - Skipping" -ForegroundColor Yellow
                        continue
                    } else {
                        throw
                    }
                }
                
                # Defender for Cloud pricing plans
                try {
                    $defenderResources = @(Get-AzResource -ResourceType 'Microsoft.Security/pricings' -ErrorAction SilentlyContinue)
                    foreach ($defenderResource in $defenderResources) {
                        $inventory.governance.defenderPlans += @{
                            name = $defenderResource.Name
                            id = $defenderResource.ResourceId
                            subscription = $sub.Name
                        }
                    }
                } catch {}
                
                # Resource Locks (subscription, resource groups, and resources)
                Write-Host "      • Collecting resource locks..." -ForegroundColor Gray
                try {
                    # Get locks at subscription level
                    $subLocks = Get-AzResourceLock -Scope "/subscriptions/$($sub.Id)" -ErrorAction SilentlyContinue
                    foreach ($lock in $subLocks) {
                        $inventory.governance.locks += @{
                            name = $lock.Name
                            resourceName = if ($lock.ResourceName) { $lock.ResourceName } else { "Subscription: $($sub.Name)" }
                            resourceType = if ($lock.ResourceType) { $lock.ResourceType } else { "Subscription" }
                            resourceGroup = $lock.ResourceGroupName
                            level = $lock.Properties.Level
                            notes = $lock.Properties.Notes
                            subscription = $sub.Name
                            scope = "Subscription"
                        }
                    }
                    
                    # Get locks at resource group level
                    $resourceGroups = Get-AzResourceGroup -ErrorAction SilentlyContinue
                    foreach ($rg in $resourceGroups) {
                        $rgLocks = Get-AzResourceLock -ResourceGroupName $rg.ResourceGroupName -ErrorAction SilentlyContinue
                        foreach ($lock in $rgLocks) {
                            # Avoid duplicates if already collected at subscription level
                            $lockExists = $inventory.governance.locks | Where-Object { 
                                $_.name -eq $lock.Name -and $_.resourceGroup -eq $lock.ResourceGroupName 
                            }
                            if (-not $lockExists) {
                                $inventory.governance.locks += @{
                                    name = $lock.Name
                                    resourceName = if ($lock.ResourceName) { $lock.ResourceName } else { "Resource Group: $($rg.ResourceGroupName)" }
                                    resourceType = if ($lock.ResourceType) { $lock.ResourceType } else { "ResourceGroup" }
                                    resourceGroup = $rg.ResourceGroupName
                                    level = $lock.Properties.Level
                                    notes = $lock.Properties.Notes
                                    subscription = $sub.Name
                                    scope = "ResourceGroup"
                                }
                            }
                        }
                    }
                    
                    $lockCount = ($inventory.governance.locks | Where-Object { $_.subscription -eq $sub.Name }).Count
                    $inventory.summary.totalLocks += $lockCount
                    Write-Host "      ✓ Collected $lockCount locks" -ForegroundColor Green
                } catch {
                    Write-Host "      ⚠️  Error collecting locks" -ForegroundColor Yellow
                }
                
                # Collect tags from subscriptions, resource groups, and selected resources
                Write-Host "      • Collecting tags..." -ForegroundColor Gray
                try {
                    # Subscription tags
                    $subResource = Get-AzSubscription -SubscriptionId $sub.Id -ErrorAction SilentlyContinue
                    if ($subResource.Tags) {
                        foreach ($tagKey in $subResource.Tags.Keys) {
                            if (-not $inventory.governance.tags.ContainsKey($tagKey)) {
                                $inventory.governance.tags[$tagKey] = @()
                            }
                            $tagValue = $subResource.Tags[$tagKey]
                            if ($tagValue -notin $inventory.governance.tags[$tagKey]) {
                                $inventory.governance.tags[$tagKey] += $tagValue
                            }
                        }
                    }
                    
                    # Resource group tags
                    foreach ($rg in $resourceGroups) {
                        if ($rg.Tags) {
                            foreach ($tagKey in $rg.Tags.Keys) {
                                if (-not $inventory.governance.tags.ContainsKey($tagKey)) {
                                    $inventory.governance.tags[$tagKey] = @()
                                }
                                $tagValue = $rg.Tags[$tagKey]
                                if ($tagValue -notin $inventory.governance.tags[$tagKey]) {
                                    $inventory.governance.tags[$tagKey] += $tagValue
                                }
                            }
                        }
                    }
                    
                    # Sample resource tags (limit to avoid performance issues)
                    $sampleResources = Get-AzResource -ErrorAction SilentlyContinue | Select-Object -First 100
                    foreach ($resource in $sampleResources) {
                        if ($resource.Tags) {
                            foreach ($tagKey in $resource.Tags.Keys) {
                                if (-not $inventory.governance.tags.ContainsKey($tagKey)) {
                                    $inventory.governance.tags[$tagKey] = @()
                                }
                                $tagValue = $resource.Tags[$tagKey]
                                if ($tagValue -notin $inventory.governance.tags[$tagKey]) {
                                    $inventory.governance.tags[$tagKey] += $tagValue
                                }
                            }
                        }
                    }
                    
                    Write-Host "      ✓ Collected $($inventory.governance.tags.Keys.Count) unique tag keys" -ForegroundColor Green
                } catch {
                    Write-Host "      ⚠️  Error collecting tags" -ForegroundColor Yellow
                }
                
            } catch {
                Write-Host "      ⚠️  Error collecting governance resources in sub: $($sub.Name)" -ForegroundColor Yellow
            }
        }
        
        Write-Host "    ✓ Inventory collection complete" -ForegroundColor Green
        
        # Evaluate Best Practices Compliance
        Update-CollectionProgress -Step 10 -TotalSteps $totalSteps -Status 'Evaluating Cloud Adoption Framework compliance...'
        $inventory.bestPractices = Get-LandingZoneBestPracticesAssessment -Inventory $inventory
        Update-CollectionProgress -Step 11 -TotalSteps $totalSteps -Status 'Complete!'
        Write-Host "    ✓ Best practices assessment complete" -ForegroundColor Green
        
    } catch {
        Write-Host "    ✗ Error during inventory collection: $($_.Exception.Message)" -ForegroundColor Red
        throw
    }
    
    return $inventory
}

function Get-LandingZoneBestPracticesAssessment {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [hashtable]$Inventory,
        [Parameter(Mandatory=$false)]
        [string]$ConfigPath = "$PSScriptRoot/scoring-config.json"
    )
    
    # Load scoring configuration
    if (-not (Test-Path $ConfigPath)) {
        Write-Warning "Scoring configuration file not found at: $ConfigPath. Using default scoring."
        $ConfigPath = "$PSScriptRoot/scoring-config.json"
    }
    
    $scoringConfig = Get-Content $ConfigPath -Raw | ConvertFrom-Json
    Write-Host "  📋 Loaded scoring configuration v$($scoringConfig.version)" -ForegroundColor Cyan
    
    # Initialize assessment structure from config
    $assessment = @{
        overallScore = 0
        maxScore = 0
        recommendations = @()
        configVersion = $scoringConfig.version
        categories = @{}
    }
    
    # Build categories from config
    foreach ($catKey in $scoringConfig.categories.PSObject.Properties.Name) {
        $catConfig = $scoringConfig.categories.$catKey
        $assessment.categories[$catKey] = @{
            score = 0
            maxScore = $catConfig.maxScore
            status = 'fail'
            findings = @()
            name = $catConfig.name
            description = $catConfig.description
        }
    }
    
    # Gather metrics from inventory (with defaults to handle missing data)
    $metrics = @{
        mgCount = $Inventory.summary.totalManagementGroups ?? 0
        subCount = $Inventory.summary.totalSubscriptions ?? 0
        policyDefs = $Inventory.summary.totalPolicyDefinitions ?? 0
        policyInits = $Inventory.summary.totalPolicyInitiatives ?? 0
        policyAssigns = $Inventory.summary.totalPolicyAssignments ?? 0
        roleAssigns = $Inventory.summary.totalRoleAssignments ?? 0
        vnetCount = $Inventory.summary.totalVNets ?? 0
        peeringCount = $Inventory.summary.totalPeerings ?? 0
        vpnCount = if ($Inventory.networking.vpnGateways) { $Inventory.networking.vpnGateways.Count } else { 0 }
        fwCount = if ($Inventory.networking.firewalls) { $Inventory.networking.firewalls.Count } else { 0 }
        expressRouteCount = if ($Inventory.networking.expressRoutes) { $Inventory.networking.expressRoutes.Count } else { 0 }
        privateDnsCount = if ($Inventory.networking.privateDnsZones) { $Inventory.networking.privateDnsZones.Count } else { 0 }
        defenderCount = if ($Inventory.governance.defenderPlans) { $Inventory.governance.defenderPlans.Count } else { 0 }
        nsgEligibleCount = @($Inventory.networking.subnets | Where-Object {
            $_.name -and $_.name -notmatch '^(AzureFirewallSubnet|GatewaySubnet|RouteServerSubnet)$'
        }).Count
        nsgProtectedCount = @($Inventory.networking.subnets | Where-Object {
            $_.name -and $_.name -notmatch '^(AzureFirewallSubnet|GatewaySubnet|RouteServerSubnet)$' -and $_.networkSecurityGroupId
        }).Count
        locks = $Inventory.summary.totalLocks ?? 0
        nsgCount = if ($Inventory.networking.networkSecurityGroups) { $Inventory.networking.networkSecurityGroups.Count } else { 0 }
        budgets = @($Inventory.governance.budgets | Where-Object { $_ }).Count
        tagCount = if ($Inventory.governance.tags.Keys) { $Inventory.governance.tags.Keys.Count } else { 0 }
        hasPrivilegedRoles = [bool]($Inventory.roleAssignments | Where-Object { $_.roleDefinitionName -match 'Owner|Contributor' })
    }
    
    # Process each category and its rules from config
    foreach ($catKey in $scoringConfig.categories.PSObject.Properties.Name) {
        $catConfig = $scoringConfig.categories.$catKey
        $category = $assessment.categories[$catKey]
        
        Write-Host "    Evaluating: $($catConfig.name)" -ForegroundColor Gray
        
        foreach ($rule in $catConfig.rules) {
            $conditionMet = $false
            $partialConditionMet = $false
            
            # Evaluate main condition
            try {
                $conditionMet = Test-ScoringCondition -Condition $rule.condition -Metrics $metrics
            } catch {
                Write-Warning "Failed to evaluate condition for rule $($rule.id): $($rule.condition) | Error: $($_.Exception.Message)"
                $conditionMet = $false
            }
            
            # Evaluate partial points condition if exists
            if ($rule.partialPoints -and -not $conditionMet) {
                try {
                    $partialConditionMet = Test-ScoringCondition -Condition $rule.partialPoints.condition -Metrics $metrics
                } catch {
                    $partialConditionMet = $false
                }
            }
            
            # Award points and add findings
            if ($conditionMet) {
                $category.score += $rule.points
                $category.findings += "✓ $($rule.description)"
            } elseif ($partialConditionMet) {
                $category.score += $rule.partialPoints.points
                $category.findings += "⚠ $($rule.description) (Partial)"
                $assessment.recommendations += $rule.recommendation
            } else {
                $category.findings += "✗ $($rule.description)"
                $assessment.recommendations += $rule.recommendation
            }
        }
    }
    
    # Legacy scoring logic kept for backward compatibility (can be removed if config covers all cases)
    # The sections below are now handled by the config file
    
    # 1. Management Group Hierarchy Assessment - NOW IN CONFIG
    <#
    $mgCount = $Inventory.summary.totalManagementGroups
    $subCount = $Inventory.summary.totalSubscriptions
    
    if ($mgCount -ge 2) {
        $assessment.categories.managementGroupHierarchy.score += 5
        $assessment.categories.managementGroupHierarchy.findings += "✓ Management group hierarchy is implemented ($mgCount groups)"
    } else {
        $assessment.categories.managementGroupHierarchy.findings += "✗ Limited management group structure. Recommended: Use hierarchical management groups for organizational alignment"
        $assessment.recommendations += "Implement a management group hierarchy (e.g., Root > Platform/Landing Zones > Corp/Online)"
    }
    
    if ($mgCount -ge 3 -and $mgCount -le 6) {
        $assessment.categories.managementGroupHierarchy.score += 5
        $assessment.categories.managementGroupHierarchy.findings += "✓ Management group hierarchy follows CAF recommendations (3-6 levels)"
    } elseif ($mgCount -gt 6) {
        $assessment.categories.managementGroupHierarchy.findings += "⚠ Management group hierarchy may be too deep. Recommended: 3-6 levels maximum"
        $assessment.recommendations += "Simplify management group structure to 3-6 levels for better manageability"
    }
    
    if ($subCount -ge 3) {
        $assessment.categories.managementGroupHierarchy.score += 5
        $assessment.categories.managementGroupHierarchy.findings += "✓ Multiple subscriptions for workload isolation ($subCount subscriptions)"
    } elseif ($subCount -gt 0) {
        $assessment.categories.managementGroupHierarchy.findings += "⚠ Consider using multiple subscriptions for better workload isolation and scale"
        $assessment.recommendations += "Adopt subscription democratization: Use separate subscriptions for platform, landing zones, and workloads"
    }
    
    # 2. Policy-Driven Governance Assessment
    $policyDefs = $Inventory.summary.totalPolicyDefinitions
    $policyInits = $Inventory.summary.totalPolicyInitiatives
    $policyAssigns = $Inventory.summary.totalPolicyAssignments
    
    if ($policyDefs -gt 0 -or $policyInits -gt 0) {
        $assessment.categories.policyDrivenGovernance.score += 5
        $assessment.categories.policyDrivenGovernance.findings += "✓ Custom policies/initiatives defined ($policyDefs definitions, $policyInits initiatives)"
    } else {
        $assessment.categories.policyDrivenGovernance.findings += "⚠ No custom policies found. Consider implementing custom policies for organizational requirements"
        $assessment.recommendations += "Define custom Azure Policies for security, compliance, and governance requirements"
    }
    
    if ($policyAssigns -ge 5) {
        $assessment.categories.policyDrivenGovernance.score += 10
        $assessment.categories.policyDrivenGovernance.findings += "✓ Active policy assignments at scale ($policyAssigns assignments)"
    } elseif ($policyAssigns -gt 0) {
        $assessment.categories.policyDrivenGovernance.score += 5
        $assessment.categories.policyDrivenGovernance.findings += "⚠ Limited policy assignments. Recommended: Apply policies at management group level"
        $assessment.recommendations += "Increase policy coverage by assigning policies at management group scope"
    } else {
        $assessment.categories.policyDrivenGovernance.findings += "✗ No policy assignments found. Critical: Implement Azure Policy for governance"
        $assessment.recommendations += "Assign Azure Policy initiatives (e.g., Azure Security Benchmark, regulatory compliance)"
    }
    
    if ($policyInits -gt 0) {
        $assessment.categories.policyDrivenGovernance.score += 5
        $assessment.categories.policyDrivenGovernance.findings += "✓ Policy initiatives (grouped policies) are being used"
    }
    
    # 3. Identity and Access Management Assessment
    $roleAssigns = $Inventory.summary.totalRoleAssignments
    
    if ($roleAssigns -ge 10) {
        $assessment.categories.identityAndAccess.score += 10
        $assessment.categories.identityAndAccess.findings += "✓ RBAC actively implemented ($roleAssigns role assignments)"
    } elseif ($roleAssigns -gt 0) {
        $assessment.categories.identityAndAccess.score += 5
        $assessment.categories.identityAndAccess.findings += "⚠ Limited RBAC implementation. Recommended: Implement least-privilege access"
        $assessment.recommendations += "Expand RBAC implementation with custom roles and group-based assignments"
    } else {
        $assessment.categories.identityAndAccess.findings += "✗ No custom role assignments. Implement RBAC for identity-based access control"
        $assessment.recommendations += "Define and assign Azure RBAC roles at management group and subscription scopes"
    }
    
    # Check for privileged roles (Owner/Contributor)
    $hasPrivilegedRoles = $Inventory.roleAssignments | Where-Object { $_.roleDefinitionName -match 'Owner|Contributor' }
    if ($hasPrivilegedRoles) {
        $assessment.categories.identityAndAccess.score += 5
        $assessment.categories.identityAndAccess.findings += "✓ Privileged roles detected. Ensure these follow least-privilege principle"
    }
    
    # 4. Network Topology and Connectivity Assessment
    $vnetCount = $Inventory.summary.totalVNets
    $peeringCount = $Inventory.summary.totalPeerings
    $vpnCount = $Inventory.networking.vpnGateways.Count
    $fwCount = $Inventory.networking.firewalls.Count
    
    if ($vnetCount -ge 2) {
        $assessment.categories.networkTopology.score += 5
        $assessment.categories.networkTopology.findings += "✓ Multiple VNets for network segmentation ($vnetCount VNets)"
    } elseif ($vnetCount -eq 1) {
        $assessment.categories.networkTopology.findings += "⚠ Single VNet detected. Consider hub-spoke topology for scalable architecture"
        $assessment.recommendations += "Implement hub-spoke network topology or Azure Virtual WAN for enterprise-scale connectivity"
    } else {
        $assessment.categories.networkTopology.findings += "✗ No VNets found. Deploy networking infrastructure"
    }
    
    if ($peeringCount -gt 0 -and $vnetCount -ge 2) {
        $assessment.categories.networkTopology.score += 10
        $assessment.categories.networkTopology.findings += "✓ VNet peering implemented for connectivity ($peeringCount peerings)"
    } elseif ($vnetCount -ge 2) {
        $assessment.categories.networkTopology.findings += "⚠ Multiple VNets without peering. Recommended: Implement hub-spoke with VNet peering"
        $assessment.recommendations += "Connect VNets using peering or Virtual WAN for centralized connectivity"
    }
    
    if ($vpnCount -gt 0 -or $fwCount -gt 0) {
        $assessment.categories.networkTopology.score += 5
        $assessment.categories.networkTopology.findings += "✓ Network security appliances deployed (VPN: $vpnCount, Firewalls: $fwCount)"
    } else {
        $assessment.categories.networkTopology.findings += "⚠ No VPN gateways or firewalls detected. Consider Azure Firewall or NVA for hub connectivity"
        $assessment.recommendations += "Deploy Azure Firewall in hub VNet for centralized security and egress control"
    }
    
    # 5. Security and Governance Assessment
    $locks = $Inventory.summary.totalLocks
    $nsgCount = $Inventory.networking.networkSecurityGroups.Count
    
    if ($locks -gt 0) {
        $assessment.categories.securityGovernance.score += 5
        $assessment.categories.securityGovernance.findings += "✓ Resource locks implemented for protection ($locks locks)"
    } else {
        $assessment.categories.securityGovernance.findings += "⚠ No resource locks found. Recommended: Lock critical resources"
        $assessment.recommendations += "Apply CanNotDelete locks on critical resources (networking, shared services)"
    }
    
    if ($nsgCount -gt 0) {
        $assessment.categories.securityGovernance.score += 5
        $assessment.categories.securityGovernance.findings += "✓ Network Security Groups deployed ($nsgCount NSGs)"
    } else {
        $assessment.categories.securityGovernance.findings += "⚠ No NSGs detected. Implement network segmentation"
        $assessment.recommendations += "Deploy Network Security Groups for subnet-level security and micro-segmentation"
    }
    
    # 6. Cost Management Assessment
    $budgets = $Inventory.summary.totalBudgets
    
    if ($budgets -ge 3) {
        $assessment.categories.costManagement.score += 10
        $assessment.categories.costManagement.findings += "✓ Cost management with budgets ($budgets budgets)"
    } elseif ($budgets -gt 0) {
        $assessment.categories.costManagement.score += 5
        $assessment.categories.costManagement.findings += "⚠ Limited budget coverage. Recommended: Budget per subscription"
        $assessment.recommendations += "Create budgets for all subscriptions with alerting thresholds"
    } else {
        $assessment.categories.costManagement.findings += "✗ No budgets configured. Implement cost management and monitoring"
        $assessment.recommendations += "Configure Azure Budgets and Cost Management alerts for financial governance"
    }
    
    # 7. Resource Organization Assessment
    $tagCount = $Inventory.governance.tags.Keys.Count
    
    if ($tagCount -ge 5) {
        $assessment.categories.resourceOrganization.score += 10
        $assessment.categories.resourceOrganization.findings += "✓ Comprehensive tagging strategy ($tagCount tag keys)"
    } elseif ($tagCount -gt 0) {
        $assessment.categories.resourceOrganization.score += 5
        $assessment.categories.resourceOrganization.findings += "⚠ Basic tagging implemented. Recommended: Standardize tags (Environment, CostCenter, Owner, etc.)"
        $assessment.recommendations += "Define and enforce tagging policy with required tags: Environment, CostCenter, Owner, Application"
    } else {
        $assessment.categories.resourceOrganization.findings += "✗ No tags detected. Implement tagging strategy for resource organization"
        $assessment.recommendations += "Implement mandatory tagging policy using Azure Policy Modify effect"
    }
    #>

    
    # Calculate overall scores using config thresholds
    foreach ($category in $assessment.categories.Keys) {
        $cat = $assessment.categories[$category]
        $assessment.maxScore += $cat.maxScore
        $assessment.overallScore += $cat.score
        
        # Determine status from config thresholds
        $percentage = if ($cat.maxScore -gt 0) { ($cat.score / $cat.maxScore) * 100 } else { 0 }
        
        if ($percentage -ge $scoringConfig.scoringThresholds.excellent.min) {
            $cat.status = 'excellent'
        } elseif ($percentage -ge $scoringConfig.scoringThresholds.good.min) {
            $cat.status = 'good'
        } elseif ($percentage -ge $scoringConfig.scoringThresholds.fair.min) {
            $cat.status = 'fair'
        } else {
            $cat.status = 'needs-improvement'
        }
    }
    
    # Overall assessment using config thresholds
    $overallPercentage = if ($assessment.maxScore -gt 0) { 
        [math]::Round(($assessment.overallScore / $assessment.maxScore) * 100, 0) 
    } else { 
        0 
    }
    $assessment.overallPercentage = $overallPercentage
    
    # Set overall status and message from config
    if ($overallPercentage -ge $scoringConfig.scoringThresholds.excellent.min) {
        $assessment.overallStatus = 'excellent'
        $assessment.overallMessage = $scoringConfig.scoringThresholds.excellent.message
    } elseif ($overallPercentage -ge $scoringConfig.scoringThresholds.good.min) {
        $assessment.overallStatus = 'good'
        $assessment.overallMessage = $scoringConfig.scoringThresholds.good.message
    } elseif ($overallPercentage -ge $scoringConfig.scoringThresholds.fair.min) {
        $assessment.overallStatus = 'fair'
        $assessment.overallMessage = $scoringConfig.scoringThresholds.fair.message
    } else {
        $assessment.overallStatus = 'needs-improvement'
        $assessment.overallMessage = $scoringConfig.scoringThresholds.'needs-improvement'.message
    }
    
    Write-Host "  ✅ Assessment complete: $overallPercentage% ($($assessment.overallStatus))" -ForegroundColor Green
    
    return $assessment
}
