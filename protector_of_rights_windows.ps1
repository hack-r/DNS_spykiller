param(
    [string]$Allowlist = ""
)

$quad9 = @('9.9.9.9', '149.112.112.112')
$allowlistValues = @()

foreach ($rawValue in @($env:DNS_ALLOWLIST, $Allowlist)) {
    if (-not [string]::IsNullOrWhiteSpace($rawValue)) {
        $allowlistValues += $rawValue -split '[,\s]+' | Where-Object { $_ }
    }
}

$allowed = $quad9 + ($allowlistValues | Select-Object -Unique)
$adapters = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' }

foreach ($adapter in $adapters) {
    $dnsConfig = Get-DnsClientServerAddress -InterfaceIndex $adapter.InterfaceIndex -AddressFamily IPv4
    $current = @($dnsConfig.ServerAddresses | Where-Object { $_ })

    if ($current.Count -gt 0 -and ($current | Where-Object { $_ -notin $allowed }).Count -eq 0) {
        Write-Output ('DNS settings already allowed for interface: ' + $adapter.InterfaceAlias)
        continue
    }

    $desired = @($current | Where-Object { $_ -in $allowed } | Select-Object -Unique)
    if ($desired.Count -eq 0) {
        $desired = @($quad9)
    }

    foreach ($dns in $quad9) {
        if ($desired.Count -ge [Math]::Max($current.Count, 2)) {
            break
        }

        if ($dns -notin $desired) {
            $desired += $dns
        }
    }

    Write-Output ('Updating DNS settings for interface: ' + $adapter.InterfaceAlias)
    Set-DnsClientServerAddress -InterfaceIndex $adapter.InterfaceIndex -ServerAddresses $desired
}

Write-Output 'DNS checks and modifications complete.'
