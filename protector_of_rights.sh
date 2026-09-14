#!/bin/bash

set -euo pipefail

readonly QUAD9_DNS=("9.9.9.9" "149.112.112.112")
readonly OS_RELEASE_FILE="${OS_RELEASE_FILE:-/etc/os-release}"
ALLOWLIST=()
PLATFORM=""
PLATFORM_LABEL=""
LINUX_BACKEND=""

usage() {
  cat <<'EOF'
Usage: protector_of_rights.sh [--allow "IP [MORE_IPS]"]

Replaces non-Quad9 DNS servers with Quad9 on:
  - macOS network services
  - Debian-based Linux systems with NetworkManager
  - Fedora-based Linux systems with NetworkManager

For Windows, use protector_of_rights.bat.

Options:
  --allow LIST   Space- or comma-separated DNS server IPs to preserve.
                 You can also set DNS_ALLOWLIST with the same format.
  -h, --help     Show this help text.
EOF
}

add_unique() {
  local value="$1"
  local existing

  for existing in "${ALLOWLIST[@]}"; do
    if [ "$existing" = "$value" ]; then
      return 0
    fi
  done

  ALLOWLIST+=("$value")
}

append_allowlist_entries() {
  local raw_entries="$1"
  local entry

  raw_entries="${raw_entries//,/ }"
  for entry in $raw_entries; do
    if [ -n "$entry" ]; then
      add_unique "$entry"
    fi
  done
}

contains_dns() {
  local needle="$1"
  shift

  local value
  for value in "$@"; do
    if [ "$value" = "$needle" ]; then
      return 0
    fi
  done

  return 1
}

contains_token() {
  local needle="$1"
  shift

  local value
  for value in "$@"; do
    case " $value " in
      *" $needle "*) return 0 ;;
    esac
  done

  return 1
}

is_allowed_dns() {
  local dns_server="$1"

  contains_dns "$dns_server" "${QUAD9_DNS[@]}" || contains_dns "$dns_server" "${ALLOWLIST[@]}"
}

add_replacement_quad9() {
  local quad9_dns

  while [ "$quad9_index" -lt "${#replacement_quad9_pool[@]}" ]; do
    quad9_dns="${replacement_quad9_pool[$quad9_index]}"
    quad9_index=$((quad9_index + 1))

    if ! contains_dns "$quad9_dns" "${desired_dns[@]}"; then
      desired_dns+=("$quad9_dns")
      return 0
    fi
  done
}

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

join_by_comma() {
  local IFS=,
  printf '%s' "$*"
}

normalize_dns_entries() {
  local raw_dns="$1"
  local dns_server

  raw_dns="${raw_dns//$'\r'/ }"
  raw_dns="${raw_dns//,/ }"
  raw_dns="${raw_dns//;/ }"

  for dns_server in $raw_dns; do
    if [ -n "$dns_server" ] && [ "$dns_server" != "--" ]; then
      printf '%s\n' "$dns_server"
    fi
  done
}

detect_platform() {
  local uname_output
  uname_output=$(uname -s)

  case "$uname_output" in
    Darwin)
      PLATFORM="macos"
      PLATFORM_LABEL="macOS"
      ;;
    Linux)
      local distro_values=""
      if [ -r "$OS_RELEASE_FILE" ]; then
        distro_values=$(sed -n 's/^\(ID\|ID_LIKE\)=//p' "$OS_RELEASE_FILE" | tr -d '"' | tr '\n' ' ')
      fi

      if contains_token "debian" "$distro_values" || contains_token "ubuntu" "$distro_values"; then
        PLATFORM="linux-debian"
        PLATFORM_LABEL="Debian-based Linux"
      elif contains_token "fedora" "$distro_values" || contains_token "rhel" "$distro_values" || contains_token "centos" "$distro_values"; then
        PLATFORM="linux-fedora"
        PLATFORM_LABEL="Fedora-based Linux"
      else
        echo "Unsupported Linux distribution. This script currently supports Debian- and Fedora-based Linux." >&2
        exit 1
      fi

      if command_exists nmcli; then
        LINUX_BACKEND="nmcli"
      else
        echo "Unable to manage DNS on $PLATFORM_LABEL: this script requires NetworkManager's nmcli." >&2
        exit 1
      fi
      ;;
    CYGWIN*|MINGW*|MSYS*)
      echo "Windows is supported via protector_of_rights.bat. Please run that script instead." >&2
      exit 1
      ;;
    *)
      echo "Unsupported operating system: $uname_output" >&2
      exit 1
      ;;
  esac
}

