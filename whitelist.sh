#!/bin/bash

# List of country ISO codes to allow (space-separated)
COUNTRY_CODES=("US" "CA")

# Specify the IP addresses you want to allow (IPv4)
ALLOWED_IPS=("192.168.1.100" "192.168.1.101")

# Specify the IP addresses you want to allow (IPv6)
ALLOWED_IPS_V6=("2001:db8::1" "2001:db8::2")

# Allowed ports from any IP
ALLOWED_PORTS=("22" "80" "443")

# Paths to MaxMind DB files
LOCATIONS_DB="GeoLite2-Country-Locations-en.csv"
BLOCKS_IPV4_DB="GeoLite2-Country-Blocks-IPv4.csv"
BLOCKS_IPV6_DB="GeoLite2-Country-Blocks-IPv6.csv"

# Names for the ipset and iptables chains
IPSET_NAME_IPV4="allowed_country_ips_ipv4"
IPSET_NAME_IPV6="allowed_country_ips_ipv6"
IPTABLES_CHAIN_IPV4="ALLOW_COUNTRY_IPV4"
IPTABLES_CHAIN_IPV6="ALLOW_COUNTRY_IPV6"

# Backup directory for iptables rules
BACKUP_DIR="/etc/iptables/backup"

# Check for required files
FILES_MISSING=false
if [[ ! -f $LOCATIONS_DB || ! -f $BLOCKS_IPV4_DB || ! -f $BLOCKS_IPV6_DB ]]; then
    FILES_MISSING=true
    echo "Required GeoLite2 database files are missing. Falling back to ipdeny.com."
fi

# Install necessary tools if not already installed (Ubuntu/Debian example)
echo "Checking necessary tools and install when needed."
INSTALL=false
PACKAGE=""
if ! command -v ipset &> /dev/null; then
    INSTALL=true
    PACKAGE="${PACKAGE} ipset"
fi

if ! command -v netfilter-persistent &> /dev/null; then
    INSTALL=true
    PACKAGE="${PACKAGE} netfilter-persistent"
fi

if ! command -v iptables &> /dev/null; then
    INSTALL=true
    PACKAGE="${PACKAGE} iptables"
fi

if ! command -v ip6tables &> /dev/null; then
    INSTALL=true
    PACKAGE="${PACKAGE} iptables"
fi

if ! command -v iptables-persistent &> /dev/null; then
    INSTALL=true
    PACKAGE="${PACKAGE} iptables-persistent"
fi

if ! command -v wget &> /dev/null; then
    INSTALL=true
    PACKAGE="${PACKAGE} wget"
fi

if [ "$INSTALL" = true ]; then
    echo "Installing missing packages: $PACKAGE"
    sudo apt-get update
    sudo apt-get install -y $PACKAGE
fi

# Backup current iptables rules
echo "Backing up current iptables rules."
TIMESTAMP=$(date +"%Y%m%d%H%M%S")
sudo mkdir -p $BACKUP_DIR
sudo iptables-save > $BACKUP_DIR/rules.v4.$TIMESTAMP
sudo ip6tables-save > $BACKUP_DIR/rules.v6.$TIMESTAMP
echo "Backup saved at $BACKUP_DIR/rules.v4.$TIMESTAMP and $BACKUP_DIR/rules.v6.$TIMESTAMP"

# Check if the ipsets already exist and destroy them if they do
echo "Checking and destroying existing ipsets."
if sudo ipset list $IPSET_NAME_IPV4 &> /dev/null; then
    sudo ipset destroy $IPSET_NAME_IPV4
fi
if sudo ipset list $IPSET_NAME_IPV6 &> /dev/null; then
    sudo ipset destroy $IPSET_NAME_IPV6
fi

# Create new ipsets
echo "Creating new ipsets."
sudo ipset create $IPSET_NAME_IPV4 hash:net
sudo ipset create $IPSET_NAME_IPV6 hash:net family inet6

# Flush the ipsets (remove all existing entries)
echo "Flushing ipsets."
sudo ipset flush $IPSET_NAME_IPV4
sudo ipset flush $IPSET_NAME_IPV6

