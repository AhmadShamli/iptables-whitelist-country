#!/bin/bash

# List of country ISO codes to allow (space-separated)
COUNTRY_CODES=("US" "CA")

# Specify the IP addresses you want to allow (IPv4)
ALLOWED_IPS=("192.168.1.100" "192.168.1.101")

# Specify the IP addresses you want to allow (IPv6)
ALLOWED_IPS_V6=("2001:db8::1" "2001:db8::2")

# Paths to MaxMind DB files
LOCATIONS_DB="GeoLite2-Country-Locations-en.csv"
BLOCKS_IPV4_DB="GeoLite2-Country-Blocks-IPv4.csv"
BLOCKS_IPV6_DB="GeoLite2-Country-Blocks-IPv6.csv"

# Names for the ipset and iptables chains
IPSET_NAME_IPV4="allowed_country_ips_ipv4"
IPSET_NAME_IPV6="allowed_country_ips_ipv6"
IPTABLES_CHAIN_IPV4="ALLOW_COUNTRY_IPV4"
IPTABLES_CHAIN_IPV6="ALLOW_COUNTRY_IPV6"

# Check for required files
FILES_MISSING=false
if [[ ! -f $LOCATIONS_DB || ! -f $BLOCKS_IPV4_DB || ! -f $BLOCKS_IPV6_DB ]]; then
    FILES_MISSING=true
    echo "Required GeoLite2 database files are missing. Falling back to ipdeny.com."
fi

# Install necessary tools if not already installed (Ubuntu/Debian example)
if ! command -v ipset &> /dev/null; then
    sudo apt-get update
    sudo apt-get install -y ipset
fi

if ! command -v iptables &> /dev/null; then
    sudo apt-get update
    sudo apt-get install -y iptables
fi

if ! command -v ip6tables &> /dev/null; then
    sudo apt-get update
    sudo apt-get install -y iptables
fi

if ! command -v wget &> /dev/null; then
    sudo apt-get update
    sudo apt-get install -y wget
fi

# Create new ipsets
sudo ipset create $IPSET_NAME_IPV4 hash:net
sudo ipset create $IPSET_NAME_IPV6 hash:net family inet6

# Flush the ipsets (remove all existing entries)
sudo ipset flush $IPSET_NAME_IPV4
sudo ipset flush $IPSET_NAME_IPV6

if [ "$FILES_MISSING" = false ]; then
    # Map country ISO codes to geoname IDs
    declare -A GEONAME_IDS
    while IFS=',' read -r geoname_id locale_code continent_code continent_name country_iso_code country_name is_in_european_union; do
        for country in "${COUNTRY_CODES[@]}"; do
            if [[ "${country_iso_code^^}" == "${country^^}" ]]; then
                GEONAME_IDS[$geoname_id]=1
            fi
        done
    done < <(tail -n +2 $LOCATIONS_DB)

    # Add IP ranges to the ipsets based on geoname IDs
    while IFS=',' read -r network geoname_id registered_country_geoname_id represented_country_geoname_id is_anonymous_proxy is_satellite_provider is_anycast; do
        if [[ -n "${GEONAME_IDS[$geoname_id]}" ]]; then
            sudo ipset add $IPSET_NAME_IPV4 $network
        fi
    done < <(tail -n +2 $BLOCKS_IPV4_DB)

    while IFS=',' read -r network geoname_id registered_country_geoname_id represented_country_geoname_id is_anonymous_proxy is_satellite_provider is_anycast; do
        if [[ -n "${GEONAME_IDS[$geoname_id]}" ]]; then
            sudo ipset add $IPSET_NAME_IPV6 $network
        fi
    done < <(tail -n +2 $BLOCKS_IPV6_DB)
else
    # Fallback to ipdeny.com for each country
    for COUNTRY_CODE in "${COUNTRY_CODES[@]}"; do
        wget -O /tmp/${COUNTRY_CODE,,}.zone http://www.ipdeny.com/ipblocks/data/countries/${COUNTRY_CODE,,}.zone
        for ip in $(cat /tmp/${COUNTRY_CODE,,}.zone); do
            sudo ipset add $IPSET_NAME_IPV4 $ip
        done
        rm /tmp/${COUNTRY_CODE,,}.zone
    done
fi

# Create new iptables chains
sudo iptables -N $IPTABLES_CHAIN_IPV4
sudo ip6tables -N $IPTABLES_CHAIN_IPV6

# Add rules to allow traffic from the IP ranges in the ipsets
sudo iptables -A $IPTABLES_CHAIN_IPV4 -m set --match-set $IPSET_NAME_IPV4 src -j ACCEPT
sudo ip6tables -A $IPTABLES_CHAIN_IPV6 -m set --match-set $IPSET_NAME_IPV6 src -j ACCEPT

# Allow incoming traffic from specific IP addresses (IPv4)
for ip in "${ALLOWED_IPS[@]}"
do
    iptables -A INPUT -s "$ip" -j ACCEPT
done

# Allow incoming traffic from specific IP addresses (IPv6)
for ip in "${ALLOWED_IPS_V6[@]}"
do
    ip6tables -A INPUT -s "$ip" -j ACCEPT
done

# Add rules to drop all other incoming traffic
sudo iptables -A $IPTABLES_CHAIN_IPV4 -j DROP
sudo ip6tables -A $IPTABLES_CHAIN_IPV6 -j DROP

# Apply the new chains to incoming connections on the INPUT chain
sudo iptables -A INPUT -j $IPTABLES_CHAIN_IPV4
sudo ip6tables -A INPUT -j $IPTABLES_CHAIN_IPV6

# Save the iptables rules
sudo iptables-save > /etc/iptables/rules.v4
sudo ip6tables-save > /etc/iptables/rules.v6

# Save the ipset rules
sudo ipset save > /etc/ipset.conf

echo "IPTables and IPSet rules have been configured to allow only incoming connections from specified countries and whitelisted IPs."
