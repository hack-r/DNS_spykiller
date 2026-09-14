@echo off
setlocal

powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$quad9 = @('9.9.9.9','149.112.112.112');" ^
  "$adapters = Get-DnsClientServerAddress -AddressFamily IPv4 | Where-Object { $_.InterfaceAlias -and $_.ServerAddresses -and $_.ServerAddresses.Count -gt 0 };" ^
  "foreach ($adapter in $adapters) {" ^
  "  $current = @($adapter.ServerAddresses);" ^
  "  if (($current | Where-Object { $_ -notin $quad9 }).Count -eq 0) {" ^
  "    Write-Output ('DNS settings already allowed for interface: ' + $adapter.InterfaceAlias);" ^
  "    continue;" ^
  "  }" ^
  "  Write-Output ('Updating DNS settings for interface: ' + $adapter.InterfaceAlias);" ^
  "  Set-DnsClientServerAddress -InterfaceIndex $adapter.InterfaceIndex -ServerAddresses $quad9;" ^
  "}" ^
  "Write-Output 'DNS checks and modifications complete.'"

if errorlevel 1 exit /b 1
