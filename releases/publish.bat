@echo off
REM ════════════════════════════════════════════════════════════════════
REM publish.bat — one-command release for SoleVision (Windows wrapper)
REM
REM   releases\publish.bat <new-version> ["note1|note2"]
REM   e.g. releases\publish.bat 1.0.1 "Fixed login crash|Improved startup time"
REM
REM Delegates to releases/publish.sh via Git Bash. Requires:
REM   - Git for Windows (provides `bash`) on PATH
REM   - Flutter on PATH
REM   - GitHub CLI (gh) installed + authenticated
REM ════════════════════════════════════════════════════════════════════

where bash >nul 2>nul
if errorlevel 1 (
  echo [ERROR] Git Bash was not found on PATH. Install Git for Windows: https://git-scm.com/
  exit /b 1
)

bash "%~dp0publish.sh" %*
