@echo off
setlocal

set "ALLOWLIST=%DNS_ALLOWLIST%"
set "POWERSHELL_EXE="

where powershell >nul 2>nul && set "POWERSHELL_EXE=powershell"
if not defined POWERSHELL_EXE (
  where pwsh >nul 2>nul && set "POWERSHELL_EXE=pwsh"
)
if not defined POWERSHELL_EXE (
  echo Unable to find PowerShell. Install powershell.exe or pwsh.exe and try again.
  exit /b 1
)

:parse_args
if "%~1"=="" goto run_script
if /I "%~1"=="--allow" (
  shift
  if "%~1"=="" (
    echo Missing value for --allow.
    exit /b 1
  )
  if defined ALLOWLIST (
    set "ALLOWLIST=%ALLOWLIST% %~1"
  ) else (
    set "ALLOWLIST=%~1"
  )
  shift
  goto parse_args
)
if /I "%~1"=="-h" (
  echo Usage: protector_of_rights.bat [--allow "IP [MORE_IPS]"]
  echo.
  echo Replaces non-Quad9 IPv4 DNS servers with Quad9 on active Windows interfaces.
  echo Supports the same DNS_ALLOWLIST and --allow inputs as protector_of_rights.sh.
  exit /b 0
)
if /I "%~1"=="--help" (
  echo Usage: protector_of_rights.bat [--allow "IP [MORE_IPS]"]
  echo.
  echo Replaces non-Quad9 IPv4 DNS servers with Quad9 on active Windows interfaces.
  echo Supports the same DNS_ALLOWLIST and --allow inputs as protector_of_rights.sh.
  exit /b 0
)

echo Unknown argument: %~1
exit /b 1

:run_script
if defined ALLOWLIST (
  %POWERSHELL_EXE% -NoProfile -ExecutionPolicy Bypass -File "%~dp0protector_of_rights_windows.ps1" -Allowlist "%ALLOWLIST%"
) else (
  %POWERSHELL_EXE% -NoProfile -ExecutionPolicy Bypass -File "%~dp0protector_of_rights_windows.ps1"
)

if errorlevel 1 exit /b 1
