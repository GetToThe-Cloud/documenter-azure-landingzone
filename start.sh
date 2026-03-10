#!/bin/bash

# Azure Landing Zone Inventory Server Startup Script

echo "🚀 Starting Azure Landing Zone Inventory Server..."
echo ""

# Stop any existing instances
echo "📌 Checking for existing instances..."
pkill -f "Start-AzureLandingZoneServer.ps1" 2>/dev/null
sleep 1

# Check if PowerShell is available
if ! command -v pwsh &> /dev/null; then
    echo "❌ PowerShell (pwsh) is not installed!"
    echo "📥 Please install PowerShell: https://aka.ms/powershell"
    exit 1
fi

# Check if Azure PowerShell modules are available
echo "📦 Checking Azure PowerShell modules..."
pwsh -Command "Get-Module -ListAvailable -Name Az.Accounts" > /dev/null 2>&1

if [ $? -ne 0 ]; then
    echo "⚠️  Azure PowerShell modules not found"
    echo "📥 They will be installed automatically when the server starts"
fi

# Start the server
echo ""
echo "🌐 Starting web server on port 8080..."
echo "📊 Opening dashboard at http://localhost:8080"
echo ""
echo "Press Ctrl+C to stop the server"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Start PowerShell server
pwsh -File "./Start-AzureLandingZoneServer.ps1" -Port 8080
