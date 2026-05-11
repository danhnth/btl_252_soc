@echo off
chcp 65001 >nul
title Windows Attack Client for SOC Demo
cls

echo ==============================================
echo    WINDOWS ATTACK CLIENT - SURICATA DEMO
echo ==============================================
echo.
echo This script connects to the Alma Linux victim
echo and triggers attacks that generate Suricata alerts.
echo.
echo PREREQUISITES:
echo   - Python 3.7+ installed on this Windows machine
echo   - Attack relay running on Alma Linux victim
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
echo Checking connection to attack relay on %VICTIM_IP%:9999...
echo.

:: Test connection first
python -c "import urllib.request; urllib.request.urlopen('http://%VICTIM_IP%:9999/health', timeout=5)" >nul 2>&1
if errorlevel 1 (
    echo [ERROR] Cannot connect to attack relay!
    echo.
    echo Please ensure:
    echo   1. SOC stack is running on the victim
    echo   2. Attack relay is started on Alma Linux:
echo.
    echo      ssh user@%VICTIM_IP%
    echo      cd ~/btl_252_soc/poc-demo/attacker-scripts
    echo      python3 external-attack-relay.py
    echo.
    echo   3. Firewall allows port 9999
    echo.
    pause
    exit /b 1
)

echo [OK] Connected to attack relay
echo.

:: Choose demo mode
echo Choose demo mode:
echo   1. Quick Demo (~1 minute, 4 attack scenarios)
echo   2. Full Demo (~3 minutes, all attack scenarios)
echo   3. List Available Scenarios
echo   4. Custom Scenario (specify which attack)
echo.

set /p DEMO_MODE="Select mode (1-4): "

if "%DEMO_MODE%"=="1" (
    echo.
    echo ==============================================
    echo    LAUNCHING QUICK DEMO
    echo ==============================================
    echo.
    python "%~dp0attacker-scripts\windows-attack-client.py" %VICTIM_IP% --quick
) else if "%DEMO_MODE%"=="2" (
    echo.
    echo ==============================================
    echo    LAUNCHING FULL DEMO
    echo ==============================================
    echo.
    python "%~dp0attacker-scripts\windows-attack-client.py" %VICTIM_IP% --all
) else if "%DEMO_MODE%"=="3" (
    echo.
    python "%~dp0attacker-scripts\windows-attack-client.py" %VICTIM_IP% --list
    echo.
    pause
    exit /b 0
) else if "%DEMO_MODE%"=="4" (
    echo.
    python "%~dp0attacker-scripts\windows-attack-client.py" %VICTIM_IP% --list
    echo.
    set /p SCENARIO="Enter scenario name: "
    if "!SCENARIO!"=="" (
        echo [ERROR] Scenario name is required
        pause
        exit /b 1
    )
    echo.
    echo ==============================================
    echo    LAUNCHING CUSTOM DEMO
    echo ==============================================
    echo Scenario: %SCENARIO%
    echo.
    python "%~dp0attacker-scripts\windows-attack-client.py" %VICTIM_IP% --scenario %SCENARIO%
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
echo   1. Wait 15-30 seconds for alerts to appear
echo   2. Open Kibana: http://%VICTIM_IP%:5601
echo   3. Navigate to: Analytics -^> Discover
echo   4. Select: suricata-ids-*
echo   5. Filter: event_type : alert
echo.
pause
