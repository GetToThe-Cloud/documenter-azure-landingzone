@echo off
REM Azure Landing Zone Inventory Server Startup Script for Windows

echo ========================================
echo Azure Landing Zone Inventory Server
echo ========================================
echo.

echo Checking for existing instances...
taskkill /F /IM pwsh.exe /FI "WINDOWTITLE eq Start-AzureLandingZoneServer*" 2>nul
timeout /t 1 /nobreak >nul

echo.
echo Starting web server on port 8080...
echo Opening dashboard at http://localhost:8080
echo.
echo Press Ctrl+C to stop the server
echo ----------------------------------------
echo.

REM Start PowerShell server
pwsh -File "%~dp0Start-AzureLandingZoneServer.ps1" -Port 8080

pause
