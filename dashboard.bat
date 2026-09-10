@echo off
title WinMCP Control Center
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0winmcp.ps1" menu