list_services() {
  case "$PLATFORM" in
    macos)
      networksetup -listallnetworkservices
      ;;
    linux-debian|linux-fedora)
      nmcli -t -f UUID connection show --active | sed '/^$/d'
      ;;
  esac
}

get_service_label() {
  local service="$1"

  case "$PLATFORM" in
    macos)
      printf '%s\n' "$service"
      ;;
    linux-debian|linux-fedora)
      nmcli -g connection.id connection show "$service"
      ;;
  esac
}

get_service_dns() {
  local service="$1"

  case "$PLATFORM" in
    macos)
      networksetup -getdnsservers "$service"
      ;;
    linux-debian|linux-fedora)
      local ipv4_dns ipv6_dns
      ipv4_dns=$(nmcli -g ipv4.dns connection show "$service")
      ipv6_dns=$(nmcli -g ipv6.dns connection show "$service")
      normalize_dns_entries "$ipv4_dns"
      normalize_dns_entries "$ipv6_dns"
      ;;
  esac
}

is_ipv6_address() {
  case "$1" in
    *:*) return 0 ;;
    *) return 1 ;;
  esac
}

set_service_dns() {
  local service="$1"
  shift

  case "$PLATFORM" in
    macos)
      networksetup -setdnsservers "$service" "$@"
      ;;
    linux-debian|linux-fedora)
      local dns_server
      local ipv4_dns=()
      local ipv6_dns=()
      local ipv4_dns_csv=""
      local ipv6_dns_csv=""

      for dns_server in "$@"; do
        if is_ipv6_address "$dns_server"; then
          ipv6_dns+=("$dns_server")
        else
          ipv4_dns+=("$dns_server")
        fi
      done

      if [ "${#ipv4_dns[@]}" -gt 0 ]; then
        ipv4_dns_csv=$(join_by_comma "${ipv4_dns[@]}")
        nmcli connection modify "$service" ipv4.ignore-auto-dns yes ipv4.dns "$ipv4_dns_csv"
      else
        nmcli connection modify "$service" ipv4.dns "" ipv4.ignore-auto-dns no
      fi

      if [ "${#ipv6_dns[@]}" -gt 0 ]; then
        ipv6_dns_csv=$(join_by_comma "${ipv6_dns[@]}")
        nmcli connection modify "$service" ipv6.ignore-auto-dns yes ipv6.dns "$ipv6_dns_csv"
      else
        nmcli connection modify "$service" ipv6.dns "" ipv6.ignore-auto-dns no
      fi

      local active_device
      local active_devices_raw
      local connection_state
      local dns_applied=false
      connection_state=$(nmcli -g GENERAL.STATE connection show "$service" | head -n 1)
      active_devices_raw=$(nmcli -g GENERAL.DEVICES connection show "$service" | head -n 1)
      active_devices_raw="${active_devices_raw//:/ }"
      active_devices_raw="${active_devices_raw//,/ }"
      for active_device in $active_devices_raw; do
        if [ -n "$active_device" ] && [ "$active_device" != "--" ]; then
          if nmcli device reapply "$active_device" >/dev/null 2>&1; then
            dns_applied=true
          fi
        fi
      done

      if [ "$dns_applied" = false ]; then
        if [[ "$connection_state" == activated* ]]; then
          if nmcli connection up "$service" >/dev/null 2>&1; then
            dns_applied=true
          fi
        else
          dns_applied=true
        fi
      fi

      if [ "$dns_applied" = false ]; then
        echo "Failed to apply updated DNS settings for service: $service" >&2
        return 1
      fi
      ;;
  esac
}

