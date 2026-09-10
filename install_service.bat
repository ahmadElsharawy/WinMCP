@echo off
title Install WinMCP Windows Service
echo ========================================================
echo       Install WinMCP as Native Windows Service
echo ========================================================
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install_service.ps1"
pause
