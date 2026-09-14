# DNS_spykiller

This macOS script reviews each configured network service and replaces DNS servers with Quad9 (`9.9.9.9`, `149.112.112.112`) unless the server is already using Quad9 or has been explicitly allowlisted.

## Usage

```bash
./protector_of_rights.sh
```

Preserve specific resolver IPs with an allowlist:

```bash
./protector_of_rights.sh --allow "127.0.0.1 ::1 134.195.4.2"
```

You can also use `DNS_ALLOWLIST` with space- or comma-separated IP values:

```bash
DNS_ALLOWLIST="127.0.0.1,::1,134.195.4.2" ./protector_of_rights.sh
```

This is useful if you intentionally route DNS through a local DNSCrypt listener (for example `127.0.0.1`) or want to keep a trusted provider such as OpenNIC on an allowlist.