if [ -n "${DNS_ALLOWLIST:-}" ]; then
  append_allowlist_entries "$DNS_ALLOWLIST"
fi

while [ "$#" -gt 0 ]; do
  case "$1" in
    --allow)
      shift
      if [ "$#" -eq 0 ]; then
        echo "Missing value for --allow." >&2
        usage >&2
        exit 1
      fi
      append_allowlist_entries "$1"
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
  shift
done

detect_platform
services_output=$(list_services)

while IFS= read -r service; do
  service_label="$service"
  if [ -z "$service" ]; then
    continue
  fi

  if [ "$PLATFORM" = "macos" ] && [ "$service" = "An asterisk (*) denotes that a network service is disabled." ]; then
    continue
  fi

  if [ "$PLATFORM" = "macos" ] && [[ "$service" == \** ]]; then
    echo "Skipping disabled network service: ${service#\*}"
    continue
  fi

  if [[ "$PLATFORM" == linux-* ]]; then
    service_label=$(get_service_label "$service")
  fi

  echo "Checking DNS settings for $PLATFORM_LABEL service: $service_label"

  if dns_output=$(get_service_dns "$service" 2>&1); then
    :
  else
    echo "Unable to read DNS settings for service: $service_label" >&2
    echo "$dns_output" >&2
    continue
  fi

  if [ "$PLATFORM" = "macos" ] && [[ "$dns_output" == *"There aren't any DNS Servers set"* ]]; then
    echo "No DNS servers configured for service: $service_label"
    continue
  fi

  current_dns=()
  while IFS= read -r dns_server; do
    if [ -n "$dns_server" ]; then
      current_dns+=("$dns_server")
    fi
  done <<< "$dns_output"

  if [ "${#current_dns[@]}" -eq 0 ]; then
    echo "No readable DNS servers found for service: $service_label"
    continue
  fi

  desired_dns=()
  replace_dns=false
  preserved_dns=false
  replacement_quad9_pool=()
  quad9_index=0

  for quad9_dns in "${QUAD9_DNS[@]}"; do
    if ! contains_dns "$quad9_dns" "${current_dns[@]}"; then
      replacement_quad9_pool+=("$quad9_dns")
    fi
  done

  for quad9_dns in "${QUAD9_DNS[@]}"; do
    replacement_quad9_pool+=("$quad9_dns")
  done

  for dns_server in "${current_dns[@]}"; do
    if is_allowed_dns "$dns_server"; then
      preserved_dns=true
      if ! contains_dns "$dns_server" "${desired_dns[@]}"; then
        desired_dns+=("$dns_server")
      fi
    else
      echo "Replacing DNS server on $service_label: $dns_server"
      replace_dns=true
      add_replacement_quad9
    fi
  done

  if [ "$replace_dns" = true ]; then
    if [ "$preserved_dns" = false ]; then
      desired_dns=()
      for quad9_dns in "${QUAD9_DNS[@]}"; do
        if ! contains_dns "$quad9_dns" "${desired_dns[@]}"; then
          desired_dns+=("$quad9_dns")
        fi
      done
    elif [ "${#desired_dns[@]}" -lt "${#current_dns[@]}" ]; then
      for quad9_dns in "${QUAD9_DNS[@]}"; do
        if [ "${#desired_dns[@]}" -ge "${#current_dns[@]}" ]; then
          break
        fi

        if ! contains_dns "$quad9_dns" "${desired_dns[@]}"; then
          desired_dns+=("$quad9_dns")
        fi
      done
    fi

    set_service_dns "$service" "${desired_dns[@]}"
  else
    echo "DNS settings already allowed for service: $service_label"
  fi
done <<< "$services_output"

echo "DNS checks and modifications complete for $PLATFORM_LABEL."
