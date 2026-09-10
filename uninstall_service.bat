@echo off
title Uninstall WinMCP Windows Service
echo ========================================================
echo       Uninstall WinMCP Windows Service
echo ========================================================
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0uninstall_service.ps1"
pause
