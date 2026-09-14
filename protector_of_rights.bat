@echo off
setlocal

powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$quad9 = @('9.9.9.9','149.112.112.112');" ^
  "$adapters = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' };" ^
  "foreach ($adapter in $adapters) {" ^
  "  $dnsConfig = Get-DnsClientServerAddress -InterfaceIndex $adapter.InterfaceIndex -AddressFamily IPv4;" ^
  "  $current = @($dnsConfig.ServerAddresses);" ^
  "  if (($current | Where-Object { $_ -notin $quad9 }).Count -eq 0) {" ^
  "    Write-Output ('DNS settings already allowed for interface: ' + $adapter.InterfaceAlias);" ^
  "    continue;" ^
  "  }" ^
  "  Write-Output ('Updating DNS settings for interface: ' + $adapter.InterfaceAlias);" ^
  "  Set-DnsClientServerAddress -InterfaceIndex $adapter.InterfaceIndex -ServerAddresses $quad9;" ^
  "}" ^
  "Write-Output 'DNS checks and modifications complete.'"

if errorlevel 1 exit /b 1
