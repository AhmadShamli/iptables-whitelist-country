# iptables Whitelist by Country

This script configures `iptables` and `ip6tables` to allow incoming connections only from specified countries and whitelisted IP addresses. It uses MaxMind GeoLite2 databases or falls back to IPDeny.com if the databases are missing. The script supports both IPv4 and IPv6 addresses.

## Prerequisites

- `ipset`
- `iptables`
- `ip6tables`
- `wget`
- MaxMind GeoLite2 databases (`GeoLite2-Country-Locations-en.csv`, `GeoLite2-Country-Blocks-IPv4.csv`, `GeoLite2-Country-Blocks-IPv6.csv`)

Ensure the above tools are installed and the MaxMind GeoLite2 database files are in the current directory.

## Script Explanation

### Variables

- `COUNTRY_CODES`: List of country ISO codes to allow (space-separated). Example: `("US" "CA")`.
- `ALLOWED_IPS` and `ALLOWED_IPS_V6`: List of IP addresses (both IPv4 and IPv6) to whitelist (space-separated). Example: `("1.2.3.4" "5.6.7.8") ("2001:db8::1" "2001:db8::2")`.

### Paths to MaxMind DB Files

- `LOCATIONS_DB`: Path to `GeoLite2-Country-Locations-en.csv`.
- `BLOCKS_IPV4_DB`: Path to `GeoLite2-Country-Blocks-IPv4.csv`.
- `BLOCKS_IPV6_DB`: Path to `GeoLite2-Country-Blocks-IPv6.csv`.

### IPTables and IPSet Names

- `IPSET_NAME_IPV4`: Name for the IPv4 ipset.
- `IPSET_NAME_IPV6`: Name for the IPv6 ipset.
- `IPTABLES_CHAIN_IPV4`: Name for the IPv4 iptables chain.
- `IPTABLES_CHAIN_IPV6`: Name for the IPv6 iptables chain.

### Steps

1. **Check for Required Files:**
   - Checks if the required MaxMind GeoLite2 database files are present. If missing, it will fall back to using IPDeny.com.

2. **Install Necessary Tools:**
   - Installs `ipset`, `iptables`, `ip6tables`, and `wget` if they are not already installed.

3. **Create and Flush IP Sets:**
   - Creates new ipsets for allowed country IPs (both IPv4 and IPv6).
   - Flushes (clears) the ipsets to remove all existing entries.

4. **Load IP Ranges from MaxMind DB or IPDeny.com:**
   - Maps country ISO codes to geoname IDs.
   - Adds IP ranges to the ipsets based on geoname IDs from MaxMind databases.
   - If the MaxMind databases are missing, it downloads IP ranges from IPDeny.com and adds them to the ipsets.

5. **Create IPTables Chains:**
   - Creates new iptables chains for allowed country IPs (both IPv4 and IPv6).

6. **Allow Traffic from IP Ranges:**
   - Adds rules to allow traffic from the IP ranges in the ipsets.

7. **Whitelist Specific IP Addresses:**
   - Adds rules to allow traffic from whitelisted IP addresses (both IPv4 and IPv6).

8. **Drop All Other Incoming Traffic:**
   - Adds rules to drop all other incoming traffic.

9. **Apply Chains to Incoming Connections:**
   - Applies the new chains to incoming connections on the `INPUT` chain.

10. **Save the Rules:**
    - Saves the iptables rules.
    - Saves the ipset rules.

### Usage

1. Ensure the script has execute permissions:
    ```bash
    chmod +x whitelist.sh
    ```

2. Run the script with `sudo`:
    ```bash
    sudo ./whitelist.sh
    ```

### Notes

- Make sure to review and test the script in a safe environment before deploying it to production systems.
- Modify the `COUNTRY_CODES` and `WHITELISTED_IPS` arrays as per your requirements.

### Example

Here's an example of how to set the `COUNTRY_CODES` and `WHITELISTED_IPS` arrays in the script:

```bash
# List of country ISO codes to allow (space-separated)
COUNTRY_CODES=("US" "CA" "GB")

# Specify the IP addresses you want to allow (IPv4)
ALLOWED_IPS=("192.168.1.100" "192.168.1.101")

# Specify the IP addresses you want to allow (IPv6)
ALLOWED_IPS_V6=("2001:db8::1" "2001:db8::2")
