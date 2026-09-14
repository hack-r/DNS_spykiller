param(
    [string]$Allowlist = ""
)

$quad9 = @('9.9.9.9', '149.112.112.112')
$allowlistValues = @()

$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error 'Run protector_of_rights.bat or protector_of_rights_windows.ps1 from an Administrator shell.'
    exit 1
}

foreach ($rawValue in @($env:DNS_ALLOWLIST, $Allowlist)) {
    if (-not [string]::IsNullOrWhiteSpace($rawValue)) {
        $allowlistValues += $rawValue -split '[,\s]+' | Where-Object { $_ }
    }
}

$allowed = $quad9 + ($allowlistValues | Select-Object -Unique)
$ipv4InterfaceIndexes = @{}
foreach ($ipv4Interface in Get-NetIPInterface -AddressFamily IPv4 -ErrorAction SilentlyContinue) {
    $ipv4InterfaceIndexes[$ipv4Interface.InterfaceIndex] = $true
}

$adapters = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' -and $ipv4InterfaceIndexes.ContainsKey($_.InterfaceIndex) } | Sort-Object -Property InterfaceIndex -Unique

foreach ($adapter in $adapters) {
    $dnsConfig = Get-DnsClientServerAddress -InterfaceIndex $adapter.InterfaceIndex -AddressFamily IPv4
    $current = @($dnsConfig.ServerAddresses | Where-Object { $_ })

    if ($current.Count -gt 0 -and ($current | Where-Object { $_ -notin $allowed }).Count -eq 0) {
        Write-Output ('DNS settings already allowed for interface: ' + $adapter.InterfaceAlias)
        continue
    }

    $desired = @($quad9)

    foreach ($dns in ($current | Where-Object { $_ -in $allowlistValues } | Select-Object -Unique)) {
        if ($dns -notin $desired) {
            $desired += $dns
        }
    }

    Write-Output ('Updating DNS settings for interface: ' + $adapter.InterfaceAlias)
    Set-DnsClientServerAddress -InterfaceIndex $adapter.InterfaceIndex -ServerAddresses $desired
}

Write-Output 'DNS checks and modifications complete.'
