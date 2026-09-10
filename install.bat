@echo off
title WinMCP Automated Installer
cd /d "%~dp0"
echo ========================================================
echo    WinMCP - Turnkey Windows MCP Server Setup
echo ========================================================
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1" %*
if %ERRORLEVEL% NEQ 0 (
    echo.
    echo [ERROR] Installation encountered an error.
)
pause
