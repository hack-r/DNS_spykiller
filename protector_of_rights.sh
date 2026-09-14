#!/bin/bash

set -euo pipefail

readonly QUAD9_DNS=("9.9.9.9" "149.112.112.112")
ALLOWLIST=()

usage() {
  cat <<'EOF'
Usage: protector_of_rights.sh [--allow "IP [MORE_IPS]"]

Replaces non-Quad9 DNS servers with Quad9 on macOS network services.

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

services_output=$(networksetup -listallnetworkservices)

while IFS= read -r service; do
  if [ -z "$service" ] || [ "$service" = "An asterisk (*) denotes that a network service is disabled." ]; then
    continue
  fi

  if [[ "$service" == \** ]]; then
    echo "Skipping disabled network service: ${service#\*}"
    continue
  fi

  echo "Checking DNS settings for network service: $service"

  if dns_output=$(networksetup -getdnsservers "$service" 2>&1); then
    :
  else
    echo "Unable to read DNS settings for network service: $service" >&2
    echo "$dns_output" >&2
    continue
  fi

  if [[ "$dns_output" == *"There aren't any DNS Servers set"* ]]; then
    echo "No DNS servers configured for network service: $service"
    continue
  fi

  current_dns=()
  while IFS= read -r dns_server; do
    if [ -n "$dns_server" ]; then
      current_dns+=("$dns_server")
    fi
  done <<< "$dns_output"

  if [ "${#current_dns[@]}" -eq 0 ]; then
    echo "No readable DNS servers found for network service: $service"
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
      echo "Replacing DNS server on $service: $dns_server"
      replace_dns=true
      add_replacement_quad9
    fi
  done

  if [ "$replace_dns" = true ]; then
    if [ "$preserved_dns" = false ]; then
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

    networksetup -setdnsservers "$service" "${desired_dns[@]}"
  else
    echo "DNS settings already allowed for network service: $service"
  fi
done <<< "$services_output"

echo "DNS checks and modifications complete."
