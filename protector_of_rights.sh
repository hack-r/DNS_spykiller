#!/bin/bash

# Get a list of network services
services=$(networksetup -listallnetworkservices)

# Iterate over each network service
for service in $services; do
  echo "Checking DNS settings for network service: $service"

  # Get the current DNS servers for the network service
  dns_servers=$(networksetup -getdnsservers "$service")

  # Check if DNS servers exist
  if [ -n "$dns_servers" ]; then
    # Flag to track if a DNS server needs to be replaced
    replace_dns=false

    # Iterate over each DNS server
    for dns_server in $dns_servers; do
      # Check if DNS server begins with "75" or "76"
      if [[ $dns_server =~ ^75|^76 ]]; then
        echo "Replacing DNS server: $dns_server with 9.9.9.9"
        replace_dns=true
      fi
    done

    # Replace DNS servers if necessary
    if [ "$replace_dns" = true ]; then
      networksetup -setdnsservers "$service" 9.9.9.9
    fi
  fi

  # Remove any search domain
  networksetup -setsearchdomains "$service" "empty"
done

echo "DNS checks and modifications complete."
