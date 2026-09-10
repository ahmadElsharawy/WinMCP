@echo off
title WinMCP - Complete Root Uninstaller
cd /d "%~dp0"
echo ========================================================
echo    WinMCP - Complete Root Uninstaller & Purge
echo ========================================================
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0uninstall.ps1" %*
if %ERRORLEVEL% NEQ 0 (
    echo.
    echo [ERROR] Uninstallation encountered an issue.
)
echo.
pause
