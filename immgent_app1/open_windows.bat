@echo off
setlocal EnableExtensions EnableDelayedExpansion

REM Optional: accept a custom tar path as first arg
set "TAR=%~1"
if not defined TAR set "TAR=immgent_app1-app_latest.tar"

REM Locate the PowerShell script next to this BAT
set "PS1=%~dp0run_windows.ps1"
if not exist "%PS1%" (
  echo Can't find "%PS1%".
  exit /b 1
)

REM Prefer PowerShell 7 (pwsh) if available, else Windows PowerShell
where pwsh >nul 2>&1 && (set "PS=pwsh") || (set "PS=powershell")

"%PS%" -NoProfile -ExecutionPolicy Bypass -File "%PS1%" "%TAR%"
exit /b %errorlevel%
