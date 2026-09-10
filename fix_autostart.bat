@echo off
:: Check for Administrator elevation
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo Requesting Administrator privileges to fix Session 0 service...
    powershell -Command "Start-Process cmd.exe -ArgumentList '/c \"\"%~f0\"\"' -Verb RunAs"
    exit /b
)

title WinMCP Fix and Auto-Start Setup
cd /d "%~dp0"

echo ============================================================
echo   1. Removing Conflicting Session 0 Windows Service...
echo ============================================================
bin\nssm.exe stop WinMCP-Service 2>nul
bin\nssm.exe remove WinMCP-Service confirm 2>nul
sc.exe delete WinMCP-Service 2>nul

echo ============================================================
echo   2. Terminating any hanging background processes...
echo ============================================================
taskkill /F /IM cloudflared.exe 2>nul
taskkill /F /IM windows-mcp-server.exe 2>nul
taskkill /F /IM python.exe 2>nul
taskkill /F /IM pythonw.exe 2>nul

echo ============================================================
echo   3. Ensuring Interactive Logon Auto-Start is Active...
echo ============================================================
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install_autostart.ps1"

echo ============================================================
echo   4. Starting WinMCP in your Real Interactive Desktop Session...
echo ============================================================
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0run_winmcp.ps1"

echo.
echo ============================================================
echo   SUCCESS! WinMCP is now running in your interactive session!
echo   It will now auto-start every time you turn on the PC and log in.
echo ============================================================
echo.
pause
