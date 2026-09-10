@echo off
title WinMCP - Complete Root Uninstaller / حذف المشروع من جذوره
chcp 65001 >nul
cd /d "%~dp0"
echo ========================================================
echo    WinMCP - Complete Root Uninstaller
echo    حذف خادم Windows MCP وإلغاء تثبيته من كامل جذوره
echo ========================================================
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0uninstall.ps1" %*
if %ERRORLEVEL% NEQ 0 (
    echo.
    echo [ERROR] Uninstallation encountered an issue.
)
echo.
pause
