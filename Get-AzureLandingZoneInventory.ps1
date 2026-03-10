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
$script:Version = "1.0.0"

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
    
    Write-Host "    ○ Gathering Azure Landing Zone inventory (v$script:Version)..." -ForegroundColor Gray
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
            peerings = @()
            vpnGateways = @()
            expressRoutes = @()
            virtualWans = @()
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
            totalPeerings = 0
            totalBudgets = 0
            totalLocks = 0
            totalVMs = 0
            totalPrivateDnsZones = 0
            totalPrivateEndpoints = 0
            totalVirtualWans = 0
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
        Write-Host "    ○ Collecting Management Groups..." -ForegroundColor Gray
        
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
        Write-Host "    ○ Collecting Subscriptions..." -ForegroundColor Gray
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
        Write-Host "    ○ Collecting Policy Definitions..." -ForegroundColor Gray
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
        Write-Host "    ○ Collecting Policy Initiatives..." -ForegroundColor Gray
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
        Write-Host "    ○ Collecting Policy Assignments..." -ForegroundColor Gray
        try {
            $assignments = Get-AzPolicyAssignment -ErrorAction SilentlyContinue
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
        Write-Host "    ○ Collecting Role Assignments..." -ForegroundColor Gray
        try {
            $roles = Get-AzRoleAssignment -ErrorAction SilentlyContinue
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
        Write-Host "    ○ Collecting Networking Resources..." -ForegroundColor Gray
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
                $vnets = Get-AzVirtualNetwork -ErrorAction SilentlyContinue
                foreach ($vnet in $vnets) {
                    $inventory.networking.vnets += @{
                        name = $vnet.Name
                        resourceGroup = $vnet.ResourceGroupName
                        location = $vnet.Location
                        addressSpace = $vnet.AddressSpace.AddressPrefixes
                        subnets = @($vnet.Subnets | ForEach-Object {
                            @{
                                name = $_.Name
                                addressPrefix = $_.AddressPrefix
                                serviceEndpoints = @($_.ServiceEndpoints | ForEach-Object { $_.Service })
                            }
                        })
                        dnsServers = $vnet.DhcpOptions.DnsServers
                        tags = $vnet.Tag
                        subscription = $sub.Name
                    }
                }
                $inventory.summary.totalVNets += $vnets.Count
                
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
                                # Get rule collection groups using Get-AzResource
                                $ruleCollectionGroupResources = Get-AzResource -ResourceType 'Microsoft.Network/firewallPolicies/ruleCollectionGroups' -ResourceGroupName $policy.ResourceGroupName -ErrorAction SilentlyContinue | 
                                    Where-Object { $_.ResourceId -like "*$($policy.Name)*" }
                                
                                $totalRuleCollections = 0
                                $totalRules = 0
                                $applicationRuleCollections = 0
                                $networkRuleCollections = 0
                                $natRuleCollections = 0
                                $ruleCollectionGroupCount = 0
                                
                                # Try to get detailed rule information from each rule collection group
                                foreach ($rcgResource in $ruleCollectionGroupResources) {
                                    try {
                                        $rcgName = $rcgResource.Name
                                        $rcGroup = Get-AzFirewallPolicyRuleCollectionGroup -Name $rcgName -ResourceGroupName $policy.ResourceGroupName -AzureFirewallPolicyName $policy.Name -ErrorAction SilentlyContinue
                                        
                                        if ($rcGroup) {
                                            $ruleCollectionGroupCount++
                                            
                                            if ($rcGroup.Properties.RuleCollection) {
                                                $totalRuleCollections += $rcGroup.Properties.RuleCollection.Count
                                                
                                                foreach ($rc in $rcGroup.Properties.RuleCollection) {
                                                    if ($rc.Rules) {
                                                        $ruleCount = $rc.Rules.Count
                                                        $totalRules += $ruleCount
                                                        
                                                        # Categorize by type
                                                        if ($rc.RuleCollectionType -eq 'FirewallPolicyFilterRuleCollection') {
                                                            if ($rc.Rules[0].RuleType -eq 'ApplicationRule') {
                                                                $applicationRuleCollections++
                                                            } elseif ($rc.Rules[0].RuleType -eq 'NetworkRule') {
                                                                $networkRuleCollections++
                                                            }
                                                        } elseif ($rc.RuleCollectionType -eq 'FirewallPolicyNatRuleCollection') {
                                                            $natRuleCollections++
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    } catch {
                                        # Silently continue if we can't get details for a specific rule collection group
                                    }
                                }
                                
                                # If we couldn't get rule collection groups, use the count from resources
                                if ($ruleCollectionGroupCount -eq 0 -and $ruleCollectionGroupResources) {
                                    $ruleCollectionGroupCount = $ruleCollectionGroupResources.Count
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
                
                # Virtual WANs
                try {
                    $vwanResources = Get-AzResource -ResourceType 'Microsoft.Network/virtualWans' -ErrorAction SilentlyContinue
                    foreach ($vwanResource in $vwanResources) {
                        try {
                            $vwan = Get-AzVirtualWan -ResourceGroupName $vwanResource.ResourceGroupName -Name $vwanResource.Name -ErrorAction SilentlyContinue
                            if ($vwan) {
                                # Get Virtual Hubs associated with this VWAN
                                $vHubs = Get-AzVirtualHub -ErrorAction SilentlyContinue | Where-Object { 
                                    $_.VirtualWan.Id -eq $vwan.Id 
                                }
                                
                                $hubDetails = @()
                                foreach ($hub in $vHubs) {
                                    $hubDetails += @{
                                        name = $hub.Name
                                        location = $hub.Location
                                        addressPrefix = $hub.AddressPrefix
                                        routingState = $hub.RoutingState
                                    }
                                }
                                
                                $inventory.networking.virtualWans += @{
                                    name = $vwan.Name
                                    id = $vwan.Id
                                    resourceGroup = $vwan.ResourceGroupName
                                    location = $vwan.Location
                                    type = $vwan.Type
                                    allowBranchToBranchTraffic = $vwan.AllowBranchToBranchTraffic
                                    allowVnetToVnetTraffic = $vwan.AllowVnetToVnetTraffic
                                    disableVpnEncryption = $vwan.DisableVpnEncryption
                                    virtualHubCount = $vHubs.Count
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
                
                # Network Security Groups - use Get-AzResource to find them
                try {
                    $nsgResources = Get-AzResource -ResourceType 'Microsoft.Network/networkSecurityGroups' -ErrorAction SilentlyContinue
                    foreach ($nsgResource in $nsgResources) {
                        try {
                            $nsg = Get-AzNetworkSecurityGroup -ResourceGroupName $nsgResource.ResourceGroupName -Name $nsgResource.Name -ErrorAction SilentlyContinue
                            if ($nsg) {
                                # Get associated subnets
                                $associatedSubnets = @()
                                foreach ($subnet in $nsg.Subnets) {
                                    if ($subnet.Id) {
                                        $subnetName = Split-Path $subnet.Id -Leaf
                                        $vnetName = ($subnet.Id -split '/subnets/')[0] | Split-Path -Leaf
                                        $associatedSubnets += "$vnetName/$subnetName"
                                    }
                                }
                                
                                # Get associated network interfaces
                                $associatedNICs = @()
                                foreach ($nic in $nsg.NetworkInterfaces) {
                                    if ($nic.Id) {
                                        $nicName = Split-Path $nic.Id -Leaf
                                        $associatedNICs += $nicName
                                    }
                                }
                                
                                $inventory.networking.networkSecurityGroups += @{
                                    name = $nsg.Name
                                    resourceGroup = $nsg.ResourceGroupName
                                    location = $nsg.Location
                                    securityRulesCount = $nsg.SecurityRules.Count
                                    defaultSecurityRulesCount = $nsg.DefaultSecurityRules.Count
                                    associatedSubnets = $associatedSubnets
                                    associatedNICs = $associatedNICs
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
        Write-Host "    ○ Collecting Virtual Machines..." -ForegroundColor Gray
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
        Write-Host "    ○ Collecting Governance Resources..." -ForegroundColor Gray
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
                
                # Budgets (requires Az.CostManagement module - skip if not available)
                try {
                    if (Get-Command Get-AzConsumptionBudget -ErrorAction SilentlyContinue) {
                        $budgets = Get-AzConsumptionBudget -ErrorAction SilentlyContinue
                        foreach ($budget in $budgets) {
                            $inventory.governance.budgets += @{
                                name = $budget.Name
                                amount = $budget.Amount
                                timeGrain = $budget.TimeGrain
                                timePeriod = @{
                                    startDate = $budget.TimePeriod.StartDate
                                    endDate = $budget.TimePeriod.EndDate
                                }
                                currentSpend = $budget.CurrentSpend.Amount
                                subscription = $sub.Name
                            }
                        }
                        $inventory.summary.totalBudgets += $budgets.Count
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
        Write-Host "    ○ Evaluating Cloud Adoption Framework compliance..." -ForegroundColor Gray
        $inventory.bestPractices = Get-LandingZoneBestPracticesAssessment -Inventory $inventory
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
        locks = $Inventory.summary.totalLocks ?? 0
        nsgCount = if ($Inventory.networking.networkSecurityGroups) { $Inventory.networking.networkSecurityGroups.Count } else { 0 }
        budgets = $Inventory.summary.totalBudgets ?? 0
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
                $condition = $rule.condition
                # Replace variable names with actual values
                foreach ($key in $metrics.Keys) {
                    $value = $metrics[$key]
                    # Handle different value types properly
                    if ($value -is [bool]) {
                        $value = if ($value) { '$true' } else { '$false' }
                    } elseif ($null -eq $value) {
                        $value = '0'
                    } else {
                        # Ensure numeric values are properly formatted
                        $value = $value.ToString()
                    }
                    $condition = $condition -replace "\b$key\b", $value
                }
                # Convert logical operators to PowerShell syntax
                $condition = $condition -replace '\bAND\b', '-and'
                $condition = $condition -replace '\bOR\b', '-or'
                $condition = $condition -replace '\btrue\b', '$true'
                $condition = $condition -replace '\bfalse\b', '$false'
                
                # Convert comparison operators to PowerShell syntax
                $condition = $condition -replace '>=', '-ge'
                $condition = $condition -replace '<=', '-le'
                $condition = $condition -replace '==', '-eq'
                $condition = $condition -replace '!=', '-ne'
                $condition = $condition -replace '(?<!-)>(?!=)', '-gt'  # > but not >= (already converted)
                $condition = $condition -replace '(?<!-)<(?!=)', '-lt'  # < but not <= (already converted)
                
                # Evaluate the condition
                $conditionMet = Invoke-Expression $condition
            } catch {
                Write-Warning "Failed to evaluate condition for rule $($rule.id): $($rule.condition) | Error: $($_.Exception.Message)"
                $conditionMet = $false
            }
            
            # Evaluate partial points condition if exists
            if ($rule.partialPoints -and -not $conditionMet) {
                try {
                    $partialCondition = $rule.partialPoints.condition
                    foreach ($key in $metrics.Keys) {
                        $value = $metrics[$key]
                        # Handle boolean values
                        if ($value -is [bool]) {
                            $value = if ($value) { '$true' } else { '$false' }
                        }
                        $partialCondition = $partialCondition -replace "\b$key\b", $value
                    }
                    # Convert logical operators to PowerShell syntax
                    $partialCondition = $partialCondition -replace '\bAND\b', '-and'
                    $partialCondition = $partialCondition -replace '\bOR\b', '-or'
                    $partialCondition = $partialCondition -replace '\btrue\b', '$true'
                    $partialCondition = $partialCondition -replace '\bfalse\b', '$false'
                    
                    # Convert comparison operators to PowerShell syntax
                    $partialCondition = $partialCondition -replace '>=', '-ge'
                    $partialCondition = $partialCondition -replace '<=', '-le'
                    $partialCondition = $partialCondition -replace '==', '-eq'
                    $partialCondition = $partialCondition -replace '!=', '-ne'
                    $partialCondition = $partialCondition -replace '(?<!-)>(?!=)', '-gt'
                    $partialCondition = $partialCondition -replace '(?<!-)<(?!=)', '-lt'
                    
                    $partialConditionMet = Invoke-Expression $partialCondition
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
