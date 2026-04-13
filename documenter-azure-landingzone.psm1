#Requires -Version 7.0

<#
.SYNOPSIS
    Azure Landing Zone Inventory Dashboard module.
.DESCRIPTION
    Loads the private script components and exports the two public commands:
      - Get-AzureLandingZoneInventory  : Collect inventory data from Azure Landing Zone environments.
      - Start-AzureLandingZoneServer   : Launch the local web dashboard for the collected data.
#>

# Dot-source private script components so their functions are available in this module scope.
. (Join-Path $PSScriptRoot 'Get-AzureLandingZoneInventory.ps1')

function Start-AzureLandingZoneServer {
    <#
    .SYNOPSIS
        Starts the Azure Landing Zone Inventory web dashboard.
    .DESCRIPTION
        Launches a local web server that provides a live view of Azure Landing Zone inventory
        with CAF compliance assessment, WAF scoring, and professional PDF export.
    .PARAMETER Port
        Port number for the web server (default: 8080).
    .EXAMPLE
        Start-AzureLandingZoneServer
    .EXAMPLE
        Start-AzureLandingZoneServer -Port 9090
    #>
    param(
        [int]$Port = 8080
    )
    & (Join-Path $PSScriptRoot 'Start-AzureLandingZoneServer.ps1') -Port $Port
}

Export-ModuleMember -Function 'Get-AzureLandingZoneInventory', 'Start-AzureLandingZoneServer'
