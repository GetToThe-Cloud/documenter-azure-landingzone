#!/usr/bin/env pwsh
#Requires -Version 7.0
<#
.SYNOPSIS
    Azure Landing Zone Inventory Web Server
.DESCRIPTION
    Starts a web server that provides a live view of Azure Landing Zone inventory
    with authentication, navigation, and PDF export capabilities.
.PARAMETER Port
    Port number for the web server (default: 8080)
.NOTES
    Requires PowerShell 7.0 or higher
#>

param(
    [int]$Port = 8080
)

# Import required modules
$ErrorActionPreference = "Stop"

if (-not ('LandingZoneInventoryShutdownHandlerAsync' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Net;

public static class LandingZoneInventoryShutdownHandlerAsync
{
    private static HttpListener listener;
    private static volatile bool shutdownRequested;

    public static ConsoleCancelEventHandler Register(HttpListener value)
    {
        listener = value;
        shutdownRequested = false;
        ConsoleCancelEventHandler handler = HandleCancelKeyPress;
        Console.CancelKeyPress += handler;
        return handler;
    }

    public static void Unregister(ConsoleCancelEventHandler handler)
    {
        Console.CancelKeyPress -= handler;
        listener = null;
        shutdownRequested = false;
    }

    public static bool IsShutdownRequested()
    {
        return shutdownRequested;
    }

    private static void HandleCancelKeyPress(object sender, ConsoleCancelEventArgs eventArgs)
    {
        eventArgs.Cancel = true;
        shutdownRequested = true;
        HttpListener currentListener = listener;
        listener = null;
        if (currentListener != null && currentListener.IsListening)
        {
            currentListener.Stop();
        }
    }
}
'@
}

Write-Host "🚀 Starting Azure Landing Zone Inventory Server..." -ForegroundColor Cyan

# Check PowerShell version
if ($PSVersionTable.PSVersion.Major -lt 7) {
    Write-Host "❌ ERROR: PowerShell 7 or higher is required." -ForegroundColor Red
    Write-Host "   Current version: $($PSVersionTable.PSVersion)" -ForegroundColor Yellow
    Write-Host "   Download PowerShell 7+: https://aka.ms/powershell" -ForegroundColor Cyan
    exit 1
}

Write-Host "✓ PowerShell version: $($PSVersionTable.PSVersion)" -ForegroundColor Green

# Check and import Azure modules
Write-Host "📦 Checking required PowerShell modules..." -ForegroundColor Cyan

$requiredModules = @(
    'Az.Accounts', 
    'Az.Resources', 
    'Az.Network', 
    'Az.PolicyInsights',
    'Az.Billing'
)

function Install-RequiredModule {
    param(
        [Parameter(Mandatory=$true)]
        [string]$ModuleName
    )
    
    try {
        $installedModule = Get-Module -ListAvailable -Name $ModuleName | Sort-Object Version -Descending | Select-Object -First 1
        
        if (-not $installedModule) {
            Write-Host "   ⬇️  Installing $ModuleName from PSGallery..." -ForegroundColor Yellow
            Install-Module -Name $ModuleName -Repository PSGallery -Scope CurrentUser -Force -ErrorAction Stop
            $installedModule = Get-Module -ListAvailable -Name $ModuleName | Sort-Object Version -Descending | Select-Object -First 1
            Write-Host "   ✓ Installed $ModuleName v$($installedModule.Version)" -ForegroundColor Green
        } else {
            # Never auto-update at startup (supply-chain hardening) — only report if an update exists
            Write-Host "   ✓ $ModuleName v$($installedModule.Version)" -ForegroundColor Green
            try {
                $onlineModule = Find-Module -Name $ModuleName -Repository PSGallery -ErrorAction Stop
                if ($onlineModule.Version -gt $installedModule.Version) {
                    Write-Host "   ℹ️  Update available: v$($onlineModule.Version). Run 'Update-Module $ModuleName' to update manually." -ForegroundColor Gray
                }
            } catch {
                # No internet or gallery unreachable — nothing to report
            }
        }
        
        # Import the module
        Import-Module $ModuleName -ErrorAction Stop -Force
        return $true
    } catch {
        Write-Host "   ✗ Error with ${ModuleName}: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

$allModulesOk = $true
foreach ($module in $requiredModules) {
    if (-not (Install-RequiredModule -ModuleName $module)) {
        $allModulesOk = $false
    }
}

if (-not $allModulesOk) {
    Write-Host "❌ Not all required modules are available. Please resolve module issues and try again." -ForegroundColor Red
    exit 1
}

# Import inventory collection module
$inventoryModulePath = Join-Path $PSScriptRoot "Get-AzureLandingZoneInventory.ps1"
. $inventoryModulePath

# Check Azure connection
function Test-AzureConnection {
    try {
        $context = Get-AzContext
        if ($null -eq $context) {
            return $false
        }
        return $true
    }
    catch {
        return $false
    }
}

# Per-user application data directory (holds Azure context + progress files; never the shared temp dir)
$script:AppDataDir = Join-Path $HOME '.documenter-azure-landingzone'
if (-not (Test-Path $script:AppDataDir)) {
    New-Item -ItemType Directory -Path $script:AppDataDir -Force | Out-Null
}
if (-not $IsWindows) {
    # Restrict directory to the current user
    chmod 700 $script:AppDataDir
}

# Global state
$script:IsAuthenticated = Test-AzureConnection
$script:InventoryData = @{}
$script:LastUpdate = $null
$script:CollectionRunspace = $null
$script:CollectionPipeline = $null
$script:CollectionInProgress = $false
$script:ProgressFilePath = Join-Path $script:AppDataDir "inventory-progress.json"
$script:AzContextFilePath = Join-Path $script:AppDataDir "az-context.json"

# Save the current Azure context (contains access tokens) with user-only permissions
function Save-ServerAzContext {
    Save-AzContext -Path $script:AzContextFilePath -Force | Out-Null
    if (-not $IsWindows) {
        chmod 600 $script:AzContextFilePath
    }
    return $script:AzContextFilePath
}

Write-Host "🔐 Azure Authentication Status: $(if ($script:IsAuthenticated) { 'Connected ✓' } else { 'Not Connected ✗' })" -ForegroundColor $(if ($script:IsAuthenticated) { 'Green' } else { 'Yellow' })

# Test Management Group access if authenticated
if ($script:IsAuthenticated) {
    try {
        $ctx = Get-AzContext
        Write-Host "   📋 Context: $($ctx.Account.Id) @ Tenant: $($ctx.Tenant.Id)" -ForegroundColor Gray
        
        $testMg = @(Get-AzManagementGroup -ErrorAction Stop)
        Write-Host "   ✓ Management Groups accessible ($($testMg.Count) found)" -ForegroundColor Green
    } catch {
        Write-Host "   ⚠️  Management Groups NOT accessible: $($_.Exception.Message)" -ForegroundColor Yellow
        Write-Host "   ℹ️  You may need 'Management Group Reader' role at tenant root" -ForegroundColor Cyan
    }
}

# HTTP Listener
$listener = New-Object System.Net.HttpListener
$cancelKeyPressHandler = [LandingZoneInventoryShutdownHandlerAsync]::Register($listener)
try {
    $listener.Prefixes.Add("http://localhost:$Port/")
    $listener.Start()

    Write-Host "🌐 Server started at http://localhost:$Port" -ForegroundColor Green
    Write-Host "📊 Access the Azure Landing Zone Inventory Dashboard in your browser" -ForegroundColor Cyan
    Write-Host "Press Ctrl+C to stop the server" -ForegroundColor Gray
    Write-Host ""

    while ($listener.IsListening -and -not [LandingZoneInventoryShutdownHandlerAsync]::IsShutdownRequested()) {
        try {
            $contextTask = $listener.GetContextAsync()
            while (-not $contextTask.Wait(250)) {
                if ([LandingZoneInventoryShutdownHandlerAsync]::IsShutdownRequested() -or -not $listener.IsListening) {
                    break
                }
            }
            if ([LandingZoneInventoryShutdownHandlerAsync]::IsShutdownRequested() -or -not $listener.IsListening) {
                break
            }
            $context = $contextTask.GetAwaiter().GetResult()
        } catch [System.Net.HttpListenerException] {
            if ([LandingZoneInventoryShutdownHandlerAsync]::IsShutdownRequested() -or -not $listener.IsListening) {
                break
            }
            throw
        } catch [System.ObjectDisposedException] {
            if ([LandingZoneInventoryShutdownHandlerAsync]::IsShutdownRequested() -or -not $listener.IsListening) {
                break
            }
            throw
        } catch [System.AggregateException] {
            if ([LandingZoneInventoryShutdownHandlerAsync]::IsShutdownRequested() -or -not $listener.IsListening) {
                break
            }
            throw
        }
        $request = $context.Request
        $response = $context.Response
        
        $path = $request.Url.AbsolutePath
        $method = $request.HttpMethod
        
        Write-Host "$(Get-Date -Format 'HH:mm:ss') $method $path" -ForegroundColor Gray
        
        # Content type and response
        $content = ""
        $responseBytes = $null
        $contentType = "text/html; charset=utf-8"
        
        # CSRF guard: state-changing endpoints must be POSTed by the dashboard JS
        # (cross-origin pages cannot set the X-Requested-With header without a CORS preflight)
        if ($path -in @('/api/auth/login', '/api/inventory/refresh') -and
            ($method -ne 'POST' -or $request.Headers['X-Requested-With'] -ne 'XMLHttpRequest')) {
            $path = '/__forbidden__'
        }
        
        # Route handling
        switch -Regex ($path) {
            '^/__forbidden__$' {
                $response.StatusCode = 403
                $content = @{ error = "Forbidden: this endpoint requires a POST request from the dashboard" } | ConvertTo-Json
                $contentType = "application/json"
            }
            
            '^/$' {
                # Serve main page
                $indexPath = Join-Path $PSScriptRoot "index.html"
                if (Test-Path $indexPath) {
                    $content = Get-Content $indexPath -Raw
                } else {
                    $content = "<html><body><h1>Azure Landing Zone Inventory Server</h1><p>index.html not found</p></body></html>"
                }
            }
            
            '^/styles\.css$' {
                $cssPath = Join-Path $PSScriptRoot "styles.css"
                if (Test-Path $cssPath) {
                    $content = Get-Content $cssPath -Raw
                    $contentType = "text/css"
                }
            }
            
            '^/app\.js$' {
                $jsPath = Join-Path $PSScriptRoot "app.js"
                if (Test-Path $jsPath) {
                    $content = Get-Content $jsPath -Raw
                    $contentType = "application/javascript"
                }
            }

            '^/gettothecloud-logo\.webp$' {
                $logoPath = Join-Path $PSScriptRoot "gettothecloud-logo.webp"
                if (Test-Path $logoPath) {
                    $responseBytes = [System.IO.File]::ReadAllBytes($logoPath)
                    $contentType = "image/webp"
                } else {
                    $response.StatusCode = 404
                    $content = "Logo not found"
                }
            }
            
            '^/scoring-config\.json$' {
                $configPath = Join-Path $PSScriptRoot "scoring-config.json"
                if (Test-Path $configPath) {
                    $content = Get-Content $configPath -Raw
                    $contentType = "application/json"
                } else {
                    $content = @{
                        error = "Scoring configuration file not found"
                        message = "scoring-config.json is missing from the application directory"
                    } | ConvertTo-Json
                    $contentType = "application/json"
                }
            }
            
            '^/waf-config\.json$' {
                $configPath = Join-Path $PSScriptRoot "waf-config.json"
                if (Test-Path $configPath) {
                    $content = Get-Content $configPath -Raw
                    $contentType = "application/json"
                } else {
                    $content = @{
                        error = "WAF configuration file not found"
                        message = "waf-config.json is missing from the application directory"
                    } | ConvertTo-Json
                    $contentType = "application/json"
                }
            }
            
            '^/api/auth/status$' {
                $script:IsAuthenticated = Test-AzureConnection
                $authStatus = @{
                    authenticated = $script:IsAuthenticated
                    context = if ($script:IsAuthenticated) {
                        $ctx = Get-AzContext
                        @{
                            account = $ctx.Account.Id
                            subscription = $ctx.Subscription.Name
                            tenant = $ctx.Tenant.Id
                        }
                    } else { $null }
                }
                $content = $authStatus | ConvertTo-Json
                $contentType = "application/json"
            }
            
            '^/api/auth/login$' {
                try {
                    Connect-AzAccount -UseDeviceAuthentication | Out-Null
                    $script:IsAuthenticated = $true
                    
                    # Test management group access
                    $mgAccessible = $false
                    $mgCount = 0
                    try {
                        $testMg = @(Get-AzManagementGroup -ErrorAction Stop)
                        $mgAccessible = $true
                        $mgCount = $testMg.Count
                    } catch {
                        Write-Host "  ⚠️  Management Groups not accessible: $($_.Exception.Message)" -ForegroundColor Yellow
                    }
                    
                    $content = @{ 
                        success = $true
                        message = "Authentication successful"
                        managementGroupsAccessible = $mgAccessible
                        managementGroupCount = $mgCount
                    } | ConvertTo-Json
                } catch {
                    Write-Host "  ✗ Authentication failed: $($_.Exception.Message)" -ForegroundColor Red
                    $content = @{ success = $false; message = "Authentication failed. See the server console for details." } | ConvertTo-Json
                }
                $contentType = "application/json"
            }
            
            '^/api/inventory/data$' {
                if ($script:IsAuthenticated) {
                    if ($script:CollectionInProgress) {
                        # Collection is running in background — tell client to poll /api/progress
                        $content = @{ collecting = $true; message = "Collection in progress" } | ConvertTo-Json
                    } elseif ($script:InventoryData -and $script:InventoryData.Count -gt 0 -and $script:InventoryData.ContainsKey('version')) {
                        # Return cached data
                        $content = $script:InventoryData | ConvertTo-Json -Depth 20
                    } else {
                        # Start collection in background runspace
                        try {
                            Write-Host "  📊 Starting Azure Landing Zone inventory collection..." -ForegroundColor Cyan
                            
                            # Clear previous progress file
                            if (Test-Path $script:ProgressFilePath) { Remove-Item $script:ProgressFilePath -Force -ErrorAction SilentlyContinue }
                            
                            # Save Azure context so the background runspace can authenticate
                            $azContextPath = Save-ServerAzContext
                            
                            $script:CollectionInProgress = $true
                            $script:CollectionRunspace = [runspacefactory]::CreateRunspace()
                            $script:CollectionRunspace.Open()
                            
                            $script:CollectionPipeline = [powershell]::Create()
                            $script:CollectionPipeline.Runspace = $script:CollectionRunspace
                            
                            $inventoryScript = $inventoryModulePath
                            $script:CollectionPipeline.AddScript({
                                param($scriptPath, $ctxPath)
                                Import-Module Az.Accounts, Az.Resources, Az.Network, Az.PolicyInsights, Az.Billing -ErrorAction Stop
                                Import-AzContext -Path $ctxPath -ErrorAction Stop | Out-Null
                                # Context imported — remove the token file as soon as it is no longer needed
                                Remove-Item $ctxPath -Force -ErrorAction SilentlyContinue
                                . $scriptPath
                                $result = Get-AzureLandingZoneInventory
                                return $result
                            }).AddArgument($inventoryScript).AddArgument($azContextPath) | Out-Null
                            
                            $script:CollectionHandle = $script:CollectionPipeline.BeginInvoke()
                            
                            $content = @{ collecting = $true; message = "Collection started" } | ConvertTo-Json
                        } catch {
                            $script:CollectionInProgress = $false
                            Write-Host "  ✗ Failed to start collection: $($_.Exception.Message)" -ForegroundColor Red
                            $content = @{ error = "Failed to start inventory collection. See the server console for details." } | ConvertTo-Json
                        }
                    }
                } else {
                    $response.StatusCode = 401
                    $content = @{ error = "Not authenticated" } | ConvertTo-Json
                }
                $contentType = "application/json"
            }
            
            '^/api/progress$' {
                if ($script:CollectionInProgress -and $script:CollectionHandle) {
                    # Check if collection has completed
                    if ($script:CollectionHandle.IsCompleted) {
                        $completedStatus = 'Complete!'
                        try {
                            # Check for pipeline errors first
                            if ($script:CollectionPipeline.HadErrors) {
                                $errMsgs = $script:CollectionPipeline.Streams.Error | ForEach-Object { $_.ToString() }
                                $errText = ($errMsgs | Select-Object -First 3) -join '; '
                                Write-Host "  ⚠ Collection completed with errors: $errText" -ForegroundColor Yellow
                            }
                            $script:InventoryData = $script:CollectionPipeline.EndInvoke($script:CollectionHandle)
                            # EndInvoke returns a PSDataCollection, extract the hashtable
                            if ($script:InventoryData -is [System.Management.Automation.PSDataCollection[PSObject]]) {
                                $script:InventoryData = $script:InventoryData[0]
                            }
                            if (-not $script:InventoryData -or ($script:InventoryData -is [hashtable] -and $script:InventoryData.Count -eq 0)) {
                                throw "Collection returned empty data — Azure context may not have transferred to background process."
                            }
                            $script:LastUpdate = Get-Date
                            Write-Host "  ✓ Inventory collection complete" -ForegroundColor Green
                        } catch {
                            Write-Host "  ✗ Inventory collection error: $($_.Exception.Message)" -ForegroundColor Red
                            $script:InventoryData = @{ error = "Inventory collection failed. See the server console for details." }
                            $completedStatus = "Error: collection failed — see the server console for details"
                        } finally {
                            $script:CollectionPipeline.Dispose()
                            $script:CollectionRunspace.Close()
                            $script:CollectionRunspace.Dispose()
                            $script:CollectionInProgress = $false
                            $script:CollectionPipeline = $null
                            $script:CollectionRunspace = $null
                            $script:CollectionHandle = $null
                        }
                        $content = @{ 
                            completed = $true 
                            percentage = 100 
                            status = $completedStatus
                        } | ConvertTo-Json
                    } else {
                        # Read progress from temp file
                        $progressInfo = @{ completed = $false; percentage = 0; status = 'Starting...' }
                        if (Test-Path $script:ProgressFilePath) {
                            try {
                                $rawProgress = [System.IO.File]::ReadAllText($script:ProgressFilePath)
                                $fileProgress = $rawProgress | ConvertFrom-Json -ErrorAction SilentlyContinue
                                if ($fileProgress) {
                                    $progressInfo.percentage = $fileProgress.percentage
                                    $progressInfo.status = $fileProgress.status
                                    $progressInfo.step = $fileProgress.step
                                    $progressInfo.totalSteps = $fileProgress.totalSteps
                                }
                            } catch {
                                # File might be mid-write, use defaults
                            }
                        }
                        $content = $progressInfo | ConvertTo-Json
                    }
                } else {
                    $content = @{ 
                        completed = -not $script:CollectionInProgress
                        percentage = if ($script:InventoryData.Count -gt 0) { 100 } else { 0 }
                        status = if ($script:InventoryData.Count -gt 0) { 'Complete!' } else { 'Idle' }
                    } | ConvertTo-Json
                }
                $contentType = "application/json"
            }
            
            '^/api/inventory/refresh$' {
                if ($script:IsAuthenticated) {
                    if ($script:CollectionInProgress) {
                        $content = @{ success = $false; message = "Collection already in progress" } | ConvertTo-Json
                    } else {
                        try {
                            Write-Host "  🔄 Starting inventory refresh..." -ForegroundColor Cyan
                            
                            # Clear previous progress file
                            if (Test-Path $script:ProgressFilePath) { Remove-Item $script:ProgressFilePath -Force -ErrorAction SilentlyContinue }
                            
                            # Reset cached data so /api/inventory/data triggers new collection
                            $script:InventoryData = @{}
                            
                            # Save Azure context so the background runspace can authenticate
                            $azContextPath = Save-ServerAzContext
                            
                            $script:CollectionInProgress = $true
                            $script:CollectionRunspace = [runspacefactory]::CreateRunspace()
                            $script:CollectionRunspace.Open()
                            
                            $script:CollectionPipeline = [powershell]::Create()
                            $script:CollectionPipeline.Runspace = $script:CollectionRunspace
                            
                            $inventoryScript = $inventoryModulePath
                            $script:CollectionPipeline.AddScript({
                                param($scriptPath, $ctxPath)
                                Import-Module Az.Accounts, Az.Resources, Az.Network, Az.PolicyInsights, Az.Billing -ErrorAction Stop
                                Import-AzContext -Path $ctxPath -ErrorAction Stop | Out-Null
                                # Context imported — remove the token file as soon as it is no longer needed
                                Remove-Item $ctxPath -Force -ErrorAction SilentlyContinue
                                . $scriptPath
                                $result = Get-AzureLandingZoneInventory
                                return $result
                            }).AddArgument($inventoryScript).AddArgument($azContextPath) | Out-Null
                            
                            $script:CollectionHandle = $script:CollectionPipeline.BeginInvoke()
                            
                            $content = @{ 
                                success = $true
                                message = "Refresh started"
                                collecting = $true
                            } | ConvertTo-Json
                        } catch {
                            $script:CollectionInProgress = $false
                            Write-Host "  ✗ Failed to start refresh: $($_.Exception.Message)" -ForegroundColor Red
                            $content = @{ success = $false; error = "Failed to start refresh. See the server console for details." } | ConvertTo-Json
                        }
                    }
                } else {
                    $response.StatusCode = 401
                    $content = @{ success = $false; error = "Not authenticated" } | ConvertTo-Json
                }
                $contentType = "application/json"
            }
            
            default {
                $response.StatusCode = 404
                $content = "<html><body><h1>404 - Not Found</h1></body></html>"
            }
        }
        
        # Send response (same-origin only — deliberately no CORS headers)
        $buffer = if ($null -ne $responseBytes) {
            $responseBytes
        } else {
            [System.Text.Encoding]::UTF8.GetBytes($content)
        }
        $response.ContentLength64 = $buffer.Length
        $response.ContentType = $contentType
        $response.Headers.Add("X-Content-Type-Options", "nosniff")
        $response.OutputStream.Write($buffer, 0, $buffer.Length)
        $response.Close()
    }
}
finally {
    [LandingZoneInventoryShutdownHandlerAsync]::Unregister($cancelKeyPressHandler)
    Write-Host "`n🛑 Stopping server..." -ForegroundColor Yellow
    if ($listener.IsListening) {
        $listener.Stop()
    }
    $listener.Close()
    # Remove any leftover Azure context (token) file
    if (Test-Path $script:AzContextFilePath) {
        Remove-Item $script:AzContextFilePath -Force -ErrorAction SilentlyContinue
    }
    Write-Host "✓ Server stopped" -ForegroundColor Green
}
