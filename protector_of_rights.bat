@echo off
setlocal

set "ALLOWLIST=%DNS_ALLOWLIST%"

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
  echo Replaces non-Quad9 DNS servers with Quad9 on active Windows interfaces.
  echo Supports the same DNS_ALLOWLIST and --allow inputs as protector_of_rights.sh.
  exit /b 0
)
if /I "%~1"=="--help" (
  echo Usage: protector_of_rights.bat [--allow "IP [MORE_IPS]"]
  echo.
  echo Replaces non-Quad9 DNS servers with Quad9 on active Windows interfaces.
  echo Supports the same DNS_ALLOWLIST and --allow inputs as protector_of_rights.sh.
  exit /b 0
)

echo Unknown argument: %~1
exit /b 1

:run_script
set "DNS_ALLOWLIST_WINDOWS=%ALLOWLIST%"

powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$quad9 = @('9.9.9.9','149.112.112.112');" ^
  "$allowlist = @();" ^
  "if ($env:DNS_ALLOWLIST_WINDOWS) { $allowlist = $env:DNS_ALLOWLIST_WINDOWS -split '[,\s]+' | Where-Object { $_ }; }" ^
  "$allowed = $quad9 + $allowlist;" ^
  "$adapters = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' };" ^
  "foreach ($adapter in $adapters) {" ^
  "  $dnsConfig = Get-DnsClientServerAddress -InterfaceIndex $adapter.InterfaceIndex -AddressFamily IPv4;" ^
  "  $current = @($dnsConfig.ServerAddresses | Where-Object { $_ });" ^
  "  if ($current.Count -gt 0 -and ($current | Where-Object { $_ -notin $allowed }).Count -eq 0) {" ^
  "    Write-Output ('DNS settings already allowed for interface: ' + $adapter.InterfaceAlias);" ^
  "    continue;" ^
  "  }" ^
  "  $desired = @($current | Where-Object { $_ -in $allowed } | Select-Object -Unique);" ^
  "  if ($desired.Count -eq 0) { $desired = @($quad9); }" ^
  "  foreach ($dns in $quad9) { if ($desired.Count -ge [Math]::Max($current.Count, 2)) { break }; if ($dns -notin $desired) { $desired += $dns } }" ^
  "  Write-Output ('Updating DNS settings for interface: ' + $adapter.InterfaceAlias);" ^
  "  Set-DnsClientServerAddress -InterfaceIndex $adapter.InterfaceIndex -ServerAddresses $desired;" ^
  "}" ^
  "Write-Output 'DNS checks and modifications complete.'"

if errorlevel 1 exit /b 1
