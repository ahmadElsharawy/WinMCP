@echo off
title WinMCP Interactive Dashboard
echo ========================================================
echo        WinMCP Interactive Control Center Dashboard
echo ========================================================
echo.
echo Launching dashboard in your default browser...
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0winmcp.ps1" dashboard