# Process country codes if not empty
if [ ${#COUNTRY_CODES[@]} -gt 0 ]; then
    if [ "$FILES_MISSING" = false ]; then
        echo "Processing country codes from GeoIP files."
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
        echo "Falling back to ipdeny.com to download IP blocks."
        for COUNTRY_CODE in "${COUNTRY_CODES[@]}"; do
            wget -O /tmp/${COUNTRY_CODE,,}.zone http://www.ipdeny.com/ipblocks/data/countries/${COUNTRY_CODE,,}.zone
            for ip in $(cat /tmp/${COUNTRY_CODE,,}.zone); do
                sudo ipset add $IPSET_NAME_IPV4 $ip
            done
            rm /tmp/${COUNTRY_CODE,,}.zone
        done
    fi
fi

# Flush existing iptables rules
echo "Flushing existing iptables rules."
iptables -F
iptables -X
ip6tables -F
ip6tables -X

# Default policy to drop all incoming traffic except outbound
echo "Setting default policy to drop all incoming traffic."
iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT ACCEPT
ip6tables -P INPUT DROP
ip6tables -P FORWARD DROP
ip6tables -P OUTPUT ACCEPT

# Create new iptables chains
echo "Creating new iptables chains."
sudo iptables -N $IPTABLES_CHAIN_IPV4
sudo ip6tables -N $IPTABLES_CHAIN_IPV6

# Allow loopback interface (localhost)
echo "Allowing loopback interface (localhost)."
iptables -A INPUT -i lo -j ACCEPT
ip6tables -A INPUT -i lo -j ACCEPT

# Allow established and related incoming connections
echo "Allowing established and related incoming connections."
iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
ip6tables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

# Allow IPv6 ICMP for network reachability
echo "Allowing IPv6 ICMP for network reachability."
ip6tables -A INPUT -p icmpv6 -j ACCEPT

# Allow incoming traffic from specific IP addresses if ALLOWED_IPS is not empty
if [ ${#ALLOWED_IPS[@]} -gt 0 ]; then
    echo "Allowing incoming traffic from specific IPv4 addresses."
    for ip in "${ALLOWED_IPS[@]}"
    do
        iptables -A INPUT -s "$ip" -j ACCEPT
    done
fi

# Allow incoming traffic from specific IPv6 addresses if ALLOWED_IPS_V6 is not empty
if [ ${#ALLOWED_IPS_V6[@]} -gt 0 ]; then
    echo "Allowing incoming traffic from specific IPv6 addresses."
    for ip in "${ALLOWED_IPS_V6[@]}"
    do
        ip6tables -A INPUT -s "$ip" -j ACCEPT
    done
fi

# Allow incoming traffic on specified ports from any IP if ALLOWED_PORTS is not empty
if [ ${#ALLOWED_PORTS[@]} -gt 0 ]; then
    echo "Allowing incoming traffic on specified ports from any IP."
    for port in "${ALLOWED_PORTS[@]}"
    do
        iptables -A INPUT -p tcp --dport "$port" -j ACCEPT
        ip6tables -A INPUT -p tcp --dport "$port" -j ACCEPT
    done
fi

# Add rules to allow traffic from the IP ranges in the ipsets if COUNTRY_CODES is not empty
if [ ${#COUNTRY_CODES[@]} -gt 0 ]; then
    echo "Adding rules to allow traffic from the IP ranges in the ipsets."
    sudo iptables -A $IPTABLES_CHAIN_IPV4 -m set --match-set $IPSET_NAME_IPV4 src -j ACCEPT
    sudo ip6tables -A $IPTABLES_CHAIN_IPV6 -m set --match-set $IPSET_NAME_IPV6 src -j ACCEPT
fi

# Apply the new chains to incoming connections on the INPUT chain
echo "Applying the new iptables chains to incoming connections."
sudo iptables -A INPUT -j $IPTABLES_CHAIN_IPV4
sudo ip6tables -A INPUT -j $IPTABLES_CHAIN_IPV6

# Create directory if it doesn't exist
echo "Creating directory for saving iptables rules if it doesn't exist."
sudo mkdir -p /etc/iptables

# Save the iptables rules
echo "Saving the iptables rules."
sudo iptables-save > /etc/iptables/rules.v4
sudo ip6tables-save > /etc/iptables/rules.v6

# Save the ipset rules
echo "Saving the ipset rules."
sudo ipset save > /etc/ipset.conf

# If netfilter-persistent is installed, reload the rules
if command -v netfilter-persistent &> /dev/null; then
    echo "Reloading the iptables rules using netfilter-persistent."
    sudo netfilter-persistent save
    sudo netfilter-persistent reload
fi

# Check if the ipset restore service already exists
if [ ! -f /etc/systemd/system/ipset-restore.service ]; then
    # Create ipset restore service
    echo "Creating a systemd service to restore ipset rules at startup."
    cat << EOF | sudo tee /etc/systemd/system/ipset-restore.service
[Unit]
Description=Restore ipset rules
Before=netfilter-persistent.service

[Service]
Type=oneshot
ExecStart=/sbin/ipset restore -f /etc/ipset.conf

[Install]
WantedBy=multi-user.target
EOF

    # Enable and start the ipset restore service
    echo "Enabling and starting the ipset restore service."
    sudo systemctl enable ipset-restore.service
    sudo systemctl start ipset-restore.service
fi

echo "IPTables and IPSet rules have been configured to allow only incoming connections from specified countries, whitelisted IPs, and specified ports from any IP."
