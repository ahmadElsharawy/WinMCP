@echo off
title WinMCP - Token Management
chcp 65001 >nul
cd /d "%~dp0"
echo ========================================================
echo    WinMCP - Security Token Management / إدارة التوكن
echo ========================================================
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0winmcp.ps1" token change
echo.
pause
