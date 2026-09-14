# DNS_spykiller

This project reviews configured DNS settings and replaces non-Quad9 DNS servers with Quad9 (`9.9.9.9`, `149.112.112.112`) unless the server is already using Quad9 or has been explicitly allowlisted.

Supported platforms:

- macOS via `networksetup`
- Debian-based Linux via NetworkManager `nmcli`
- Fedora-based Linux via NetworkManager `nmcli`
- Windows via `protector_of_rights.bat`

## Usage

```bash
./protector_of_rights.sh
```

On Windows:

```bat
protector_of_rights.bat
```

The Windows script accepts the same `--allow` flag and `DNS_ALLOWLIST` environment variable as the Unix shell script.

Preserve specific resolver IPs with an allowlist:

```bash
./protector_of_rights.sh --allow "127.0.0.1 ::1 134.195.4.2"
```

You can also use `DNS_ALLOWLIST` with space- or comma-separated IP values:

```bash
DNS_ALLOWLIST="127.0.0.1,::1,134.195.4.2" ./protector_of_rights.sh
```

This is useful if you intentionally route DNS through a local DNSCrypt listener (for example `127.0.0.1`) or want to keep a trusted provider such as OpenNIC on an allowlist.

## Notes

- The Unix shell script auto-detects macOS vs. supported Linux distributions.
- On Linux, the script currently supports NetworkManager-managed connections through `nmcli`.
- The Windows batch file uses PowerShell to update active IPv4 interfaces and should be run from an Administrator shell.
