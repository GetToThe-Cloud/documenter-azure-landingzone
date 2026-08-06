// Global state
let inventoryData = null;
let isAuthenticated = false;
let wafConfig = null;
const APP_VERSION = "1.0.0";

// Escape untrusted values before inserting into HTML (XSS protection)
function escapeHtml(value) {
    if (value === null || value === undefined) return '';
    return String(value)
        .replace(/&/g, '&amp;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;')
        .replace(/"/g, '&quot;')
        .replace(/'/g, '&#39;');
}
const esc = escapeHtml;

// Headers required by the server's CSRF guard on state-changing endpoints
const CSRF_HEADERS = { 'X-Requested-With': 'XMLHttpRequest' };

// Initialize on page load
document.addEventListener('DOMContentLoaded', () => {
    console.log(`🏢 Azure Landing Zone Inventory v${APP_VERSION}`);
    loadWAFConfig();
    checkAuthStatus();
});

// Check authentication status
async function checkAuthStatus() {
    try {
        const response = await fetch('/api/auth/status');
        const data = await response.json();
        
        isAuthenticated = data.authenticated;
        updateAuthUI(data);
        
        if (isAuthenticated) {
            loadInventory();
        } else {
            showAuthRequired();
            // Automatically request Azure login
            await requestAzureLogin();
        }
    } catch (error) {
        console.error('Error checking auth status:', error);
        showAuthRequired();
    }
}

// Update authentication UI
function updateAuthUI(data) {
    const authStatus = document.getElementById('authStatus');
    
    if (data.authenticated && data.context) {
        authStatus.className = 'auth-status authenticated';
        authStatus.innerHTML = `
            ✓ Authenticated as <strong>${esc(data.context.account)}</strong><br>
            Tenant: ${esc(data.context.tenant)}
        `;
    } else {
        authStatus.className = 'auth-status not-authenticated';
        authStatus.innerHTML = '⚠️ Not authenticated with Azure. Initiating login...';
    }
}

// Show authentication required screen
function showAuthRequired() {
    document.getElementById('authRequired').style.display = 'flex';
    document.querySelectorAll('.content-section').forEach(section => {
        if (section.id !== 'authRequired') {
            section.style.display = 'none';
        }
    });
}

// Request Azure login (with rate limiting to prevent multiple simultaneous requests)
let loginInProgress = false;
async function requestAzureLogin() {
    if (loginInProgress) {
        console.log('Login already in progress, skipping duplicate request');
        return;
    }
    
    loginInProgress = true;
    const authStatus = document.getElementById('authStatus');
    
    try {
        authStatus.innerHTML = '🔐 Requesting Azure login... Please check your browser or terminal for authentication instructions.';
        
        const response = await fetch('/api/auth/login', { method: 'POST', headers: CSRF_HEADERS });
        const data = await response.json();
        
        if (data.success) {
            let message = '✓ Authentication successful!';
            
            // Check management group access
            if (data.managementGroupsAccessible === false) {
                message += '<br>⚠️ Warning: Management Groups not accessible. You may need "Management Group Reader" role.';
            } else if (data.managementGroupCount !== undefined) {
                message += ` (${esc(data.managementGroupCount)} management groups found)`;
            }
            message += '<br>Loading data...';
            
            authStatus.innerHTML = message;
            
            // Reload after brief delay to show message
            setTimeout(() => location.reload(), 1500);
        } else {
            authStatus.className = 'auth-status not-authenticated';
            authStatus.innerHTML = `⚠️ Authentication required. ${esc(data.message || 'Please sign in to Azure.')}`;
        }
    } catch (error) {
        console.error('Error requesting Azure login:', error);
        authStatus.className = 'auth-status not-authenticated';
        authStatus.innerHTML = '⚠️ Authentication request failed. Please check the server console or click the button below to retry.';
    } finally {
        loginInProgress = false;
    }
}

// Authenticate with Azure (manual trigger)
async function authenticateAzure() {
    await requestAzureLogin();
}

// Load inventory data
async function loadInventory() {
    try {
        showLoading();
        showProgress();
        updateProgress(0, 'Starting inventory collection...');
        
        // Trigger the collection (server starts it in background)
        const startResponse = await fetch('/api/inventory/data');
        const startData = await startResponse.json();
        
        if (startResponse.status === 401) {
            hideProgress();
            showAuthRequired();
            return;
        }
        
        if (startData.error) {
            hideProgress();
            alert('Error loading inventory: ' + startData.error);
            return;
        }
        
        // If data was already cached (no collection needed), use it directly
        if (!startData.collecting && !startData.error) {
            inventoryData = startData;
            updateProgress(100, 'Complete!');
            console.log(`📊 Inventory loaded - Data version: ${inventoryData.version || 'unknown'}, App version: ${APP_VERSION}`);
            updateLastUpdate();
            updateVersionInfo();
            populateUI();
            hideAuthRequired();
            setTimeout(() => hideProgress(), 500);
            return;
        }
        
        // Poll for real progress from the server
        await pollProgress();
        
        // Collection complete — fetch the full data
        updateProgress(97, 'Loading inventory data...');
        const dataResponse = await fetch('/api/inventory/data');
        inventoryData = await dataResponse.json();
        
        if (inventoryData.error) {
            hideProgress();
            alert('Error loading inventory: ' + inventoryData.error);
            return;
        }
        
        // If we still get a "collecting" response, poll a bit more
        if (inventoryData.collecting) {
            await pollProgress();
            const retryResponse = await fetch('/api/inventory/data');
            inventoryData = await retryResponse.json();
        }
        
        updateProgress(100, 'Complete!');
        
        console.log(`📊 Inventory loaded - Data version: ${inventoryData.version || 'unknown'}, App version: ${APP_VERSION}`);
        updateLastUpdate();
        updateVersionInfo();
        populateUI();
        hideAuthRequired();
        
        setTimeout(() => hideProgress(), 500);
    } catch (error) {
        hideProgress();
        console.error('Error loading inventory:', error);
        alert('Failed to load inventory: ' + error.message);
    }
}

// Poll the /api/progress endpoint until collection completes
function pollProgress() {
    return new Promise((resolve) => {
        const interval = setInterval(async () => {
            try {
                const res = await fetch('/api/progress');
                const progress = await res.json();
                
                updateProgress(
                    progress.percentage || 0, 
                    progress.status || 'Collecting...'
                );
                
                if (progress.completed) {
                    clearInterval(interval);
                    resolve();
                }
            } catch (e) {
                // Server busy or error, keep polling
            }
        }, 800);
    });
}

// Refresh inventory
async function refreshInventory() {
    const btn = document.getElementById('refreshBtn');
    btn.disabled = true;
    btn.innerHTML = '<span class="icon">⏳</span> Refreshing...';
    
    try {
        showProgress();
        updateProgress(0, 'Starting refresh...');
        
        // Tell server to clear cache and start new collection
        const refreshRes = await fetch('/api/inventory/refresh', { method: 'POST', headers: CSRF_HEADERS });
        const refreshData = await refreshRes.json();
        
        if (!refreshData.success && !refreshData.collecting) {
            throw new Error(refreshData.error || refreshData.message || 'Refresh failed');
        }
        
        // Poll progress until complete
        await pollProgress();
        
        // Fetch the fresh data
        updateProgress(97, 'Loading inventory data...');
        const dataResponse = await fetch('/api/inventory/data');
        inventoryData = await dataResponse.json();
        
        if (inventoryData.error) {
            throw new Error(inventoryData.error);
        }
        
        updateProgress(100, 'Complete!');
        updateLastUpdate();
        updateVersionInfo();
        populateUI();
        
        setTimeout(() => hideProgress(), 500);
        
        btn.innerHTML = '<span class="icon">✓</span> Refreshed!';
        setTimeout(() => {
            btn.innerHTML = '<span class="icon">🔄</span> Refresh';
            btn.disabled = false;
        }, 2000);
    } catch (error) {
        hideProgress();
        console.error('Error refreshing inventory:', error);
        btn.innerHTML = '<span class="icon">🔄</span> Refresh';
        btn.disabled = false;
    }
}

// Update last update timestamp
function updateLastUpdate() {
    if (inventoryData && inventoryData.collectionTime) {
        const date = new Date(inventoryData.collectionTime);
        document.getElementById('lastUpdate').textContent = 
            `Last updated: ${date.toLocaleString()}`;
    }
}

// Update version information
function updateVersionInfo() {
    const versionElement = document.getElementById('versionInfo');
    if (versionElement) {
        const dataVersion = inventoryData?.version || 'unknown';
        versionElement.textContent = `v${APP_VERSION} (data: v${dataVersion})`;
    }
}

// Show loading state
function showLoading() {
    document.querySelectorAll('.content-section tbody').forEach(tbody => {
        tbody.innerHTML = '<tr><td colspan="10" class="loading">Loading</td></tr>';
    });
}

// Progress bar functions
function showProgress() {
    const overlay = document.getElementById('progressOverlay');
    if (overlay) {
        overlay.style.display = 'flex';
        updateProgress(0, 'Initializing...');
    }
}

function hideProgress() {
    const overlay = document.getElementById('progressOverlay');
    if (overlay) {
        setTimeout(() => {
            overlay.style.display = 'none';
        }, 300);
    }
}

function updateProgress(percentage, status) {
    const fill = document.getElementById('progressBarFill');
    const percentageEl = document.getElementById('progressPercentage');
    const statusEl = document.getElementById('progressStatus');
    
    if (fill) fill.style.width = percentage + '%';
    if (percentageEl) percentageEl.textContent = Math.round(percentage) + '%';
    if (statusEl) statusEl.textContent = status;
}

// Hide authentication required screen
function hideAuthRequired() {
    document.getElementById('authRequired').style.display = 'none';
}

// Populate UI with inventory data
function populateUI() {
    if (!inventoryData) return;
    
    // Update explanations
    if (inventoryData.explanations) {
        document.getElementById('overviewExplanation').textContent = 
            inventoryData.explanations.overview || 'No description available';
        document.getElementById('managementGroupsExplanation').textContent = 
            inventoryData.explanations.managementGroups || 'No description available';
        document.getElementById('subscriptionsExplanation').textContent = 
            inventoryData.explanations.subscriptions || 'No description available';
        document.getElementById('policiesExplanation').textContent = 
            inventoryData.explanations.policies || 'No description available';
        document.getElementById('roleAssignmentsExplanation').textContent = 
            inventoryData.explanations.roleAssignments || 'No description available';
        document.getElementById('networkingExplanation').textContent = 
            inventoryData.explanations.networking || 'No description available';
        document.getElementById('governanceExplanation').textContent = 
            inventoryData.explanations.governance || 'No description available';
    }
    
    // Update summary cards
    const summary = inventoryData.summary || {};
    document.getElementById('totalManagementGroups').textContent = summary.totalManagementGroups || 0;
    document.getElementById('totalSubscriptions').textContent = summary.totalSubscriptions || 0;
    document.getElementById('totalPolicyDefinitions').textContent = summary.totalPolicyDefinitions || 0;
    document.getElementById('totalPolicyInitiatives').textContent = summary.totalPolicyInitiatives || 0;
    document.getElementById('totalPolicyAssignments').textContent = summary.totalPolicyAssignments || 0;
    document.getElementById('totalRoleAssignments').textContent = summary.totalRoleAssignments || 0;
    document.getElementById('totalVNets').textContent = summary.totalVNets || 0;
    document.getElementById('totalPeerings').textContent = summary.totalPeerings || 0;
    document.getElementById('totalVirtualWans').textContent = summary.totalVirtualWans || 0;
    document.getElementById('totalPrivateDnsZones').textContent = summary.totalPrivateDnsZones || 0;
    document.getElementById('totalPrivateEndpoints').textContent = summary.totalPrivateEndpoints || 0;
    document.getElementById('totalVMs').textContent = summary.totalVMs || 0;
    document.getElementById('totalBudgets').textContent = summary.totalBudgets || 0;
    document.getElementById('totalLocks').textContent = summary.totalLocks || 0;
    
    // Populate best practices assessment
    populateBestPractices();
    
    // Populate tables
    populateManagementGroups();
    populateSubscriptions();
    populatePolicies();
    populateRoleAssignments();
    populateNetworking();
    populateVirtualMachines();
    populateGovernance();
    createNetworkDiagram();
}

// Populate Management Groups table
function populateManagementGroups() {
    const tbody = document.getElementById('managementgroupsTableBody');
    const mgs = inventoryData.managementGroups || [];
    
    if (mgs.length === 0) {
        tbody.innerHTML = '<tr><td colspan="5">No management groups found</td></tr>';
        return;
    }
    
    tbody.innerHTML = mgs.map(mg => `
        <tr>
            <td><strong>${esc(mg.displayName || 'N/A')}</strong></td>
            <td><code>${esc(mg.name || 'N/A')}</code></td>
            <td>${esc(mg.parentName || 'N/A')}</td>
            <td>${mg.children ? mg.children.length : 0}</td>
            <td>${esc(mg.type || 'N/A')}</td>
        </tr>
    `).join('');
}

// Populate Subscriptions table
function populateSubscriptions() {
    const tbody = document.getElementById('subscriptionsTableBody');
    const subs = inventoryData.subscriptions || [];
    
    if (subs.length === 0) {
        tbody.innerHTML = '<tr><td colspan="4">No subscriptions found</td></tr>';
        return;
    }
    
    tbody.innerHTML = subs.map(sub => `
        <tr>
            <td><strong>${esc(sub.name || 'N/A')}</strong></td>
            <td><code>${esc(sub.subscriptionId || 'N/A')}</code></td>
            <td><span class="badge ${sub.state === 'Enabled' ? 'badge-success' : 'badge-warning'}">${esc(sub.state || 'Unknown')}</span></td>
            <td>${formatTags(sub.tags)}</td>
        </tr>
    `).join('');
}

// Populate Policies tables
function populatePolicies() {
    const policies = inventoryData.policies || {};
    
    // Policy Definitions
    const defTbody = document.getElementById('policyDefinitionsTableBody');
    const defs = policies.definitions || [];
    
    if (defs.length === 0) {
        defTbody.innerHTML = '<tr><td colspan="4">No policy definitions found</td></tr>';
    } else {
        defTbody.innerHTML = defs.map(policy => {
            const displayName = policy.displayName || policy.name || 'Unnamed Policy';
            const policyType = policy.policyType || 'Unknown';
            const mode = policy.mode || 'All';
            const description = policy.description || 'No description available';
            
            return `
                <tr>
                    <td><strong>${esc(displayName)}</strong></td>
                    <td><span class="badge ${policyType === 'Custom' ? 'badge-primary' : 'badge-secondary'}">${esc(policyType)}</span></td>
                    <td>${esc(mode)}</td>
                    <td>${esc(truncate(description, 100))}</td>
                </tr>
            `;
        }).join('');
    }
    
    // Policy Initiatives
    const initTbody = document.getElementById('policyInitiativesTableBody');
    const inits = policies.initiatives || [];
    
    if (inits.length === 0) {
        initTbody.innerHTML = '<tr><td colspan="4">No policy initiatives found</td></tr>';
    } else {
        initTbody.innerHTML = inits.map(initiative => {
            const displayName = initiative.displayName || initiative.name || 'Unnamed Initiative';
            const policyType = initiative.policyType || 'Unknown';
            const policyCount = initiative.policyDefinitions ? initiative.policyDefinitions.length : 0;
            const description = initiative.description || 'No description available';
            
            return `
                <tr>
                    <td><strong>${esc(displayName)}</strong></td>
                    <td><span class="badge ${policyType === 'Custom' ? 'badge-primary' : 'badge-secondary'}">${esc(policyType)}</span></td>
                    <td>${policyCount}</td>
                    <td>${esc(truncate(description, 100))}</td>
                </tr>
            `;
        }).join('');
    }
    
    // Policy Assignments
    const assignTbody = document.getElementById('policyAssignmentsTableBody');
    const assigns = policies.assignments || [];
    
    if (assigns.length === 0) {
        assignTbody.innerHTML = '<tr><td colspan="4">No policy assignments found</td></tr>';
    } else {
        assignTbody.innerHTML = assigns.map(assignment => {
            const displayName = assignment.displayName || assignment.name || 'Unnamed Assignment';
            const enforcementMode = assignment.enforcementMode || 'Default';
            const scope = assignment.scope || 'Unknown scope';
            const description = assignment.description || `Policy assignment: ${assignment.policyName || 'Unknown'}`;
            
            return `
                <tr>
                    <td><strong>${esc(displayName)}</strong></td>
                    <td><span class="badge ${enforcementMode === 'Default' ? 'badge-success' : 'badge-warning'}">${esc(enforcementMode)}</span></td>
                    <td><small title="${esc(scope)}">${esc(truncate(scope, 80))}</small></td>
                    <td>${esc(truncate(description, 80))}</td>
                </tr>
            `;
        }).join('');
    }
}

// Populate Role Assignments table
function populateRoleAssignments() {
    const tbody = document.getElementById('roleassignmentsTableBody');
    const roles = inventoryData.roleAssignments || [];
    
    if (roles.length === 0) {
        tbody.innerHTML = '<tr><td colspan="4">No role assignments found</td></tr>';
        return;
    }
    
    tbody.innerHTML = roles.map(role => `
        <tr>
            <td><strong>${esc(role.displayName || role.signInName || 'N/A')}</strong></td>
            <td>${esc(role.roleDefinitionName || 'N/A')}</td>
            <td><small title="${esc(role.scope || 'N/A')}">${esc(truncate(role.scope, 80) || 'N/A')}</small></td>
            <td>${esc(role.objectType || 'N/A')}</td>
        </tr>
    `).join('');
}

// Populate Networking tables
function populateNetworking() {
    const networking = inventoryData.networking || {};
    
    // Virtual Networks
    const vnetsTbody = document.getElementById('vnetsTableBody');
    const vnets = networking.vnets || [];
    
    if (vnets.length === 0) {
        vnetsTbody.innerHTML = '<tr><td colspan="6">No virtual networks found</td></tr>';
    } else {
        vnetsTbody.innerHTML = vnets.map(vnet => `
            <tr>
                <td><strong>${esc(vnet.name || 'N/A')}</strong></td>
                <td>${esc(vnet.resourceGroup || 'N/A')}</td>
                <td>${esc(vnet.location || 'N/A')}</td>
                <td><code>${esc(vnet.addressSpace ? vnet.addressSpace.join(', ') : 'N/A')}</code></td>
                <td>${vnet.subnets ? vnet.subnets.length : 0} subnets</td>
                <td><small>${esc(vnet.subscription || 'N/A')}</small></td>
            </tr>
        `).join('');
    }
    
    // VNet Peerings
    const peerTbody = document.getElementById('peeringsTableBody');
    const peerings = networking.peerings || [];
    
    if (peerings.length === 0) {
        peerTbody.innerHTML = '<tr><td colspan="9">No VNet peerings found</td></tr>';
    } else {
        peerTbody.innerHTML = peerings.map((peer, idx) => `
            <tr onclick="showResourceDetails('peering', ${idx})" data-type="peering" data-index="${idx}">
                <td><strong>${esc(peer.name || 'N/A')}</strong></td>
                <td>${esc(peer.sourceVNet || 'N/A')}</td>
                <td>${esc(peer.remoteVNet || 'N/A')}</td>
                <td><span class="status-badge ${peer.peeringState === 'Connected' ? 'status-connected' : 'status-disconnected'}">${esc(peer.peeringState || 'Unknown')}</span></td>
                <td>${peer.allowVirtualNetworkAccess ? '✓' : '✗'}</td>
                <td>${peer.allowForwardedTraffic ? '✓' : '✗'}</td>
                <td>${peer.allowGatewayTransit ? '✓' : '✗'}</td>
                <td>${peer.useRemoteGateways ? '✓' : '✗'}</td>
                <td>${esc(peer.provisioningState || 'N/A')}</td>
            </tr>
        `).join('');
    }
    
    // VPN Gateways
    const vpnTbody = document.getElementById('vpnGatewaysTableBody');
    const vpns = networking.vpnGateways || [];
    
    if (vpns.length === 0) {
        vpnTbody.innerHTML = '<tr><td colspan="6">No VPN gateways found</td></tr>';
    } else {
        vpnTbody.innerHTML = vpns.map(vpn => `
            <tr>
                <td><strong>${esc(vpn.name || 'N/A')}</strong></td>
                <td>${esc(vpn.resourceGroup || 'N/A')}</td>
                <td>${esc(vpn.location || 'N/A')}</td>
                <td>${esc(vpn.gatewayType || 'N/A')}</td>
                <td>${esc(vpn.sku || 'N/A')}</td>
                <td><small>${esc(vpn.subscription || 'N/A')}</small></td>
            </tr>
        `).join('');
    }
    
    // Virtual WANs
    const vwanTbody = document.getElementById('virtualWansTableBody');
    const vwans = networking.virtualWans || [];
    
    if (vwans.length === 0) {
        vwanTbody.innerHTML = '<tr><td colspan="7">No Virtual WANs found</td></tr>';
    } else {
        vwanTbody.innerHTML = vwans.map(vwan => `
            <tr>
                <td><strong>${esc(vwan.name || 'N/A')}</strong></td>
                <td>${esc(vwan.resourceGroup || 'N/A')}</td>
                <td>${esc(vwan.location || 'N/A')}</td>
                <td>${vwan.virtualHubCount || 0} hubs</td>
                <td>${vwan.allowBranchToBranchTraffic ? '✓' : '✗'}</td>
                <td>${vwan.allowVnetToVnetTraffic ? '✓' : '✗'}</td>
                <td><small>${esc(vwan.subscription || 'N/A')}</small></td>
            </tr>
        `).join('');
    }
    
    // Firewalls
    const fwTbody = document.getElementById('firewallsTableBody');
    const noFirewallNotice = document.getElementById('noFirewallNotice');
    const firewallsTableWrapper = document.getElementById('firewallsTableWrapper');
    const firewalls = networking.firewalls || [];
    
    if (firewalls.length === 0) {
        noFirewallNotice.style.display = 'block';
        firewallsTableWrapper.style.display = 'none';
    } else {
        noFirewallNotice.style.display = 'none';
        firewallsTableWrapper.style.display = 'block';
        fwTbody.innerHTML = firewalls.map(fw => {
            let policyRulesInfo = '';
            if (fw.usingPolicy && fw.firewallPolicyName) {
                policyRulesInfo = `Policy: ${esc(fw.firewallPolicyName)}`;
            } else {
                policyRulesInfo = `Classic Rules: ${fw.totalClassicRules || 0}`;
            }
            
            const ruleCollectionsInfo = fw.usingPolicy 
                ? 'See Policy' 
                : `App: ${fw.applicationRuleCollections || 0}, Net: ${fw.networkRuleCollections || 0}, NAT: ${fw.natRuleCollections || 0}`;
            
            return `
                <tr>
                    <td><strong>${esc(fw.name || 'N/A')}</strong></td>
                    <td>${esc(fw.resourceGroup || 'N/A')}</td>
                    <td>${esc(fw.location || 'N/A')}</td>
                    <td>${esc(fw.tier || 'N/A')}</td>
                    <td>${policyRulesInfo}</td>
                    <td>${ruleCollectionsInfo}</td>
                    <td>${esc(fw.threatIntelMode || 'N/A')}</td>
                    <td><small>${esc(fw.subscription || 'N/A')}</small></td>
                </tr>
            `;
        }).join('');
    }
    
    // Firewall Policies
    const fwPolicyTbody = document.getElementById('firewallPoliciesTableBody');
    const firewallPolicies = networking.firewallPolicies || [];
    
    if (firewallPolicies.length === 0) {
        fwPolicyTbody.innerHTML = '<tr><td colspan="10">No Firewall Policies found</td></tr>';
    } else {
        fwPolicyTbody.innerHTML = firewallPolicies.map(policy => `
            <tr>
                <td><strong>${esc(policy.name || 'N/A')}</strong></td>
                <td>${esc(policy.resourceGroup || 'N/A')}</td>
                <td>${esc(policy.location || 'N/A')}</td>
                <td>${esc(policy.tier || 'N/A')}</td>
                <td><strong>${policy.totalRules || 0}</strong></td>
                <td>${policy.applicationRuleCollections || 0}</td>
                <td>${policy.networkRuleCollections || 0}</td>
                <td>${policy.natRuleCollections || 0}</td>
                <td>${esc(policy.intrusionDetection || 'Off')}</td>
                <td><small>${esc(policy.subscription || 'N/A')}</small></td>
            </tr>
        `).join('');
    }

    // Firewall Policy Rules (only shown when firewalls are present)
    const policyRulesSection = document.getElementById('firewallPolicyRulesSection');
    const policyRulesContainer = document.getElementById('firewallPolicyRulesContainer');

    if (firewalls.length === 0 || firewallPolicies.length === 0) {
        policyRulesSection.style.display = 'none';
    } else {
        policyRulesSection.style.display = 'block';

        // Build a map: policyName → policy object (for quick lookup)
        const policyMap = {};
        firewallPolicies.forEach(p => { policyMap[p.name] = p; });

        // Collect the set of policy names that are actually attached to a firewall
        const attachedPolicyNames = new Set(
            firewalls.filter(fw => fw.usingPolicy && fw.firewallPolicyName)
                     .map(fw => fw.firewallPolicyName)
        );

        // Render per-policy rule details
        const policySections = firewallPolicies
            .filter(p => attachedPolicyNames.has(p.name))
            .map(policy => {
                const groups = policy.ruleCollectionGroupDetails || [];

                if (groups.length === 0) {
                    return `
                        <div style="margin-bottom:2rem;">
                            <h4 style="margin-bottom:0.5rem;">${esc(policy.name)} <small style="font-weight:normal;color:#888;">(${esc(policy.subscription || '')})</small></h4>
                            <p style="color:#888;">No rule collection groups found for this policy.</p>
                        </div>`;
                }

                const groupsHtml = groups.map(rcg => {
                    const collectionsHtml = (rcg.ruleCollections || []).map(rc => {
                        const rules = rc.rules || [];
                        const typeLabel = rc.ruleCollectionType === 'FirewallPolicyNatRuleCollection'
                            ? 'NAT'
                            : ((rules[0] && rules[0].ruleType === 'ApplicationRule') ? 'App' : 'Network');

                        const rulesHtml = rules.length === 0
                            ? `<tr><td colspan="6" style="color:#888;">No rules defined</td></tr>`
                            : rules.map(rule => {
                                let src = [
                                    ...(rule.sourceAddresses || []),
                                    ...(rule.sourceIpGroups   || [])
                                ].join(', ') || '*';
                                let dst = '';
                                let extra = '';

                                if (rule.ruleType === 'ApplicationRule') {
                                    dst = [...(rule.targetFqdns || []), ...(rule.fqdnTags || []), ...(rule.webCategories || []), ...(rule.targetUrls || [])].join(', ') || '*';
                                    extra = (rule.protocols || []).join(', ') || 'Any';
                                } else if (rule.ruleType === 'NatRule') {
                                    dst = [...(rule.destinationAddresses || [])].join(', ') || '*';
                                    const translated = rule.translatedFqdn || rule.translatedAddress || '';
                                    extra = `→ ${translated}:${rule.translatedPort || ''}`;
                                } else {
                                    dst = [
                                        ...(rule.destinationAddresses || []),
                                        ...(rule.destinationIpGroups  || []),
                                        ...(rule.destinationFqdns     || [])
                                    ].join(', ') || '*';
                                    extra = [
                                        (rule.ipProtocols     || []).join('/'),
                                        (rule.destinationPorts|| []).join(', ')
                                    ].filter(Boolean).join(' ') || 'Any';
                                }

                                return `
                                    <tr>
                                        <td>${esc(rule.name || 'N/A')}</td>
                                        <td><span class="badge badge-info">${esc(rule.ruleType || '')}</span></td>
                                        <td><code>${esc(src)}</code></td>
                                        <td><code>${esc(dst)}</code></td>
                                        <td>${esc(extra)}</td>
                                        <td>${esc(rule.description || '')}</td>
                                    </tr>`;
                            }).join('');

                        return `
                            <div style="margin-bottom:1rem; padding-left:1rem; border-left:3px solid #e0e0e0;">
                                <div style="font-weight:600; margin-bottom:0.4rem;">
                                    ${esc(rc.name || 'Unnamed collection')}
                                    &nbsp;<span class="badge badge-info">${typeLabel}</span>
                                    &nbsp;<span style="color:#888;font-size:0.85em;">Priority: ${esc(rc.priority !== null && rc.priority !== undefined ? rc.priority : 'N/A')} &mdash; Action: ${esc(rc.action || 'N/A')}</span>
                                </div>
                                <div class="data-table-container" style="margin:0;">
                                    <table class="data-table" style="font-size:0.85em;">
                                        <thead><tr>
                                            <th>Rule Name</th><th>Type</th><th>Source</th>
                                            <th>Destination</th><th>Protocol / Port</th><th>Description</th>
                                        </tr></thead>
                                        <tbody>${rulesHtml}</tbody>
                                    </table>
                                </div>
                            </div>`;
                    }).join('');

                    return `
                        <div style="margin-bottom:1.5rem; padding:1rem; background:#fafafa; border-radius:6px; border:1px solid #e8e8e8;">
                            <div style="font-weight:700; margin-bottom:0.75rem;">
                                Rule Collection Group: ${esc(rcg.name || 'Unnamed')}
                                <span style="color:#888;font-size:0.85em; font-weight:normal;">&mdash; Priority: ${esc(rcg.priority !== null && rcg.priority !== undefined ? rcg.priority : 'N/A')}</span>
                            </div>
                            ${collectionsHtml || '<p style="color:#888;">No rule collections.</p>'}
                        </div>`;
                }).join('');

                return `
                    <div style="margin-bottom:2.5rem;">
                        <h4 style="margin-bottom:0.75rem; border-bottom:1px solid #ddd; padding-bottom:0.4rem;">
                            ${esc(policy.name)}
                            <small style="font-weight:normal; color:#888; font-size:0.8em;">&nbsp;${esc(policy.subscription || '')} &mdash; ${esc(policy.tier || '')}</small>
                        </h4>
                        ${groupsHtml}
                    </div>`;
            }).join('');

        policyRulesContainer.innerHTML = policySections ||
            '<p style="color:#888;">No rules found for the attached firewall policies.</p>';
    }

    // NSGs
    const nsgTbody = document.getElementById('nsgsTableBody');
    const nsgs = networking.networkSecurityGroups || [];
    
    if (nsgs.length === 0) {
        nsgTbody.innerHTML = '<tr><td colspan="5">No network security groups found</td></tr>';
    } else {
        nsgTbody.innerHTML = nsgs.map(nsg => `
            <tr>
                <td><strong>${esc(nsg.name || 'N/A')}</strong></td>
                <td>${esc(nsg.resourceGroup || 'N/A')}</td>
                <td>${esc(nsg.location || 'N/A')}</td>
                <td>${nsg.securityRulesCount || 0} rules</td>
                <td><small>${esc(nsg.subscription || 'N/A')}</small></td>
            </tr>
        `).join('');
    }
    
    // Private DNS Zones
    const privateDnsZonesTbody = document.getElementById('privateDnsZonesTableBody');
    const privateDnsZones = networking.privateDnsZones || [];
    
    if (privateDnsZones.length === 0) {
        privateDnsZonesTbody.innerHTML = '<tr><td colspan="6">No private DNS zones found</td></tr>';
    } else {
        privateDnsZonesTbody.innerHTML = privateDnsZones.map(zone => `
            <tr>
                <td><strong>${esc(zone.name || 'N/A')}</strong></td>
                <td>${esc(zone.resourceGroup || 'N/A')}</td>
                <td>${esc(zone.location || 'N/A')}</td>
                <td>${zone.numberOfRecordSets || 0}</td>
                <td>${zone.numberOfVirtualNetworkLinks || 0}</td>
                <td><small>${esc(zone.subscription || 'N/A')}</small></td>
            </tr>
        `).join('');
    }
    
    // Private Endpoints
    const privateEndpointsTbody = document.getElementById('privateEndpointsTableBody');
    const privateEndpoints = networking.privateEndpoints || [];
    
    if (privateEndpoints.length === 0) {
        privateEndpointsTbody.innerHTML = '<tr><td colspan="8">No private endpoints found</td></tr>';
    } else {
        privateEndpointsTbody.innerHTML = privateEndpoints.map(pe => `
            <tr>
                <td><strong>${esc(pe.name || 'N/A')}</strong></td>
                <td>${esc(pe.resourceGroup || 'N/A')}</td>
                <td>${esc(pe.location || 'N/A')}</td>
                <td>${esc(pe.vnet || 'N/A')}</td>
                <td>${esc(pe.subnet || 'N/A')}</td>
                <td><code>${esc(pe.privateIPs && pe.privateIPs.length > 0 ? pe.privateIPs.join(', ') : 'N/A')}</code></td>
                <td>${esc(pe.connectedResource || 'N/A')}</td>
                <td><small>${esc(pe.subscription || 'N/A')}</small></td>
            </tr>
        `).join('');
    }
}

// Populate Governance tables
function populateGovernance() {
    const governance = inventoryData.governance || {};
    
    // Budgets
    const budgetTbody = document.getElementById('budgetsTableBody');
    const budgets = governance.budgets || [];
    
    if (budgets.length === 0) {
        budgetTbody.innerHTML = '<tr><td colspan="5">No budgets found</td></tr>';
    } else {
        budgetTbody.innerHTML = budgets.map(budget => `
            <tr>
                <td><strong>${esc(budget.name || 'N/A')}</strong></td>
                <td>$${esc(budget.amount || 0)}</td>
                <td>${esc(budget.timeGrain || 'N/A')}</td>
                <td>$${esc(budget.currentSpend || 0)}</td>
                <td><small>${esc(budget.subscription || 'N/A')}</small></td>
            </tr>
        `).join('');
    }
    
    // Locks
    const lockTbody = document.getElementById('locksTableBody');
    const locks = governance.locks || [];
    
    if (locks.length === 0) {
        lockTbody.innerHTML = '<tr><td colspan="5">No resource locks found</td></tr>';
    } else {
        lockTbody.innerHTML = locks.map(lock => `
            <tr>
                <td><strong>${esc(lock.name || 'N/A')}</strong></td>
                <td>${esc(lock.resourceName || 'N/A')}</td>
                <td><span class="badge ${lock.level === 'CanNotDelete' ? 'badge-danger' : 'badge-warning'}">${esc(lock.level || 'N/A')}</span></td>
                <td>${esc(lock.notes || 'No notes')}</td>
                <td><small>${esc(lock.subscription || 'N/A')}</small></td>
            </tr>
        `).join('');
    }
    
    // Tags
    const tagsContainer = document.getElementById('tagsContent');
    const tags = governance.tags || {};
    
    if (Object.keys(tags).length === 0) {
        tagsContainer.innerHTML = '<p>No common tags found</p>';
    } else {
        tagsContainer.innerHTML = Object.keys(tags).map(key => `
            <div class="tag-group">
                <div class="tag-key">${esc(key)}</div>
                <div class="tag-values">
                    ${tags[key].map(value => `<span class="tag-value">${esc(value)}</span>`).join('')}
                </div>
            </div>
        `).join('');
    }
}

// Populate Best Practices Assessment
function populateBestPractices() {
    const bp = inventoryData.bestPractices;
    
    if (!bp) {
        return;
    }
    
    // Show the section
    document.getElementById('bestPracticesSection').style.display = 'block';
    
    // Overall score
    document.getElementById('overallScore').textContent = bp.overallPercentage + '%';
    document.getElementById('overallMessage').textContent = bp.overallMessage || '';
    
    // Category scores
    const categories = [
        'managementGroupHierarchy',
        'policyDrivenGovernance',
        'identityAndAccess',
        'networkTopology',
        'securityGovernance',
        'costManagement',
        'resourceOrganization'
    ];
    
    categories.forEach(categoryKey => {
        const cat = bp.categories[categoryKey];
        if (!cat) return;
        
        const cardElement = document.getElementById('bp-' + categoryKey);
        if (!cardElement) return;
        
        const percentage = Math.round((cat.score / cat.maxScore) * 100);
        const h3 = cardElement.querySelector('h3');
        const statusElement = cardElement.querySelector('.bp-status');
        
        if (h3) {
            h3.textContent = percentage + '%';
        }
        
        if (statusElement) {
            let statusText = '';
            let statusClass = '';
            
            switch(cat.status) {
                case 'excellent':
                    statusText = '✓ Excellent';
                    statusClass = 'bp-status-excellent';
                    break;
                case 'good':
                    statusText = '✓ Good';
                    statusClass = 'bp-status-good';
                    break;
                case 'fair':
                    statusText = '⚠ Fair';
                    statusClass = 'bp-status-fair';
                    break;
                case 'needs-improvement':
                    statusText = '✗ Needs Work';
                    statusClass = 'bp-status-needs-improvement';
                    break;
            }
            
            statusElement.textContent = statusText;
            statusElement.className = 'bp-status ' + statusClass;
        }
    });
    
    // Recommendations
    if (bp.recommendations && bp.recommendations.length > 0) {
        document.getElementById('bpRecommendations').style.display = 'block';
        const list = document.getElementById('recommendationsList');
        list.innerHTML = bp.recommendations.map(rec => `<li>${esc(rec)}</li>`).join('');
    } else {
        document.getElementById('bpRecommendations').style.display = 'none';
    }
}

// Show specific section
function showSection(sectionId) {
    // Update active nav link
    document.querySelectorAll('.nav-link').forEach(link => {
        link.classList.remove('active');
        if (link.getAttribute('data-section') === sectionId) {
            link.classList.add('active');
        }
    });
    
    // Show selected section
    document.querySelectorAll('.content-section').forEach(section => {
        section.classList.remove('active');
        if (section.id === sectionId) {
            section.classList.add('active');
        }
    });
}

// Export raw inventory data to JSON file
function exportToJSON() {
    if (!inventoryData) {
        alert('No inventory data available. Please load or refresh the inventory first.');
        return;
    }
    
    const btn = document.getElementById('exportJsonBtn');
    btn.disabled = true;
    btn.innerHTML = '<span class="icon">⏳</span> Exporting...';
    
    try {
        // Filter to include only resources and their details (no assessments or summaries)
        const resourcesOnlyData = {
            timestamp: inventoryData.timestamp,
            collectedBy: inventoryData.collectedBy,
            tenant: inventoryData.tenant,
            resources: {
                managementGroups: inventoryData.managementGroups || [],
                subscriptions: inventoryData.subscriptions || [],
                policies: {
                    definitions: inventoryData.policyDefinitions || [],
                    initiatives: inventoryData.policyInitiatives || [],
                    assignments: inventoryData.policyAssignments || []
                },
                roleAssignments: inventoryData.roleAssignments || [],
                networking: {
                    virtualNetworks: inventoryData.networking?.virtualNetworks || [],
                    peerings: inventoryData.networking?.peerings || [],
                    virtualWans: inventoryData.networking?.virtualWans || [],
                    vpnGateways: inventoryData.networking?.vpnGateways || [],
                    expressRouteCircuits: inventoryData.networking?.expressRouteCircuits || [],
                    firewalls: inventoryData.networking?.firewalls || [],
                    firewallPolicies: inventoryData.networking?.firewallPolicies || [],
                    networkSecurityGroups: inventoryData.networking?.networkSecurityGroups || [],
                    privateDnsZones: inventoryData.networking?.privateDnsZones || [],
                    privateEndpoints: inventoryData.networking?.privateEndpoints || []
                },
                virtualMachines: inventoryData.virtualMachines || [],
                governance: {
                    budgets: inventoryData.governance?.budgets || [],
                    locks: inventoryData.governance?.locks || [],
                    tags: inventoryData.governance?.tags || {}
                }
            },
            metadata: {
                totalResources: {
                    managementGroups: (inventoryData.managementGroups || []).length,
                    subscriptions: (inventoryData.subscriptions || []).length,
                    policyDefinitions: (inventoryData.policyDefinitions || []).length,
                    policyInitiatives: (inventoryData.policyInitiatives || []).length,
                    policyAssignments: (inventoryData.policyAssignments || []).length,
                    roleAssignments: (inventoryData.roleAssignments || []).length,
                    virtualNetworks: (inventoryData.networking?.virtualNetworks || []).length,
                    peerings: (inventoryData.networking?.peerings || []).length,
                    virtualMachines: (inventoryData.virtualMachines || []).length,
                    budgets: (inventoryData.governance?.budgets || []).length,
                    locks: (inventoryData.governance?.locks || []).length
                },
                exportedAt: new Date().toISOString(),
                exportVersion: '1.0.0'
            }
        };
        
        // Create formatted JSON string
        const jsonString = JSON.stringify(resourcesOnlyData, null, 2);
        
        // Create filename with timestamp
        const timestamp = inventoryData.timestamp 
            ? new Date(inventoryData.timestamp).toISOString().replace(/[:.]/g, '-').slice(0, -5)
            : new Date().toISOString().replace(/[:.]/g, '-').slice(0, -5);
        const filename = `azure-resources-export-${timestamp}.json`;
        
        // Create blob and download
        const blob = new Blob([jsonString], { type: 'application/json' });
        const url = URL.createObjectURL(blob);
        const link = document.createElement('a');
        link.href = url;
        link.download = filename;
        document.body.appendChild(link);
        link.click();
        document.body.removeChild(link);
        URL.revokeObjectURL(url);
        
        // Show success message
        btn.innerHTML = '<span class="icon">✓</span> Exported!';
        setTimeout(() => {
            btn.innerHTML = '<span class="icon">💾</span> Export JSON';
            btn.disabled = false;
        }, 2000);
        
        console.log(`✅ Resources exported to ${filename}`);
        console.log(`📊 Exported ${resourcesOnlyData.metadata.totalResources.managementGroups} management groups, ${resourcesOnlyData.metadata.totalResources.subscriptions} subscriptions, ${resourcesOnlyData.metadata.totalResources.virtualMachines} VMs, and more...`);
    } catch (error) {
        console.error('Error exporting JSON:', error);
        alert('Failed to export JSON. See console for details.');
        btn.innerHTML = '<span class="icon">💾</span> Export JSON';
        btn.disabled = false;
    }
}

// Export to PDF with comprehensive details and WAF assessment
async function exportToPDF() {
    const btn = document.getElementById('exportBtn');
    btn.disabled = true;
    btn.innerHTML = '<span class="icon">⏳</span> Generating PDF...';
    
    try {
        const { jsPDF } = window.jspdf;
        const pdf = new jsPDF('p', 'mm', 'a4');
        
        let yPos = 20;
        const lineHeight = 6;
        const pageHeight = 280;
        const margin = 20;
        const maxWidth = 170;
        
        // Helper function to add text with word wrap
        function addText(text, fontSize = 10, isBold = false, color = [0, 0, 0]) {
            pdf.setFontSize(fontSize);
            pdf.setFont(undefined, isBold ? 'bold' : 'normal');
            pdf.setTextColor(...color);
            
            const lines = pdf.splitTextToSize(text, maxWidth);
            lines.forEach(line => {
                if (yPos > pageHeight) {
                    pdf.addPage();
                    yPos = 20;
                }
                pdf.text(line, margin, yPos);
                yPos += lineHeight;
            });
            pdf.setTextColor(0, 0, 0);
        }
        
        function addSection(title, text) {
            if (yPos > pageHeight - 30) {
                pdf.addPage();
                yPos = 20;
            }
            yPos += 5;
            addText(title, 14, true, [0, 120, 212]);
            yPos += 2;
            addText(text, 10, false);
            yPos += 5;
        }
        
        function addSubSection(title) {
            if (yPos > pageHeight - 20) {
                pdf.addPage();
                yPos = 20;
            }
            yPos += 3;
            addText(title, 11, true, [0, 120, 212]);
            yPos += 2;
        }
        
        function addBullet(text, indent = 0) {
            if (yPos > pageHeight - 10) {
                pdf.addPage();
                yPos = 20;
            }
            
            // Replace Unicode symbols with PDF-safe alternatives
            const cleanText = text
                .replace(/✓/g, '[+]')
                .replace(/✗/g, '[-]')
                .replace(/⚠/g, '[!]')
                .replace(/●/g, '*')
                .replace(/•/g, '-');
            
            const bulletMargin = margin + indent;
            pdf.text('-', bulletMargin, yPos);
            const lines = pdf.splitTextToSize(cleanText, maxWidth - indent - 5);
            lines.forEach((line, idx) => {
                pdf.text(line, bulletMargin + 5, yPos);
                if (idx < lines.length - 1) yPos += lineHeight;
            });
            yPos += lineHeight;
        }
        
        function getScoreColor(percentage) {
            if (percentage >= 80) return [16, 185, 129];  // Green
            if (percentage >= 60) return [245, 158, 11];  // Orange
            if (percentage >= 40) return [251, 146, 60];  // Light orange
            return [239, 68, 68];  // Red
        }
        
        function getStatusEmoji(status) {
            switch(status) {
                case 'excellent': return '[EXCELLENT]';
                case 'good': return '[GOOD]';
                case 'fair': return '[FAIR]';
                case 'needs-improvement': return '[NEEDS IMPROVEMENT]';
                default: return '[UNKNOWN]';
            }
        }
        
        // Helper function to add a table
        function addTable(headers, rows, columnWidths) {
            const tableWidth = columnWidths.reduce((a, b) => a + b, 0);
            const tableX = margin;
            
            // Check if we need a new page
            const estimatedHeight = (rows.length + 2) * 6;
            if (yPos + estimatedHeight > pageHeight) {
                pdf.addPage();
                yPos = 20;
            }
            
            // Draw header
            pdf.setFillColor(0, 120, 212);
            pdf.rect(tableX, yPos, tableWidth, 7, 'F');
            
            pdf.setTextColor(255, 255, 255);
            pdf.setFontSize(8);
            pdf.setFont(undefined, 'bold');
            
            let xOffset = tableX + 1;
            headers.forEach((header, i) => {
                pdf.text(header, xOffset, yPos + 5);
                xOffset += columnWidths[i];
            });
            yPos += 7;
            
            // Draw rows
            pdf.setTextColor(0, 0, 0);
            pdf.setFont(undefined, 'normal');
            pdf.setFontSize(7);
            
            rows.forEach((row, rowIndex) => {
                // Check if we need a new page
                if (yPos > pageHeight - 10) {
                    pdf.addPage();
                    yPos = 20;
                    
                    // Redraw header on new page
                    pdf.setFillColor(0, 120, 212);
                    pdf.rect(tableX, yPos, tableWidth, 7, 'F');
                    pdf.setTextColor(255, 255, 255);
                    pdf.setFontSize(8);
                    pdf.setFont(undefined, 'bold');
                    
                    xOffset = tableX + 1;
                    headers.forEach((header, i) => {
                        pdf.text(header, xOffset, yPos + 5);
                        xOffset += columnWidths[i];
                    });
                    yPos += 7;
                    
                    pdf.setTextColor(0, 0, 0);
                    pdf.setFont(undefined, 'normal');
                    pdf.setFontSize(7);
                }
                
                // Alternate row colors
                if (rowIndex % 2 === 0) {
                    pdf.setFillColor(245, 248, 250);
                    pdf.rect(tableX, yPos, tableWidth, 6, 'F');
                }
                
                xOffset = tableX + 1;
                row.forEach((cell, i) => {
                    const cellText = String(cell || 'N/A');
                    const maxCellWidth = columnWidths[i] - 2;
                    const truncated = pdf.splitTextToSize(cellText, maxCellWidth)[0] || '';
                    pdf.text(truncated, xOffset, yPos + 4);
                    xOffset += columnWidths[i];
                });
                yPos += 6;
            });
            
            yPos += 3;
        }
        
        // Cover Page
        pdf.setFontSize(24);
        pdf.setFont(undefined, 'bold');
        pdf.setTextColor(0, 120, 212);
        pdf.text('Azure Landing Zone', margin, yPos);
        yPos += 10;
        pdf.text('Assessment Report', margin, yPos);
        yPos += 20;
        
        pdf.setFontSize(12);
        pdf.setFont(undefined, 'normal');
        pdf.setTextColor(0, 0, 0);
        pdf.text(`Generated: ${new Date().toLocaleString()}`, margin, yPos);
        yPos += 8;
        pdf.text(`Version: ${inventoryData.version || 'unknown'} (App: ${APP_VERSION})`, margin, yPos);
        yPos += 8;
        pdf.text(`Tenant ID: ${inventoryData.tenantId || 'N/A'}`, margin, yPos);
        yPos += 8;
        
        const summary = inventoryData.summary || {};
        pdf.text(`Total Subscriptions: ${summary.totalSubscriptions || 0}`, margin, yPos);
        yPos += 6;
        pdf.text(`Total Resources Analyzed: Management Groups, Policies, Networks, Governance`, margin, yPos);
        yPos += 15;
        
        pdf.setFontSize(10);
        pdf.setFont(undefined, 'italic');
        addText('This report provides a comprehensive assessment of your Azure Landing Zone implementation against Microsoft Cloud Adoption Framework (CAF) and Well-Architected Framework (WAF) best practices.');
        yPos += 10;
        
        // === PAGE 2: Executive Summary ===
        pdf.addPage();
        yPos = 20;
        
        addText('EXECUTIVE SUMMARY', 16, true, [0, 120, 212]);
        yPos += 5;
        
        if (inventoryData.explanations) {
            addText(inventoryData.explanations.overview, 10, false);
            yPos += 5;
        }
        
        // Tenant Information
        addSubSection('Tenant Overview');
        addBullet(`Tenant ID: ${inventoryData.tenantId || 'Not available'}`);
        addBullet(`Collection Time: ${new Date(inventoryData.collectionTime).toLocaleString()}`);
        addBullet(`Management Groups: ${summary.totalManagementGroups || 0}`);
        addBullet(`Active Subscriptions: ${summary.totalSubscriptions || 0}`);
        yPos += 5;
        
        // Resource Summary
        addSubSection('Resource Inventory Summary');
        addBullet(`Policy Definitions: ${summary.totalPolicyDefinitions || 0}`);
        addBullet(`Policy Initiatives (Sets): ${summary.totalPolicyInitiatives || 0}`);
        addBullet(`Policy Assignments: ${summary.totalPolicyAssignments || 0}`);
        addBullet(`RBAC Role Assignments: ${summary.totalRoleAssignments || 0}`);
        addBullet(`Virtual Networks: ${summary.totalVNets || 0}`);
        addBullet(`VNet Peerings: ${summary.totalPeerings || 0}`);
        addBullet(`Virtual WANs: ${summary.totalVirtualWans || 0}`);
        addBullet(`VPN Gateways: ${inventoryData.networking?.vpnGateways?.length || 0}`);
        addBullet(`ExpressRoute Circuits: ${inventoryData.networking?.expressRoutes?.length || 0}`);
        addBullet(`Azure Firewalls: ${summary.totalFirewalls || 0}`);
        addBullet(`Firewall Policies: ${summary.totalFirewallPolicies || 0}`);
        addBullet(`Network Security Groups: ${inventoryData.networking?.networkSecurityGroups?.length || 0}`);
        addBullet(`Private DNS Zones: ${summary.totalPrivateDnsZones || 0}`);
        addBullet(`Private Endpoints: ${summary.totalPrivateEndpoints || 0}`);
        addBullet(`Cost Management Budgets: ${summary.totalBudgets || 0}`);
        addBullet(`Resource Locks: ${summary.totalLocks || 0}`);
        addBullet(`Virtual Machines: ${summary.totalVMs || 0}`);
        yPos += 10;
        
        // === CAF COMPLIANCE ASSESSMENT ===
        if (inventoryData.bestPractices) {
            pdf.addPage();
            yPos = 20;
            
            addText('CLOUD ADOPTION FRAMEWORK ASSESSMENT', 16, true, [0, 120, 212]);
            yPos += 5;
            
            const bp = inventoryData.bestPractices;
            const overallColor = getScoreColor(bp.overallPercentage);
            
            // Overall Score Box
            pdf.setDrawColor(180, 180, 180);
            pdf.setFillColor(245, 248, 250);
            pdf.rect(margin, yPos, maxWidth, 25, 'FD');
            yPos += 7;
            
            pdf.setFontSize(14);
            pdf.setFont(undefined, 'bold');
            pdf.setTextColor(...overallColor);
            pdf.text(`Overall CAF Compliance Score: ${bp.overallPercentage}%`, margin + 5, yPos);
            yPos += 7;
            
            pdf.setFontSize(10);
            pdf.setFont(undefined, 'normal');
            pdf.setTextColor(0, 0, 0);
            pdf.text(`${bp.overallScore} points out of ${bp.maxScore} maximum`, margin + 5, yPos);
            yPos += 7;
            
            pdf.setFont(undefined, 'italic');
            pdf.text(`Status: ${getStatusEmoji(bp.overallStatus)} ${bp.overallMessage}`, margin + 5, yPos);
            yPos += 10;
            
            pdf.setFont(undefined, 'normal');
            addText('This assessment evaluates your Azure Landing Zone against Microsoft Cloud Adoption Framework design principles covering management hierarchy, policy governance, identity management, network topology, security, cost management, and resource organization.', 9, false);
            yPos += 5;
            
            // === DETAILED CATEGORY ASSESSMENTS ===
            const categories = {
                'managementGroupHierarchy': 'Management Group Hierarchy',
                'policyDrivenGovernance': 'Policy-Driven Governance',
                'identityAndAccess': 'Identity and Access Management',
                'networkTopology': 'Network Topology and Connectivity',
                'securityGovernance': 'Security and Governance',
                'costManagement': 'Cost Management',
                'resourceOrganization': 'Resource Organization'
            };
            
            for (const [key, title] of Object.entries(categories)) {
                const cat = bp.categories[key];
                if (!cat) continue;
                
                const catPercentage = Math.round((cat.score / cat.maxScore) * 100);
                const catColor = getScoreColor(catPercentage);
                
                // Start new page if needed
                if (yPos > pageHeight - 50) {
                    pdf.addPage();
                    yPos = 20;
                }
                
                // Category Header
                pdf.setFontSize(12);
                pdf.setFont(undefined, 'bold');
                pdf.setTextColor(...catColor);
                pdf.text(`${getStatusEmoji(cat.status)} ${title}`, margin, yPos);
                yPos += 6;
                
                pdf.setFontSize(10);
                pdf.setTextColor(0, 0, 0);
                pdf.text(`Score: ${cat.score}/${cat.maxScore} (${catPercentage}%)`, margin, yPos);
                yPos += 7;
                
                // Findings
                pdf.setFont(undefined, 'normal');
                pdf.setFontSize(9);
                cat.findings.forEach(finding => {
                    if (yPos > pageHeight - 10) {
                        pdf.addPage();
                        yPos = 20;
                    }
                    
                    // Replace Unicode symbols with PDF-safe alternatives
                    let icon = '';
                    let color = [0, 0, 0];
                    
                    if (finding.startsWith('✓')) {
                        icon = '[+]';
                        color = [16, 185, 129]; // green
                    } else if (finding.startsWith('⚠')) {
                        icon = '[!]';
                        color = [245, 158, 11]; // orange
                    } else if (finding.startsWith('✗')) {
                        icon = '[-]';
                        color = [239, 68, 68]; // red
                    }
                    
                    const cleanFinding = finding.replace(/^[✓⚠✗]\s*/, '');
                    const textToDisplay = icon ? `${icon} ${cleanFinding}` : cleanFinding;
                    
                    pdf.setTextColor(...color);
                    const lines = pdf.splitTextToSize(textToDisplay, maxWidth - 4);
                    lines.forEach(line => {
                        if (yPos > pageHeight - 5) {
                            pdf.addPage();
                            yPos = 20;
                        }
                        pdf.text(line, margin + 2, yPos);
                        yPos += 5;
                    });
                    pdf.setTextColor(0, 0, 0);
                    yPos += 1;
                });
                
                yPos += 5;
            }
            
            // === RECOMMENDATIONS ===
            if (bp.recommendations && bp.recommendations.length > 0) {
                pdf.addPage();
                yPos = 20;
                
                addText('RECOMMENDED ACTIONS', 14, true, [0, 120, 212]);
                yPos += 5;
                
                addText('Based on the CAF assessment, the following actions are recommended to improve your Azure Landing Zone implementation:', 10, false);
                yPos += 5;
                
                bp.recommendations.forEach((rec, idx) => {
                    if (yPos > pageHeight - 15) {
                        pdf.addPage();
                        yPos = 20;
                    }
                    
                    pdf.setFontSize(9);
                    pdf.setFont(undefined, 'bold');
                    pdf.text(`${idx + 1}.`, margin, yPos);
                    pdf.setFont(undefined, 'normal');
                    
                    const lines = pdf.splitTextToSize(rec, maxWidth - 8);
                    lines.forEach(line => {
                        if (yPos > pageHeight - 5) {
                            pdf.addPage();
                            yPos = 20;
                        }
                        pdf.text(line, margin + 7, yPos);
                        yPos += 5;
                    });
                    yPos += 3;
                });
                
                yPos += 10;
            }
            
            // === WAF ALIGNMENT ===
            pdf.addPage();
            yPos = 20;
            
            addText('WELL-ARCHITECTED FRAMEWORK ALIGNMENT', 14, true, [0, 120, 212]);
            yPos += 5;
            
            addText('This section maps your Azure Landing Zone implementation to the five pillars of the Microsoft Azure Well-Architected Framework (WAF).', 10, false);
            yPos += 8;
            
            // Check if WAF config is loaded
            if (!wafConfig || !wafConfig.pillars) {
                addText('⚠️ WAF configuration not loaded. Using default assessment logic.', 10, true);
                yPos += 5;
            } else {
                // Evaluate each pillar dynamically
                const pillarKeys = Object.keys(wafConfig.pillars).sort((a, b) => 
                    (wafConfig.pillars[a].order || 0) - (wafConfig.pillars[b].order || 0)
                );
                
                const pillarScores = [];
                
                pillarKeys.forEach(pillarKey => {
                    const pillarConfig = wafConfig.pillars[pillarKey];
                    const evaluation = evaluateWAFPillar(pillarKey, pillarConfig, inventoryData);
                    
                    addSubSection(`Pillar ${pillarConfig.order}: ${evaluation.pillarName}`);
                    addText(`Assessment: ${evaluation.assessment}`, 9, true);
                    yPos += 2;
                    
                    // Add check results
                    evaluation.checks.forEach(check => {
                        addBullet(check.message);
                    });
                    
                    // Add pillar score
                    pdf.setTextColor(...getScoreColor(evaluation.score));
                    addText(`${evaluation.pillarName} Score: ${evaluation.score}%`, 10, true);
                    pdf.setTextColor(0, 0, 0);
                    yPos += 5;
                    
                    pillarScores.push(evaluation.score);
                });
                
                // Overall WAF Score
                const overallWAFScore = pillarScores.reduce((sum, score) => sum + score, 0) / pillarScores.length;
                pdf.setDrawColor(180, 180, 180);
                pdf.setFillColor(245, 248, 250);
                pdf.rect(margin, yPos, maxWidth, 15, 'FD');
                yPos += 5;
                
                pdf.setFontSize(12);
                pdf.setFont(undefined, 'bold');
                pdf.setTextColor(...getScoreColor(overallWAFScore));
                pdf.text(`Overall WAF Alignment Score: ${Math.round(overallWAFScore)}%`, margin + 5, yPos);
                yPos += 6;
                
                pdf.setFontSize(9);
                pdf.setFont(undefined, 'italic');
                pdf.setTextColor(0, 0, 0);
                pdf.text('Reference: Microsoft Azure Well-Architected Framework', margin + 5, yPos);
            }
            yPos += 10;
        }
        
        // === DETAILED COMPONENT SECTIONS ===
        
        // Management Groups Details
        if (inventoryData.managementGroups && inventoryData.managementGroups.length > 0) {
            pdf.addPage();
            yPos = 20;
            
            addText('MANAGEMENT GROUP HIERARCHY', 14, true, [0, 120, 212]);
            yPos += 5;
            
            if (inventoryData.explanations?.managementGroups) {
                addText(inventoryData.explanations.managementGroups, 9, false);
                yPos += 5;
            }
            
            addSubSection(`Detected Management Groups (${inventoryData.managementGroups.length})`);
            
            inventoryData.managementGroups.forEach(mg => {
                if (yPos > pageHeight - 20) {
                    pdf.addPage();
                    yPos = 20;
                }
                
                addBullet(`${mg.displayName} (${mg.name})`, 0);
                if (mg.parentId) {
                    addBullet(`Parent: ${mg.parentId.split('/').pop()}`, 5);
                }
                if (mg.children && mg.children.length > 0) {
                    addBullet(`Children: ${mg.children.length} (${mg.children.map(c => c.displayName || c.name).join(', ')})`, 5);
                }
                yPos += 2;
            });
            yPos += 5;
        }
        
        // Subscriptions Details
        if (inventoryData.subscriptions && inventoryData.subscriptions.length > 0) {
            pdf.addPage();
            yPos = 20;
            
            addText('SUBSCRIPTION INVENTORY', 14, true, [0, 120, 212]);
            yPos += 5;
            
            if (inventoryData.explanations?.subscriptions) {
                addText(inventoryData.explanations.subscriptions, 9, false);
                yPos += 5;
            }
            
            addSubSection(`Active Subscriptions (${inventoryData.subscriptions.length})`);
            
            inventoryData.subscriptions.forEach(sub => {
                if (yPos > pageHeight - 25) {
                    pdf.addPage();
                    yPos = 20;
                }
                
                pdf.setFont(undefined, 'bold');
                addBullet(`${sub.name}`, 0);
                pdf.setFont(undefined, 'normal');
                addBullet(`ID: ${sub.id}`, 5);
                addBullet(`State: ${sub.state}`, 5);
                if (sub.managementGroupId) {
                    addBullet(`Management Group: ${sub.managementGroupId.split('/').pop()}`, 5);
                }
                if (sub.tags && Object.keys(sub.tags).length > 0) {
                    const tagStr = Object.entries(sub.tags).map(([k, v]) => `${k}=${v}`).slice(0, 3).join(', ');
                    addBullet(`Tags: ${tagStr}${Object.keys(sub.tags).length > 3 ? '...' : ''}`, 5);
                }
                yPos += 2;
            });
            yPos += 5;
        }
        
        // Policy Details
        if (summary.totalPolicyAssignments > 0 || summary.totalPolicyDefinitions > 0) {
            pdf.addPage();
            yPos = 20;
            
            addText('AZURE POLICY CONFIGURATION', 14, true, [0, 120, 212]);
            yPos += 5;
            
            if (inventoryData.explanations?.policies) {
                addText(inventoryData.explanations.policies, 9, false);
                yPos += 5;
            }
            
            // Policy Summary
            addSubSection('Policy Summary');
            addBullet(`Custom Policy Definitions: ${summary.totalPolicyDefinitions || 0}`);
            addBullet(`Policy Initiatives (Sets): ${summary.totalPolicyInitiatives || 0}`);
            addBullet(`Active Assignments: ${summary.totalPolicyAssignments || 0}`);
            yPos += 5;
            
            // Sample Policy Assignments
            if (inventoryData.policies?.assignments && inventoryData.policies.assignments.length > 0) {
                addSubSection(`Policy Assignments (showing first 10)`);
                
                const assignments = inventoryData.policies.assignments.slice(0, 10);
                assignments.forEach(pa => {
                    if (yPos > pageHeight - 20) {
                        pdf.addPage();
                        yPos = 20;
                    }
                    
                    pdf.setFont(undefined, 'bold');
                    addBullet(`${pa.displayName || pa.name}`, 0);
                    pdf.setFont(undefined, 'normal');
                    addBullet(`Scope: ${pa.scope?.split('/').slice(-2).join('/')}`, 5);
                    if (pa.policyDefinitionName) {
                        addBullet(`Policy: ${pa.policyDefinitionName}`, 5);
                    }
                    yPos += 2;
                });
            }
            yPos += 5;
        }
        
        // RBAC Details
        if (summary.totalRoleAssignments > 0) {
            pdf.addPage();
            yPos = 20;
            
            addText('ROLE-BASED ACCESS CONTROL (RBAC)', 14, true, [0, 120, 212]);
            yPos += 5;
            
            if (inventoryData.explanations?.roleAssignments) {
                addText(inventoryData.explanations.roleAssignments, 9, false);
                yPos += 5;
            }
            
            addSubSection(`Total Role Assignments: ${summary.totalRoleAssignments}`);
            
            // Role distribution
            if (inventoryData.roleAssignments && inventoryData.roleAssignments.length > 0) {
                const roleCounts = {};
                inventoryData.roleAssignments.forEach(ra => {
                    const role = ra.roleDefinitionName || 'Unknown';
                    roleCounts[role] = (roleCounts[role] || 0) + 1;
                });
                
                addSubSection('Role Distribution');
                Object.entries(roleCounts).slice(0, 15).forEach(([role, count]) => {
                    addBullet(`${role}: ${count} assignment${count > 1 ? 's' : ''}`);
                });
            }
            yPos += 5;
        }
        
        // Networking Details
        if (summary.totalVNets > 0) {
            pdf.addPage();
            yPos = 20;
            
            addText('NETWORK ARCHITECTURE', 14, true, [0, 120, 212]);
            yPos += 5;
            
            if (inventoryData.explanations?.networking) {
                addText(inventoryData.explanations.networking, 9, false);
                yPos += 5;
            }
            
            // Virtual WAN Table
            if (inventoryData.networking?.virtualWans && inventoryData.networking.virtualWans.length > 0) {
                if (yPos > pageHeight - 40) {
                    pdf.addPage();
                    yPos = 20;
                }
                
                addSubSection(`Virtual WANs (${inventoryData.networking.virtualWans.length})`);
                yPos += 2;
                
                const vwanRows = inventoryData.networking.virtualWans.map(vwan => [
                    vwan.name || 'N/A',
                    vwan.location || 'N/A',
                    vwan.virtualHubCount || 0,
                    vwan.allowBranchToBranchTraffic ? 'Yes' : 'No',
                    vwan.allowVnetToVnetTraffic ? 'Yes' : 'No',
                    vwan.disableVpnEncryption ? 'Yes' : 'No',
                    vwan.subscription || 'N/A'
                ]);
                
                addTable(
                    ['Name', 'Location', 'Hubs', 'Branch-to-Branch', 'VNet-to-VNet', 'VPN Encryption', 'Subscription'],
                    vwanRows,
                    [30, 20, 12, 22, 20, 22, 34]
                );
                yPos += 5;
            }
            
            // VPN Gateways Table
            if (inventoryData.networking?.vpnGateways && inventoryData.networking.vpnGateways.length > 0) {
                if (yPos > pageHeight - 40) {
                    pdf.addPage();
                    yPos = 20;
                }
                
                addSubSection(`VPN Gateways (${inventoryData.networking.vpnGateways.length})`);
                yPos += 2;
                
                const vpnRows = inventoryData.networking.vpnGateways.map(vpn => [
                    vpn.name || 'N/A',
                    vpn.location || 'N/A',
                    vpn.gatewayType || 'N/A',
                    vpn.sku || 'N/A',
                    vpn.vpnType || 'N/A',
                    vpn.activeActive ? 'Yes' : 'No',
                    vpn.enableBgp ? 'Yes' : 'No',
                    vpn.subscription || 'N/A'
                ]);
                
                addTable(
                    ['Name', 'Location', 'Type', 'SKU', 'VPN Type', 'Active-Active', 'BGP', 'Subscription'],
                    vpnRows,
                    [28, 20, 15, 18, 18, 20, 15, 26]
                );
                yPos += 5;
            }
            
            // ExpressRoute Circuits Table
            if (inventoryData.networking?.expressRoutes && inventoryData.networking.expressRoutes.length > 0) {
                if (yPos > pageHeight - 40) {
                    pdf.addPage();
                    yPos = 20;
                }
                
                addSubSection(`ExpressRoute Circuits (${inventoryData.networking.expressRoutes.length})`);
                yPos += 2;
                
                const erRows = inventoryData.networking.expressRoutes.map(er => [
                    er.name || 'N/A',
                    er.location || 'N/A',
                    er.serviceProviderName || 'N/A',
                    er.peeringLocation || 'N/A',
                    er.bandwidthInMbps || 'N/A',
                    er.circuitProvisioningState || 'N/A',
                    er.subscription || 'N/A'
                ]);
                
                addTable(
                    ['Circuit Name', 'Location', 'Provider', 'Peering Location', 'Bandwidth', 'State', 'Subscription'],
                    erRows,
                    [30, 18, 28, 25, 18, 20, 31]
                );
                yPos += 5;
            }
            
            // Private DNS Zones Table
            if (inventoryData.networking?.privateDnsZones && inventoryData.networking.privateDnsZones.length > 0) {
                if (yPos > pageHeight - 40) {
                    pdf.addPage();
                    yPos = 20;
                }
                
                addSubSection(`Private DNS Zones (${inventoryData.networking.privateDnsZones.length})`);
                yPos += 2;
                
                const dnsRows = inventoryData.networking.privateDnsZones.map(zone => {
                    const vnetLinks = zone.virtualNetworkLinks || [];
                    const linkedVNets = vnetLinks.length > 0 
                        ? vnetLinks.map(link => link.vnetName).filter(v => v !== 'N/A').slice(0, 2).join(', ')
                        : 'None';
                    const moreLinks = vnetLinks.length > 2 ? ` +${vnetLinks.length - 2} more` : '';
                    
                    return [
                        zone.name || 'N/A',
                        zone.location || 'N/A',
                        zone.numberOfRecordSets || 0,
                        zone.numberOfVirtualNetworkLinks || 0,
                        linkedVNets + moreLinks,
                        zone.subscription || 'N/A'
                    ];
                });
                
                addTable(
                    ['Zone Name', 'Location', 'Records', 'VNet Links', 'Linked VNets', 'Subscription'],
                    dnsRows,
                    [45, 18, 15, 18, 50, 24]
                );
                yPos += 5;
            }
            
            // Network Security Groups Table
            if (inventoryData.networking?.networkSecurityGroups && inventoryData.networking.networkSecurityGroups.length > 0) {
                if (yPos > pageHeight - 40) {
                    pdf.addPage();
                    yPos = 20;
                }
                
                addSubSection(`Network Security Groups (${inventoryData.networking.networkSecurityGroups.length})`);
                yPos += 2;
                
                const nsgRows = inventoryData.networking.networkSecurityGroups.map(nsg => {
                    const subnets = nsg.associatedSubnets || [];
                    const nics = nsg.associatedNICs || [];
                    
                    let connections = '';
                    if (subnets.length > 0) {
                        connections = `Subnets: ${subnets.slice(0, 2).join(', ')}`;
                        if (subnets.length > 2) connections += ` +${subnets.length - 2}`;
                    }
                    if (nics.length > 0) {
                        if (connections) connections += ' | ';
                        connections += `NICs: ${nics.length}`;
                    }
                    if (!connections) connections = 'Not associated';
                    
                    return [
                        nsg.name || 'N/A',
                        nsg.location || 'N/A',
                        nsg.securityRulesCount || 0,
                        connections,
                        nsg.subscription || 'N/A'
                    ];
                });
                
                addTable(
                    ['NSG Name', 'Location', 'Rules', 'Connected To', 'Subscription'],
                    nsgRows,
                    [40, 20, 15, 60, 35]
                );
                yPos += 5;
            }
            
            // Private Endpoints Table
            if (inventoryData.networking?.privateEndpoints && inventoryData.networking.privateEndpoints.length > 0) {
                if (yPos > pageHeight - 40) {
                    pdf.addPage();
                    yPos = 20;
                }
                
                addSubSection(`Private Endpoints (${inventoryData.networking.privateEndpoints.length})`);
                yPos += 2;
                
                const peRows = inventoryData.networking.privateEndpoints.map(pe => {
                    const privateIPs = pe.privateIPs || [];
                    const ipAddress = privateIPs.length > 0 ? privateIPs[0] : 'N/A';
                    
                    return [
                        pe.name || 'N/A',
                        pe.connectedResource || 'N/A',
                        pe.vnet || 'N/A',
                        pe.subnet || 'N/A',
                        ipAddress,
                        pe.provisioningState || 'N/A',
                        pe.subscription || 'N/A'
                    ];
                });
                
                addTable(
                    ['Endpoint Name', 'Connected Resource', 'VNet', 'Subnet', 'Private IP', 'State', 'Subscription'],
                    peRows,
                    [30, 35, 20, 20, 18, 18, 29]
                );
                yPos += 5;
            }
            
            // VNet Table
            addSubSection(`Virtual Networks (${summary.totalVNets})`);
            yPos += 2;
            
            if (inventoryData.networking?.vnets && inventoryData.networking.vnets.length > 0) {
                const vnetRows = inventoryData.networking.vnets.map(vnet => [
                    vnet.name || 'N/A',
                    vnet.location || 'N/A',
                    vnet.addressSpace?.join(', ') || 'N/A',
                    vnet.subnets?.length || 0,
                    vnet.subscription || 'N/A'
                ]);
                
                addTable(
                    ['Name', 'Location', 'Address Space', 'Subnets', 'Subscription'],
                    vnetRows,
                    [40, 25, 50, 15, 40]
                );
            }
            yPos += 5;
            
            // VNet Peerings Table
            if (summary.totalPeerings > 0 && inventoryData.networking?.peerings) {
                addSubSection(`VNet Peerings (${summary.totalPeerings})`);
                yPos += 2;
                
                const peeringRows = inventoryData.networking.peerings.map(peer => [
                    peer.name || 'N/A',
                    peer.sourceVNet || 'N/A',
                    peer.remoteVNet || 'N/A',
                    peer.peeringState || 'Unknown',
                    peer.allowForwardedTraffic ? 'Yes' : 'No',
                    peer.subscription || 'N/A'
                ]);
                
                addTable(
                    ['Peering Name', 'Source VNet', 'Remote VNet', 'State', 'Fwd Traffic', 'Subscription'],
                    peeringRows,
                    [35, 30, 30, 20, 20, 35]
                );
                yPos += 5;
            }
            
            // Azure Firewalls Table
            if (inventoryData.networking?.firewalls && inventoryData.networking.firewalls.length > 0) {
                if (yPos > pageHeight - 30) {
                    pdf.addPage();
                    yPos = 20;
                }
                
                addSubSection(`Azure Firewalls (${inventoryData.networking.firewalls.length})`);
                yPos += 2;
                
                const firewallRows = inventoryData.networking.firewalls.map(fw => {
                    let rules = '';
                    if (fw.usingPolicy && fw.firewallPolicyName) {
                        rules = `Policy: ${fw.firewallPolicyName}`;
                    } else {
                        rules = `Classic: ${fw.totalClassicRules || 0}`;
                    }
                    
                    return [
                        fw.name || 'N/A',
                        fw.location || 'N/A',
                        fw.tier || 'N/A',
                        rules,
                        fw.threatIntelMode || 'N/A',
                        fw.subscription || 'N/A'
                    ];
                });
                
                addTable(
                    ['Name', 'Location', 'Tier', 'Rules/Policy', 'Threat Intel', 'Subscription'],
                    firewallRows,
                    [35, 20, 20, 40, 25, 30]
                );
                yPos += 5;
            }
            
            // Firewall Policies Table
            if (inventoryData.networking?.firewallPolicies && inventoryData.networking.firewallPolicies.length > 0) {
                if (yPos > pageHeight - 30) {
                    pdf.addPage();
                    yPos = 20;
                }
                
                addSubSection(`Azure Firewall Policies (${inventoryData.networking.firewallPolicies.length})`);
                yPos += 2;
                
                const policyRows = inventoryData.networking.firewallPolicies.map(policy => [
                    policy.name || 'N/A',
                    policy.location || 'N/A',
                    policy.tier || 'N/A',
                    policy.totalRules || 0,
                    `A:${policy.applicationRuleCollections || 0} N:${policy.networkRuleCollections || 0} NAT:${policy.natRuleCollections || 0}`,
                    policy.intrusionDetection || 'Off',
                    policy.subscription || 'N/A'
                ]);
                
                addTable(
                    ['Policy Name', 'Location', 'Tier', 'Total Rules', 'Collections', 'IDS', 'Subscription'],
                    policyRows,
                    [30, 20, 15, 18, 30, 15, 32]
                );
                yPos += 5;
            }
            
            // Network Security Summary
            if (inventoryData.networking?.networkSecurityGroups?.length > 0 || 
                inventoryData.networking?.privateDnsZones?.length > 0 ||
                inventoryData.networking?.privateEndpoints?.length > 0) {
                addSubSection('Additional Network Components');
                if (inventoryData.networking.networkSecurityGroups?.length > 0) {
                    addBullet(`Network Security Groups: ${inventoryData.networking.networkSecurityGroups.length}`);
                }
                if (inventoryData.networking.privateDnsZones?.length > 0) {
                    addBullet(`Private DNS Zones: ${inventoryData.networking.privateDnsZones.length}`);
                }
                if (inventoryData.networking.privateEndpoints?.length > 0) {
                    addBullet(`Private Endpoints: ${inventoryData.networking.privateEndpoints.length}`);
                }
                yPos += 5;
            }
        }
        
        // Governance Details
        if (summary.totalBudgets > 0 || summary.totalLocks > 0) {
            pdf.addPage();
            yPos = 20;
            
            addText('GOVERNANCE AND COMPLIANCE', 14, true, [0, 120, 212]);
            yPos += 5;
            
            if (inventoryData.explanations?.governance) {
                addText(inventoryData.explanations.governance, 9, false);
                yPos += 5;
            }
            
            // Cost Management
            if (summary.totalBudgets > 0) {
                addSubSection(`Cost Management Budgets (${summary.totalBudgets})`);
                
                if (inventoryData.governance?.budgets) {
                    inventoryData.governance.budgets.slice(0, 10).forEach(budget => {
                        if (yPos > pageHeight - 20) {
                            pdf.addPage();
                            yPos = 20;
                        }
                        
                        pdf.setFont(undefined, 'bold');
                        addBullet(`${budget.name}`, 0);
                        pdf.setFont(undefined, 'normal');
                        if (budget.amount) {
                            addBullet(`Amount: $${budget.amount} ${budget.timeGrain || ''}`, 5);
                        }
                        if (budget.scope) {
                            addBullet(`Scope: ${budget.scope.split('/').slice(-2).join('/')}`, 5);
                        }
                        yPos += 2;
                    });
                }
                yPos += 5;
            }
            
            // Resource Locks
            if (summary.totalLocks > 0) {
                addSubSection(`Resource Locks (${summary.totalLocks})`);
                addText('Resource locks protect critical resources from accidental deletion or modification.', 9, false);
                yPos += 3;
                
                if (inventoryData.governance?.locks) {
                    const locksByType = {};
                    inventoryData.governance.locks.forEach(lock => {
                        const type = lock.level || 'Unknown';
                        locksByType[type] = (locksByType[type] || 0) + 1;
                    });
                    
                    Object.entries(locksByType).forEach(([type, count]) => {
                        addBullet(`${type}: ${count} lock${count > 1 ? 's' : ''}`);
                    });
                }
                yPos += 5;
            }
            
            // Tagging Strategy
            if (inventoryData.governance?.tags && Object.keys(inventoryData.governance.tags).length > 0) {
                addSubSection('Resource Tagging Strategy');
                const tags = Object.keys(inventoryData.governance.tags);
                addBullet(`Unique tag keys in use: ${tags.length}`);
                addBullet(`Common tags: ${tags.slice(0, 10).join(', ')}${tags.length > 10 ? '...' : ''}`);
                yPos += 5;
            }
        }
        
        // === REFERENCES AND RESOURCES ===
        pdf.addPage();
        yPos = 20;
        
        addText('REFERENCES AND RESOURCES', 14, true, [0, 120, 212]);
        yPos += 10;
        
        pdf.setFontSize(10);
        pdf.setFont(undefined, 'bold');
        pdf.text('Microsoft Cloud Adoption Framework', margin, yPos);
        yPos += 5;
        pdf.setFont(undefined, 'normal');
        pdf.setFontSize(9);
        addText('The Cloud Adoption Framework provides proven guidance for your cloud adoption journey. This Landing Zone assessment is based on CAF design principles for enterprise-scale architecture.');
        yPos += 3;
        addText('https://learn.microsoft.com/azure/cloud-adoption-framework/');
        yPos += 8;
        
        pdf.setFontSize(10);
        pdf.setFont(undefined, 'bold');
        pdf.text('Microsoft Azure Well-Architected Framework', margin, yPos);
        yPos += 5;
        pdf.setFont(undefined, 'normal');
        pdf.setFontSize(9);
        addText('The Well-Architected Framework helps you build and operate reliable, secure, efficient, and cost-effective systems in the cloud. This report assesses your Landing Zone against WAF\'s five pillars.');
        yPos += 3;
        addText('https://learn.microsoft.com/azure/well-architected/');
        yPos += 8;
        
        pdf.setFontSize(10);
        pdf.setFont(undefined, 'bold');
        pdf.text('Azure Landing Zone Design Areas', margin, yPos);
        yPos += 5;
        pdf.setFont(undefined, 'normal');
        pdf.setFontSize(9);
        addText('Learn about the eight design areas that define an Azure Landing Zone: identity, management groups, subscriptions, network topology, security, management, governance, and platform automation.');
        yPos += 3;
        addText('https://learn.microsoft.com/azure/cloud-adoption-framework/ready/landing-zone/design-areas');
        yPos += 8;
        
        pdf.setFontSize(10);
        pdf.setFont(undefined, 'bold');
        pdf.text('Azure Architecture Center', margin, yPos);
        yPos += 5;
        pdf.setFont(undefined, 'normal');
        pdf.setFontSize(9);
        addText('Browse reference architectures, best practices, and design patterns for building solutions on Azure.');
        yPos += 3;
        addText('https://learn.microsoft.com/azure/architecture/');
        yPos += 15;
        
        // Report Footer
        pdf.setDrawColor(180, 180, 180);
        pdf.line(margin, yPos, margin + maxWidth, yPos);
        yPos += 7;
        
        pdf.setFontSize(8);
        pdf.setFont(undefined, 'italic');
        pdf.setTextColor(100, 100, 100);
        pdf.text('Azure Landing Zone Assessment Report', margin, yPos);
        pdf.text(`Generated: ${new Date().toLocaleString()}`, margin + maxWidth - 45, yPos);
        
        // Add page numbers and watermark to all pages
        const pageCount = pdf.internal.getNumberOfPages();
        for (let i = 1; i <= pageCount; i++) {
            pdf.setPage(i);
            
            // Page number
            pdf.setFontSize(8);
            pdf.setTextColor(150, 150, 150);
            pdf.text(`Page ${i} of ${pageCount}`, margin + maxWidth - 20, 290);
            
            // Watermark
            pdf.setFontSize(7);
            pdf.setTextColor(180, 180, 180);
            pdf.setFont(undefined, 'italic');
            const watermarkText = 'Created by Alex ter Neuzen for https://www.gettothe.cloud';
            const watermarkWidth = pdf.getTextWidth(watermarkText);
            pdf.text(watermarkText, (210 - watermarkWidth) / 2, 293);
        }
        
        // Save with timestamp
        const timestamp = new Date().toISOString().split('T')[0];
        pdf.save(`Azure-Landing-Zone-Assessment-${timestamp}.pdf`);
        
        btn.innerHTML = '<span class="icon">✓</span> PDF Downloaded!';
        setTimeout(() => {
            btn.innerHTML = '<span class="icon">📄</span> Export PDF';
            btn.disabled = false;
        }, 2000);
    } catch (error) {
        console.error('Error generating PDF:', error);
        alert('Failed to generate PDF: ' + error.message);
        btn.innerHTML = '<span class="icon">📄</span> Export PDF';
        btn.disabled = false;
    }
}

// Utility functions
function formatTags(tags) {
    if (!tags || Object.keys(tags).length === 0) {
        return '<em>No tags</em>';
    }
    return Object.entries(tags)
        .map(([key, value]) => `<span class="tag-value">${esc(key)}: ${esc(value)}</span>`)
        .join(' ');
}

function truncate(str, length) {
    if (!str) return '';
    return str.length > length ? str.substring(0, length) + '...' : str;
}

// Populate Virtual Machines table
function populateVirtualMachines() {
    const tbody = document.getElementById('virtualmachinesTableBody');
    const vms = (inventoryData.compute && inventoryData.compute.virtualMachines) || [];
    
    if (vms.length === 0) {
        tbody.innerHTML = '<tr><td colspan="10">No virtual machines found</td></tr>';
        return;
    }
    
    tbody.innerHTML = vms.map((vm, idx) => {
        const powerStateClass = vm.powerState === 'running' ? 'status-running' : 
                               vm.powerState === 'deallocated' ? 'status-deallocated' : 'status-stopped';
        return `
            <tr onclick="showResourceDetails('vm', ${idx})" data-type="vm" data-index="${idx}">
                <td><strong>${esc(vm.name || 'N/A')}</strong></td>
                <td>${esc(vm.vmSize || 'N/A')}</td>
                <td>${esc(vm.osType || 'N/A')}</td>
                <td><span class="status-badge ${powerStateClass}">${esc(vm.powerState || 'Unknown')}</span></td>
                <td>${vm.vnet ? esc(vm.vnet) : '<em>None</em>'}</td>
                <td>${vm.subnet ? esc(vm.subnet) : '<em>None</em>'}</td>
                <td><code>${esc(vm.privateIPs && vm.privateIPs.length > 0 ? vm.privateIPs.join(', ') : 'None')}</code></td>
                <td>${vm.publicIPs && vm.publicIPs.length > 0 ? esc(vm.publicIPs.join(', ')) : '<em>None</em>'}</td>
                <td>${esc(vm.location || 'N/A')}</td>
                <td><small>${esc(vm.subscription || 'N/A')}</small></td>
            </tr>
        `;
    }).join('');
}

// Create network diagram
let networkDiagramInstance = null;

function createNetworkDiagram() {
    if (!inventoryData) return;
    
    const container = document.getElementById('networkDiagram');
    if (!container) return;
    
    const nodes = [];
    const edges = [];
    let nodeId = 1;
    
    // Create node map for lookups
    const vnetNodeMap = {};
    const vmNodeMap = {};
    
    // Add VNets
    const vnets = (inventoryData.networking && inventoryData.networking.vnets) || [];
    vnets.forEach((vnet, idx) => {
        const id = nodeId++;
        vnetNodeMap[vnet.name] = id;
        nodes.push({
            id: id,
            label: vnet.name,
            shape: 'box',
            color: {
                background: '#667eea',
                border: '#5568d3'
            },
            font: { color: '#ffffff', size: 14, face: 'Arial' },
            title: `VNet: ${vnet.name}\\nAddress Space: ${vnet.addressSpace ? vnet.addressSpace.join(', ') : 'N/A'}\\nLocation: ${vnet.location}`,
            dataType: 'vnet',
            dataIndex: idx
        });
    });
    
    // Add VMs
    const vms = (inventoryData.compute && inventoryData.compute.virtualMachines) || [];
    vms.forEach((vm, idx) => {
        const id = nodeId++;
        vmNodeMap[vm.name] = id;
        nodes.push({
            id: id,
            label: vm.name,
            shape: 'image',
            image: 'data:image/svg+xml;base64,PHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHdpZHRoPSI0OCIgaGVpZ2h0PSI0OCIgdmlld0JveD0iMCAwIDQ4IDQ4Ij48cmVjdCB3aWR0aD0iNDgiIGhlaWdodD0iNDgiIGZpbGw9IiM0Mjg1RjQiLz48dGV4dCB4PSI1MCUiIHk9IjUwJSIgZm9udC1mYW1pbHk9IkFyaWFsIiBmb250LXNpemU9IjI0IiBmaWxsPSJ3aGl0ZSIgdGV4dC1hbmNob3I9Im1pZGRsZSIgZHk9Ii4zZW0iPvCfkrs8L3RleHQ+PC9zdmc+',
            size: 30,
            title: `VM: ${vm.name}\\nSize: ${vm.vmSize}\\nOS: ${vm.osType}\\nState: ${vm.powerState}`,
            dataType: 'vm',
            dataIndex: idx
        });
        
        // Connect VM to VNet
        if (vm.vnet && vnetNodeMap[vm.vnet]) {
            edges.push({
                from: id,
                to: vnetNodeMap[vm.vnet],
                color: { color: '#95a5a6' },
                dashes: true,
                arrows: { to: false },
                title: `Connected via ${vm.subnet || 'subnet'}`
            });
        }
    });
    
    // Add VNet Peerings
    const peerings = (inventoryData.networking && inventoryData.networking.peerings) || [];
    peerings.forEach(peer => {
        const sourceId = vnetNodeMap[peer.sourceVNet];
        const remoteId = vnetNodeMap[peer.remoteVNet];
        
        if (sourceId && remoteId) {
            edges.push({
                from: sourceId,
                to: remoteId,
                color: { 
                    color: peer.peeringState === 'Connected' ? '#27ae60' : '#e74c3c',
                    highlight: '#f39c12'
                },
                width: 3,
                arrows: { to: { enabled: true, type: 'arrow' } },
                title: `Peering: ${peer.name}\\nState: ${peer.peeringState}`,
                smooth: { type: 'curvedCW', roundness: 0.2 }
            });
        }
    });
    
    // Create network
    const data = { nodes: new vis.DataSet(nodes), edges: new vis.DataSet(edges) };
    const options = {
        physics: {
            enabled: true,
            stabilization: { iterations: 200 },
            barnesHut: {
                gravitationalConstant: -8000,
                centralGravity: 0.3,
                springLength: 200,
                springConstant: 0.04
            }
        },
        interaction: {
            hover: true,
            tooltipDelay: 200,
            navigationButtons: true,
            keyboard: true
        },
        nodes: {
            font: { size: 14 }
        },
        edges: {
            font: { size: 12, align: 'middle' },
            smooth: { type: 'continuous' }
        }
    };
    
    networkDiagramInstance = new vis.Network(container, data, options);
    
    // Add click event to nodes
    networkDiagramInstance.on('click', function(params) {
        if (params.nodes.length > 0) {
            const nodeId = params.nodes[0];
            const node = nodes.find(n => n.id === nodeId);
            if (node) {
                showResourceDetails(node.dataType, node.dataIndex);
            }
        }
    });
}

// Reset diagram view
function resetDiagram() {
    if (networkDiagramInstance) {
        networkDiagramInstance.fit();
    }
}

// Fit diagram to screen
function fitDiagram() {
    if (networkDiagramInstance) {
        networkDiagramInstance.fit({
            animation: {
                duration: 1000,
                easingFunction: 'easeInOutQuad'
            }
        });
    }
}

// Show resource details panel
function showResourceDetails(type, index) {
    const panel = document.getElementById('resourceDetails');
    const title = document.getElementById('detailsTitle');
    const content = document.getElementById('detailsContent');
    
    let resource = null;
    let html = '';
    
    if (type === 'vnet') {
        const vnets = (inventoryData.networking && inventoryData.networking.vnets) || [];
        resource = vnets[index];
        if (resource) {
            title.textContent = `VNet: ${resource.name}`;
            html = `
                <div class="detail-section">
                    <div class="detail-label">Resource Group</div>
                    <div class="detail-value">${esc(resource.resourceGroup || 'N/A')}</div>
                    
                    <div class="detail-label">Location</div>
                    <div class="detail-value">${esc(resource.location || 'N/A')}</div>
                    
                    <div class="detail-label">Address Space</div>
                    <div class="detail-value"><code>${esc(resource.addressSpace ? resource.addressSpace.join(', ') : 'N/A')}</code></div>
                    
                    <div class="detail-label">Subnets</div>
                    <div class="detail-value">
                        ${resource.subnets && resource.subnets.length > 0 ? 
                            resource.subnets.map(s => `• ${esc(s.name)}: <code>${esc(s.addressPrefix)}</code>`).join('<br>') : 
                            'No subnets'}
                    </div>
                    
                    <div class="detail-label">DNS Servers</div>
                    <div class="detail-value">${esc(resource.dnsServers && resource.dnsServers.length > 0 ? resource.dnsServers.join(', ') : 'Default (Azure provided)')}</div>
                    
                    <div class="detail-label">Subscription</div>
                    <div class="detail-value">${esc(resource.subscription || 'N/A')}</div>
                </div>
                
                <div class="detail-section">
                    <div class="detail-label">Connected Resources</div>
                    <ul class="connections-list">
            `;
            
            // Find connected VMs
            const vms = (inventoryData.compute && inventoryData.compute.virtualMachines) || [];
            const connectedVMs = vms.filter(vm => vm.vnet === resource.name);
            connectedVMs.forEach(vm => {
                html += `<li onclick="showResourceDetails('vm', ${vms.indexOf(vm)})">💻 ${esc(vm.name)} (${esc(vm.subnet || 'unknown subnet')})</li>`;
            });
            
            // Find peerings
            const peerings = (inventoryData.networking && inventoryData.networking.peerings) || [];
            const connectedPeerings = peerings.filter(p => p.sourceVNet === resource.name || p.remoteVNet === resource.name);
            connectedPeerings.forEach(peer => {
                html += `<li onclick="showResourceDetails('peering', ${peerings.indexOf(peer)})">🔗 Peering to ${esc(peer.sourceVNet === resource.name ? peer.remoteVNet : peer.sourceVNet)}</li>`;
            });
            
            if (connectedVMs.length === 0 && connectedPeerings.length === 0) {
                html += '<li>No connections found</li>';
            }
            
            html += '</ul></div>';
        }
    } else if (type === 'vm') {
        // Use modal for VM details
        showVMDetailsModal(index);
        return;
    } else if (type === 'peering') {
        const peerings = (inventoryData.networking && inventoryData.networking.peerings) || [];
        resource = peerings[index];
        if (resource) {
            title.textContent = `Peering: ${resource.name}`;
            html = `
                <div class="detail-section">
                    <div class="detail-label">Source VNet</div>
                    <div class="detail-value">${esc(resource.sourceVNet || 'N/A')}</div>
                    
                    <div class="detail-label">Remote VNet</div>
                    <div class="detail-value">${esc(resource.remoteVNet || 'N/A')}</div>
                    
                    <div class="detail-label">Peering State</div>
                    <div class="detail-value"><span class="status-badge status-${resource.peeringState === 'Connected' ? 'connected' : 'disconnected'}">${esc(resource.peeringState || 'Unknown')}</span></div>
                    
                    <div class="detail-label">Provisioning State</div>
                    <div class="detail-value">${esc(resource.provisioningState || 'N/A')}</div>
                    
                    <div class="detail-label">Allow Virtual Network Access</div>
                    <div class="detail-value">${resource.allowVirtualNetworkAccess ? '✓ Yes' : '✗ No'}</div>
                    
                    <div class="detail-label">Allow Forwarded Traffic</div>
                    <div class="detail-value">${resource.allowForwardedTraffic ? '✓ Yes' : '✗ No'}</div>
                    
                    <div class="detail-label">Allow Gateway Transit</div>
                    <div class="detail-value">${resource.allowGatewayTransit ? '✓ Yes' : '✗ No'}</div>
                    
                    <div class="detail-label">Use Remote Gateways</div>
                    <div class="detail-value">${resource.useRemoteGateways ? '✓ Yes' : '✗ No'}</div>
                    
                    <div class="detail-label">Remote Address Space</div>
                    <div class="detail-value"><code>${esc(resource.remoteAddressSpace ? resource.remoteAddressSpace.join(', ') : 'N/A')}</code></div>
                    
                    <div class="detail-label">Resource Group</div>
                    <div class="detail-value">${esc(resource.sourceResourceGroup || 'N/A')}</div>
                    
                    <div class="detail-label">Subscription</div>
                    <div class="detail-value">${esc(resource.subscription || 'N/A')}</div>
                </div>
                
                <div class="detail-section">
                    <div class="detail-label">Connected VNets</div>
                    <ul class="connections-list">
            `;
            
            const vnets = (inventoryData.networking && inventoryData.networking.vnets) || [];
            const sourceIdx = vnets.findIndex(v => v.name === resource.sourceVNet);
            const remoteIdx = vnets.findIndex(v => v.name === resource.remoteVNet);
            
            if (sourceIdx >= 0) {
                html += `<li onclick="showResourceDetails('vnet', ${sourceIdx})">🌐 ${esc(resource.sourceVNet)} (Source)</li>`;
            }
            if (remoteIdx >= 0) {
                html += `<li onclick="showResourceDetails('vnet', ${remoteIdx})">🌐 ${esc(resource.remoteVNet)} (Remote)</li>`;
            }
            
            html += '</ul></div>';
        }
    }
    
    content.innerHTML = html;
    panel.style.display = 'block';
}

// Close resource details panel
function closeDetails() {
    document.getElementById('resourceDetails').style.display = 'none';
}

// Show VM details in modal
function showVMDetailsModal(index) {
    const vms = (inventoryData.compute && inventoryData.compute.virtualMachines) || [];
    const vm = vms[index];
    
    if (!vm) return;
    
    const modal = document.getElementById('vmDetailsModal');
    const title = document.getElementById('vmModalTitle');
    const body = document.getElementById('vmModalBody');
    
    title.textContent = `Virtual Machine: ${vm.name || 'Unknown'}`;
    
    let html = `
        <div class="vm-details-grid">
            <div class="detail-card">
                <h3>💻 Basic Information</h3>
                <div class="detail-row">
                    <span class="detail-label">Name:</span>
                    <span class="detail-value"><strong>${esc(vm.name || 'N/A')}</strong></span>
                </div>
                <div class="detail-row">
                    <span class="detail-label">Resource Group:</span>
                    <span class="detail-value">${esc(vm.resourceGroup || 'N/A')}</span>
                </div>
                <div class="detail-row">
                    <span class="detail-label">VM Size:</span>
                    <span class="detail-value"><code>${esc(vm.vmSize || 'N/A')}</code></span>
                </div>
                <div class="detail-row">
                    <span class="detail-label">Operating System:</span>
                    <span class="detail-value">${esc(vm.osType || 'N/A')}</span>
                </div>
                <div class="detail-row">
                    <span class="detail-label">Power State:</span>
                    <span class="detail-value">
                        <span class="status-badge status-${esc(vm.powerState || 'unknown')}">${esc(vm.powerState || 'Unknown')}</span>
                    </span>
                </div>
                <div class="detail-row">
                    <span class="detail-label">Location:</span>
                    <span class="detail-value">${esc(vm.location || 'N/A')}</span>
                </div>
                <div class="detail-row">
                    <span class="detail-label">Subscription:</span>
                    <span class="detail-value"><small>${esc(vm.subscription || 'N/A')}</small></span>
                </div>
            </div>
            
            <div class="detail-card">
                <h3>💾 Storage</h3>
                <div class="detail-row">
                    <span class="detail-label">OS Disk Size:</span>
                    <span class="detail-value">${vm.osDiskSizeGB || 0} GB</span>
                </div>
                <div class="detail-row">
                    <span class="detail-label">Data Disks:</span>
                    <span class="detail-value">${vm.dataDisksCount || 0} disk(s)</span>
                </div>
                <div class="detail-row">
                    <span class="detail-label">Availability Set:</span>
                    <span class="detail-value">${vm.availabilitySet ? esc(vm.availabilitySet) : '<em>None</em>'}</span>
                </div>
            </div>
            
            <div class="detail-card">
                <h3>🌐 Networking</h3>
                <div class="detail-row">
                    <span class="detail-label">Virtual Network:</span>
                    <span class="detail-value">${vm.vnet ? esc(vm.vnet) : '<em>None</em>'}</span>
                </div>
                <div class="detail-row">
                    <span class="detail-label">Subnet:</span>
                    <span class="detail-value">${vm.subnet ? esc(vm.subnet) : '<em>None</em>'}</span>
                </div>
                <div class="detail-row">
                    <span class="detail-label">Private IP(s):</span>
                    <span class="detail-value"><code>${esc(vm.privateIPs && vm.privateIPs.length > 0 ? vm.privateIPs.join(', ') : 'None')}</code></span>
                </div>
                <div class="detail-row">
                    <span class="detail-label">Public IP(s):</span>
                    <span class="detail-value">${vm.publicIPs && vm.publicIPs.length > 0 ? esc(vm.publicIPs.join(', ')) : '<em>None</em>'}</span>
                </div>
                <div class="detail-row">
                    <span class="detail-label">Network Interfaces:</span>
                    <span class="detail-value"><small>${esc(vm.networkInterfaces && vm.networkInterfaces.length > 0 ? vm.networkInterfaces.join(', ') : 'None')}</small></span>
                </div>
            </div>
    `;
    
    // Tags section
    if (vm.tags && Object.keys(vm.tags).length > 0) {
        html += `
            <div class="detail-card detail-card-full">
                <h3>🏷️ Tags</h3>
                <div class="tags-grid">
        `;
        
        for (const [key, value] of Object.entries(vm.tags)) {
            html += `
                <div class="tag-item">
                    <span class="tag-key">${esc(key)}:</span>
                    <span class="tag-value">${value ? esc(value) : '<em>empty</em>'}</span>
                </div>
            `;
        }
        
        html += `
                </div>
            </div>
        `;
    } else {
        html += `
            <div class="detail-card detail-card-full">
                <h3>🏷️ Tags</h3>
                <p style="color: #999; font-style: italic;">No tags assigned to this virtual machine</p>
            </div>
        `;
    }
    
    html += `</div>`;
    
    body.innerHTML = html;
    modal.style.display = 'block';
    
    // Close modal when clicking outside
    modal.onclick = function(event) {
        if (event.target === modal) {
            closeVMModal();
        }
    };
}

// Close VM details modal
function closeVMModal() {
    const modal = document.getElementById('vmDetailsModal');
    modal.style.display = 'none';
}

// Load WAF configuration at startup
async function loadWAFConfig() {
    try {
        const response = await fetch('waf-config.json');
        if (!response.ok) {
            console.warn('WAF configuration file not found, will use fallback scoring');
            return;
        }
        
        wafConfig = await response.json();
        console.log('✓ WAF configuration loaded successfully');
    } catch (error) {
        console.error('Error loading WAF configuration:', error);
    }
}

// --- Safe WAF condition evaluation (no eval) --------------------------------
// Grammar: <token> <op> <token> joined by AND / OR (AND binds tighter than OR).
// Tokens are metric names, numbers, or true/false. Operators: >= <= == != > <

function resolveConditionToken(token, metrics) {
    token = token.trim();
    if (Object.prototype.hasOwnProperty.call(metrics, token)) {
        const value = metrics[token];
        return (value === null || value === undefined) ? 0 : value;
    }
    if (token === 'true') return true;
    if (token === 'false') return false;
    const num = Number(token);
    if (token !== '' && !Number.isNaN(num)) return num;
    throw new Error(`Unknown token '${token}' in WAF condition`);
}

function evaluateComparison(expression, metrics) {
    const match = expression.match(/^\s*([\w.]+)\s*(>=|<=|==|!=|>|<)\s*([\w.]+)\s*$/);
    if (match) {
        const left = resolveConditionToken(match[1], metrics);
        const right = resolveConditionToken(match[3], metrics);
        switch (match[2]) {
            case '>=': return Number(left) >= Number(right);
            case '<=': return Number(left) <= Number(right);
            case '==': return left === right || Number(left) === Number(right);
            case '!=': return !(left === right || Number(left) === Number(right));
            case '>':  return Number(left) > Number(right);
            case '<':  return Number(left) < Number(right);
        }
    }
    // Bare token — treat as a boolean metric
    return Boolean(resolveConditionToken(expression, metrics));
}

// Evaluate a single WAF check condition
function evaluateWAFCondition(condition, metrics) {
    try {
        return condition.split(/\bOR\b/i).some(orPart =>
            orPart.split(/\bAND\b/i).every(andPart => evaluateComparison(andPart, metrics))
        );
    } catch (error) {
        console.error('Error evaluating WAF condition:', condition, error);
        return false;
    }
}

// Evaluate a WAF pillar and return results
function evaluateWAFPillar(pillarKey, pillarData, inventoryData) {
    const summary = inventoryData.summary || {};
    const networking = inventoryData.networking || {};
    const governance = inventoryData.governance || {};
    
    // Build metrics object
    const metrics = {
        // Boolean flags
        hasMultipleVNets: summary.totalVNets >= 2,
        hasVNetPeering: summary.totalPeerings > 0,
        hasLocks: summary.totalLocks > 0,
        hasVpnGateway: (networking.vpnGateways?.length || 0) > 0,
        hasExpressRoute: (networking.expressRoutes?.length || 0) > 0,
        hasPolicyAssignments: summary.totalPolicyAssignments >= 5,
        hasRBAC: summary.totalRoleAssignments >= 10,
        hasNSGs: (networking.networkSecurityGroups?.length || 0) > 0,
        hasFirewall: (networking.firewalls?.length || 0) > 0,
        hasBudgets: summary.totalBudgets >= 3,
        hasTags: (governance.tags && Object.keys(governance.tags).length >= 5),
        hasPolicies: summary.totalPolicyAssignments > 0,
        hasMgHierarchy: summary.totalManagementGroups >= 3,
        hasMultiSub: summary.totalSubscriptions >= 3,
        hasDiagnostics: (governance.diagnosticSettings?.length || 0) > 0,
        
        // Counts
        policyAssignmentCount: summary.totalPolicyAssignments || 0,
        roleAssignmentCount: summary.totalRoleAssignments || 0,
        nsgCount: networking.networkSecurityGroups?.length || 0,
        budgetCount: summary.totalBudgets || 0,
        mgCount: summary.totalManagementGroups || 0
    };
    
    const results = [];
    let totalWeight = 0;
    let passedWeight = 0;
    
    pillarData.checks.forEach(check => {
        const passed = evaluateWAFCondition(check.condition, metrics);
        totalWeight += check.weight;
        if (passed) passedWeight += check.weight;
        
        // Replace placeholders in messages with actual values
        let message = passed ? check.passMessage : check.failMessage;
        message = message.replace(/{(\w+)}/g, (match, key) => metrics[key] || '0');
        
        results.push({
            id: check.id,
            name: check.name,
            passed: passed,
            message: message
        });
    });
    
    const score = totalWeight > 0 ? (passedWeight / totalWeight) * 100 : 0;
    
    return {
        pillarName: pillarData.name,
        description: pillarData.description,
        assessment: pillarData.assessment,
        checks: results,
        score: Math.round(score)
    };
}

// Load and display scoring configuration
async function loadScoringConfiguration() {
    try {
        const response = await fetch('scoring-config.json');
        if (!response.ok) {
            throw new Error('Failed to load scoring configuration');
        }
        
        const config = await response.json();
        displayScoringConfiguration(config);
    } catch (error) {
        console.error('Error loading scoring configuration:', error);
        document.getElementById('scoringRulesContainer').innerHTML = `
            <div class="info-banner" style="background-color: #fee; border-color: #faa;">
                <strong>⚠️ Error Loading Configuration</strong>
                <p>Could not load the scoring configuration file. Please ensure scoring-config.json exists in the application directory.</p>
            </div>
        `;
    }
}

// Display scoring configuration in the UI
function displayScoringConfiguration(config) {
    // Display version information
    document.getElementById('configVersion').textContent = config.version || 'N/A';
    document.getElementById('configLastUpdated').textContent = config.lastUpdated || 'N/A';
    
    // Calculate totals
    const categories = Object.keys(config.categories || {});
    let totalRules = 0;
    categories.forEach(key => {
        const cat = config.categories[key];
        totalRules += (cat.rules || []).length;
    });
    
    document.getElementById('configTotalCategories').textContent = categories.length;
    document.getElementById('configTotalRules').textContent = totalRules;
    
    // Display categories and rules
    const container = document.getElementById('scoringRulesContainer');
    let html = '';
    
    categories.forEach(categoryKey => {
        const category = config.categories[categoryKey];
        const categoryMaxScore = category.maxScore || 0;
        
        html += `
            <div class="scoring-category" style="margin-bottom: 30px; border: 1px solid #e0e0e0; border-radius: 8px; padding: 20px; background: #fafafa;">
                <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 15px;">
                    <h4 style="margin: 0; color: #0078d4;">${esc(category.name)}</h4>
                    <span style="background: #0078d4; color: white; padding: 4px 12px; border-radius: 12px; font-weight: bold;">
                        Max Score: ${categoryMaxScore}
                    </span>
                </div>
                <p style="color: #666; margin-bottom: 15px; font-style: italic;">${esc(category.description)}</p>
                
                <div class="rules-list" style="margin-left: 10px;">
        `;
        
        (category.rules || []).forEach((rule, index) => {
            const hasPartialPoints = rule.partialPoints && rule.partialPoints.points > 0;
            
            html += `
                <div class="rule-item" style="margin-bottom: 20px; padding: 15px; background: white; border-left: 4px solid #0078d4; border-radius: 4px;">
                    <div style="display: flex; justify-content: space-between; align-items: start; margin-bottom: 8px;">
                        <div style="flex: 1;">
                            <strong style="color: #333;">${esc(rule.id)}: ${esc(rule.name)}</strong>
                            <p style="margin: 5px 0 0 0; color: #666; font-size: 14px;">${esc(rule.description)}</p>
                        </div>
                        <span style="background: #10b981; color: white; padding: 4px 10px; border-radius: 8px; font-weight: bold; white-space: nowrap; margin-left: 10px;">
                            +${esc(rule.points)} pts
                        </span>
                    </div>
                    
                    <div style="background: #f0f8ff; padding: 10px; border-radius: 4px; margin-top: 10px;">
                        <strong style="color: #0078d4; font-size: 13px;">Condition:</strong>
                        <code style="display: block; margin-top: 5px; padding: 8px; background: white; border: 1px solid #ddd; border-radius: 4px; font-size: 12px; color: #d63384;">
                            ${esc(rule.condition)}
                        </code>
                    </div>
                    
                    ${hasPartialPoints ? `
                        <div style="background: #fff9e6; padding: 10px; border-radius: 4px; margin-top: 8px; border-left: 3px solid #ffc107;">
                            <strong style="color: #856404; font-size: 13px;">⚠️ Partial Points Available:</strong>
                            <p style="margin: 5px 0 5px 0; font-size: 13px; color: #666;">
                                If main condition not met, awards <strong>+${esc(rule.partialPoints.points)} pts</strong> when:
                            </p>
                            <code style="display: block; padding: 6px; background: white; border: 1px solid #ddd; border-radius: 4px; font-size: 12px; color: #d63384;">
                                ${esc(rule.partialPoints.condition)}
                            </code>
                        </div>
                    ` : ''}
                    
                    <div style="margin-top: 10px; padding: 10px; background: #fff3cd; border-left: 3px solid #ffc107; border-radius: 4px;">
                        <strong style="color: #856404; font-size: 13px;">💡 Recommendation:</strong>
                        <p style="margin: 5px 0 0 0; color: #666; font-size: 13px;">${esc(rule.recommendation)}</p>
                    </div>
                </div>
            `;
        });
        
        html += `
                </div>
            </div>
        `;
    });
    
    container.innerHTML = html;
    
    // Display thresholds
    displayScoringThresholds(config.scoringThresholds);
}

// Display scoring thresholds
function displayScoringThresholds(thresholds) {
    const container = document.getElementById('scoringThresholds');
    
    const thresholdKeys = ['excellent', 'good', 'fair', 'needs-improvement'];
    
    let html = `
        <table class="data-table">
            <thead>
                <tr>
                    <th>Status</th>
                    <th>Icon</th>
                    <th>Minimum Score (%)</th>
                    <th>Message</th>
                </tr>
            </thead>
            <tbody>
    `;
    
    thresholdKeys.forEach(key => {
        if (thresholds[key]) {
            const threshold = thresholds[key];
            const statusColor = 
                key === 'excellent' ? '#10b981' :
                key === 'good' ? '#3b82f6' :
                key === 'fair' ? '#f59e0b' :
                '#ef4444';
            
            html += `
                <tr>
                    <td><strong style="color: ${statusColor};">${esc(threshold.label)}</strong></td>
                    <td style="font-size: 20px; text-align: center;">${esc(threshold.icon)}</td>
                    <td><span style="background: ${statusColor}; color: white; padding: 4px 12px; border-radius: 8px; font-weight: bold;">≥ ${esc(threshold.min)}%</span></td>
                    <td style="color: #666;">${esc(threshold.message)}</td>
                </tr>
            `;
        }
    });
    
    html += `
            </tbody>
        </table>
    `;
    
    container.innerHTML = html;
}

// Load and display WAF configuration for the UI section
async function loadWAFConfiguration() {
    try {
        const response = await fetch('waf-config.json');
        if (!response.ok) {
            throw new Error('Failed to load WAF configuration');
        }
        
        const config = await response.json();
        displayWAFConfiguration(config);
    } catch (error) {
        console.error('Error loading WAF configuration:', error);
        document.getElementById('wafPillarsContainer').innerHTML = `
            <div class="info-banner" style="background-color: #fee; border-color: #faa;">
                <strong>⚠️ Error Loading Configuration</strong>
                <p>Could not load the WAF configuration file. Please ensure waf-config.json exists in the application directory.</p>
            </div>
        `;
    }
}

// Display WAF configuration in the UI
function displayWAFConfiguration(config) {
    // Display version information
    document.getElementById('wafConfigVersionValue').textContent = config.version || 'N/A';
    document.getElementById('wafConfigLastUpdated').textContent = config.lastUpdated || 'N/A';
    
    // Calculate totals
    const pillars = Object.keys(config.pillars || {});
    let totalChecks = 0;
    pillars.forEach(key => {
        const pillar = config.pillars[key];
        totalChecks += (pillar.checks || []).length;
    });
    
    document.getElementById('wafConfigTotalPillars').textContent = pillars.length;
    document.getElementById('wafConfigTotalChecks').textContent = totalChecks;
    
    // Display pillars and checks
    const container = document.getElementById('wafPillarsContainer');
    let html = '';
    
    // Sort pillars by order
    const sortedPillars = pillars.sort((a, b) => {
        const orderA = config.pillars[a].order || 0;
        const orderB = config.pillars[b].order || 0;
        return orderA - orderB;
    });
    
    sortedPillars.forEach(pillarKey => {
        const pillar = config.pillars[pillarKey];
        const checksCount = (pillar.checks || []).length;
        
        html += `
            <div class="scoring-category" style="margin-bottom: 30px; border: 1px solid #e0e0e0; border-radius: 8px; padding: 20px; background: #fafafa;">
                <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 15px;">
                    <div>
                        <h4 style="margin: 0; color: #0078d4; font-size: 18px;">Pillar ${esc(pillar.order)}: ${esc(pillar.name)}</h4>
                        <p style="margin: 5px 0 0 0; color: #666; font-size: 14px;">${esc(pillar.description)}</p>
                    </div>
                    <div style="text-align: right;">
                        <span style="background: #0078d4; color: white; padding: 4px 12px; border-radius: 12px; font-size: 12px; font-weight: bold;">
                            ${checksCount} Checks
                        </span>
                    </div>
                </div>
                
                <div style="background: white; border-radius: 6px; padding: 15px; margin-top: 15px;">
                    <div style="color: #666; font-size: 13px; margin-bottom: 10px;">
                        <strong>Assessment:</strong> ${esc(pillar.assessment)}
                    </div>
                    
                    <table class="data-table" style="margin-top: 10px;">
                        <thead>
                            <tr>
                                <th style="width: 100px;">Check ID</th>
                                <th>Check Name</th>
                                <th style="width: 250px;">Condition</th>
                                <th style="width: 80px; text-align: center;">Weight</th>
                            </tr>
                        </thead>
                        <tbody>
        `;
        
        (pillar.checks || []).forEach(check => {
            html += `
                <tr>
                    <td><code style="background: #f0f0f0; padding: 2px 6px; border-radius: 3px; font-size: 11px;">${esc(check.id)}</code></td>
                    <td><strong>${esc(check.name)}</strong><br><span style="color: #666; font-size: 12px;">${esc(check.description)}</span></td>
                    <td><code style="font-size: 11px; color: #d63384;">${esc(check.condition)}</code></td>
                    <td style="text-align: center;"><span style="background: #e7f3ff; padding: 4px 8px; border-radius: 8px; font-weight: bold;">${esc(check.weight)}</span></td>
                </tr>
                <tr>
                    <td colspan="4" style="background: #f9f9f9; padding: 10px; border-top: none;">
                        <div style="display: grid; grid-template-columns: 1fr 1fr; gap: 10px;">
                            <div>
                                <span style="color: #10b981; font-weight: bold;">✓ Pass:</span> 
                                <span style="color: #666; font-size: 12px;">${esc(check.passMessage)}</span>
                            </div>
                            <div>
                                <span style="color: #ef4444; font-weight: bold;">✗ Fail:</span> 
                                <span style="color: #666; font-size: 12px;">${esc(check.failMessage)}</span>
                            </div>
                        </div>
                    </td>
                </tr>
            `;
        });
        
        html += `
                        </tbody>
                    </table>
                </div>
            </div>
        `;
    });
    
    container.innerHTML = html;
}

// Initialize scoring configuration view when section is shown
document.addEventListener('DOMContentLoaded', () => {
    // Override showSection to load config when that section is viewed
    const originalShowSection = window.showSection;
    window.showSection = function(sectionId) {
        if (originalShowSection) {
            originalShowSection(sectionId);
        }
        
        // Load scoring configuration when that section is shown
        if (sectionId === 'scoringconfig') {
            loadScoringConfiguration();
            loadWAFConfiguration();
        }
    };
});

