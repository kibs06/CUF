@echo off
REM Double-click this file, click Yes on the UAC prompt, and it adds the
REM firewall rule that unblocks http://192.168.1.215:8099/ on THIS PC.
REM Cause: this PC's firewall DefaultOutboundAction = Block and the only
REM web rule allows ports 80,443, so port 8099 is denied instantly
REM ("Bad access" / Edge ERR_NETWORK_ACCESS_DENIED) while ping works.
net session >nul 2>&1
if %errorlevel% neq 0 (
  powershell -NoProfile -Command "Start-Process '%~f0' -Verb RunAs"
  exit /b
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0fix-lan-8099-firewall.ps1"
echo.
pause
