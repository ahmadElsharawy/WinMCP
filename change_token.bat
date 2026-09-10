@echo off
title WinMCP - Token Management
cd /d "%~dp0"
echo ========================================================
echo    WinMCP - Security Token Management
echo ========================================================
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0winmcp.ps1" token change
echo.
pause
