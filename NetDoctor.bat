@echo off
title NetDoctor - Automated Network Diagnostic & Optimizer
:: Auto-request Administrator Privileges
net session >nul 2>&1
if %errorLevel% == 0 (
    goto :runScript
) else (
    echo Requesting Administrator permissions...
    powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process '%~dpnx0' -Verb RunAs"
    exit /b
)

:runScript
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "NetDoctor.ps1"
pause
