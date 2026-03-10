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
    'Az.PolicyInsights'
)

function Update-RequiredModule {
    param(
        [Parameter(Mandatory=$true)]
        [string]$ModuleName
    )
    
    try {
        $installedModule = Get-Module -ListAvailable -Name $ModuleName | Sort-Object Version -Descending | Select-Object -First 1
        
        if (-not $installedModule) {
            Write-Host "   ⬇️  Installing $ModuleName..." -ForegroundColor Yellow
            Install-Module -Name $ModuleName -Force -Scope CurrentUser -AllowClobber -ErrorAction Stop
            $installedModule = Get-Module -ListAvailable -Name $ModuleName | Sort-Object Version -Descending | Select-Object -First 1
            Write-Host "   ✓ Installed $ModuleName v$($installedModule.Version)" -ForegroundColor Green
        } else {
            # Check for updates
            try {
                $onlineModule = Find-Module -Name $ModuleName -ErrorAction Stop
                
                if ($onlineModule.Version -gt $installedModule.Version) {
                    Write-Host "   ⬆️  Updating $ModuleName from v$($installedModule.Version) to v$($onlineModule.Version)..." -ForegroundColor Yellow
                    Update-Module -Name $ModuleName -Force -ErrorAction Stop
                    Write-Host "   ✓ Updated $ModuleName to v$($onlineModule.Version)" -ForegroundColor Green
                } else {
                    Write-Host "   ✓ $ModuleName v$($installedModule.Version) (latest)" -ForegroundColor Green
                }
            } catch {
                # If online check fails (e.g., no internet), just use installed version
                Write-Host "   ✓ $ModuleName v$($installedModule.Version) (online check skipped)" -ForegroundColor Gray
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
    if (-not (Update-RequiredModule -ModuleName $module)) {
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

# Global state
$script:IsAuthenticated = Test-AzureConnection
$script:InventoryData = @{}
$script:LastUpdate = $null

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
$listener.Prefixes.Add("http://localhost:$Port/")
$listener.Start()

Write-Host "🌐 Server started at http://localhost:$Port" -ForegroundColor Green
Write-Host "📊 Access the Azure Landing Zone Inventory Dashboard in your browser" -ForegroundColor Cyan
Write-Host "Press Ctrl+C to stop the server" -ForegroundColor Gray
Write-Host ""

try {
    while ($listener.IsListening) {
        $context = $listener.GetContext()
        $request = $context.Request
        $response = $context.Response
        
        $path = $request.Url.AbsolutePath
        $method = $request.HttpMethod
        
        Write-Host "$(Get-Date -Format 'HH:mm:ss') $method $path" -ForegroundColor Gray
        
        # Content type and response
        $content = ""
        $contentType = "text/html; charset=utf-8"
        
        # Route handling
        switch -Regex ($path) {
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
                    $content = @{ success = $false; message = $_.Exception.Message } | ConvertTo-Json
                }
                $contentType = "application/json"
            }
            
            '^/api/inventory/data$' {
                if ($script:IsAuthenticated) {
                    try {
                        Write-Host "  📊 Collecting Azure Landing Zone inventory..." -ForegroundColor Cyan
                        $script:InventoryData = Get-AzureLandingZoneInventory
                        $script:LastUpdate = Get-Date
                        $content = $script:InventoryData | ConvertTo-Json -Depth 20
                    } catch {
                        $content = @{ error = $_.Exception.Message } | ConvertTo-Json
                    }
                } else {
                    $response.StatusCode = 401
                    $content = @{ error = "Not authenticated" } | ConvertTo-Json
                }
                $contentType = "application/json"
            }
            
            '^/api/inventory/refresh$' {
                if ($script:IsAuthenticated) {
                    try {
                        Write-Host "  🔄 Refreshing inventory..." -ForegroundColor Cyan
                        $script:InventoryData = Get-AzureLandingZoneInventory
                        $script:LastUpdate = Get-Date
                        $content = @{ 
                            success = $true
                            lastUpdate = $script:LastUpdate.ToString('o')
                        } | ConvertTo-Json
                    } catch {
                        $content = @{ success = $false; error = $_.Exception.Message } | ConvertTo-Json
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
        
        # Send response
        $buffer = [System.Text.Encoding]::UTF8.GetBytes($content)
        $response.ContentLength64 = $buffer.Length
        $response.ContentType = $contentType
        $response.Headers.Add("Access-Control-Allow-Origin", "*")
        $response.OutputStream.Write($buffer, 0, $buffer.Length)
        $response.Close()
    }
}
finally {
    Write-Host "`n🛑 Stopping server..." -ForegroundColor Yellow
    $listener.Stop()
    $listener.Close()
    Write-Host "✓ Server stopped" -ForegroundColor Green
}
