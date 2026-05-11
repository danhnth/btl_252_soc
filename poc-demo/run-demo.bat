@echo off
chcp 65001 >nul
title SOC Demo - Windows Attacker
cls

echo ==============================================
echo    SOC ATTACK DEMO - WINDOWS ATTACKER
echo ==============================================
echo.
echo This script will launch attack scenarios against
echo your Alma Linux SOC stack for demonstration.
echo.
echo Requirements:
echo   - Python 3.7+ installed on this Windows machine
echo   - Alma Linux victim running SOC stack
echo   - Network connectivity between machines
echo.
echo ==============================================
echo.

:: Check if Python is available
python --version >nul 2>&1
if errorlevel 1 (
    echo [ERROR] Python is not installed or not in PATH
    echo Please install Python 3.7+ from https://python.org
    pause
    exit /b 1
)

echo [OK] Python detected
echo.

:: Get victim IP
set /p VICTIM_IP="Enter Alma Linux victim IP address: "

if "%VICTIM_IP%"=="" (
    echo [ERROR] IP address is required
    pause
    exit /b 1
)

echo.
echo Choose demo mode:
echo   1. Quick Demo (3 attacks, ~1 minute)
echo   2. Full Demo (all attacks, ~3 minutes)
echo   3. Continuous Demo (loops until stopped)
echo   4. Custom Port Demo (specify HTTP/SSH ports)
echo.

set /p DEMO_MODE="Select mode (1-4): "

if "%DEMO_MODE%"=="1" (
    echo.
    echo ==============================================
    echo    LAUNCHING QUICK DEMO
    echo ==============================================
    echo.
    python "%~dp0attacker-scripts\windows-attacker.py" %VICTIM_IP% --quick
) else if "%DEMO_MODE%"=="2" (
    echo.
    echo ==============================================
    echo    LAUNCHING FULL DEMO
    echo ==============================================
    echo.
    python "%~dp0attacker-scripts\windows-attacker.py" %VICTIM_IP% --all
) else if "%DEMO_MODE%"=="3" (
    echo.
    echo ==============================================
    echo    LAUNCHING CONTINUOUS DEMO
    echo ==============================================
    echo Press Ctrl+C to stop
echo.
    set /p INTERVAL="Interval between cycles (seconds, default 60): "
    if "!INTERVAL!"=="" set INTERVAL=60
    python "%~dp0attacker-scripts\windows-attacker.py" %VICTIM_IP% --all --continuous --interval %INTERVAL%
) else if "%DEMO_MODE%"=="4" (
    echo.
    set /p HTTP_PORT="HTTP Port (default 80): "
    if "!HTTP_PORT!"=="" set HTTP_PORT=80
    set /p SSH_PORT="SSH Port (default 22): "
    if "!SSH_PORT!"=="" set SSH_PORT=22
    echo.
    echo ==============================================
    echo    LAUNCHING CUSTOM DEMO
    echo ==============================================
    echo HTTP Port: %HTTP_PORT%
    echo SSH Port: %SSH_PORT%
    echo.
    python "%~dp0attacker-scripts\windows-attacker.py" %VICTIM_IP% --all --http-port %HTTP_PORT% --ssh-port %SSH_PORT%
) else (
    echo [ERROR] Invalid selection
    pause
    exit /b 1
)

echo.
echo ==============================================
echo    DEMO COMPLETE
echo ==============================================
echo.
echo Next steps:
echo   1. Open Kibana: http://%VICTIM_IP%:5601
echo   2. Open Wazuh: https://%VICTIM_IP%
echo   3. View alerts in Discover
echo.
pause
