@echo off
title WinMCP - Windows MCP Server Control Center
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0winmcp.ps1" %*
