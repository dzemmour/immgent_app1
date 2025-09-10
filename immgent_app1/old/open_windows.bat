@echo off
setlocal EnableExtensions EnableDelayedExpansion

REM Optional: accept a custom tar path as first arg
set TAR=%~1
if "%TAR%"=="" set TAR=immgent_app1-app_latest.tar

where powershell >nul 2>&1
if errorlevel 1 (
  echo PowerShell is required. Please run the PowerShell script directly.
  exit /b 1
)

REM Pass the tar path through to the PowerShell script
powershell -ExecutionPolicy Bypass -File "%~dp0run-windows.ps1" "%TAR%"
