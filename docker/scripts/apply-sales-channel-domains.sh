#!/usr/bin/env bash
# Apply sales-channel hostnames from a key=value mapping file.
#
# Exit codes:
#   0   mappings applied
#   10  mapping file missing or empty (caller should fall back to default URL)
#   11  parse error
#
# Format of the mapping file:
#   <sales-channel-name-or-id>=<scheme>://<hostname>
# Lines starting with `#` and empty lines are ignored.

set -euo pipefail

MAPPING_FILE="${1:-/var/www/html/sales-channel-hosts.local.map}"
FORCE_HTTP="${FORCE_HTTP:-1}"

if [ ! -s "${MAPPING_FILE}" ]; then
    exit 10
fi

# Strip comments + blanks
mapfile -t lines < <(grep -vE '^\s*(#|$)' "${MAPPING_FILE}" || true)
if [ "${#lines[@]}" -eq 0 ]; then
    exit 10
fi

cd /var/www/html

for line in "${lines[@]}"; do
    key="${line%%=*}"
    url="${line#*=}"
    if [ -z "${key}" ] || [ -z "${url}" ]; then
        echo "::error::Invalid mapping line: ${line}"
        exit 11
    fi

    if [ "${FORCE_HTTP}" = "1" ]; then
        url="${url/https:/http:}"
    fi

    # Resolve key → sales-channel id. Match by id first, then by name.
    if [[ "${key}" =~ ^[0-9a-f]{32}$ ]]; then
        sc_id="${key}"
    else
        sc_id=$(mysql -hmariadb -uroot -p"${MYSQL_ROOT_PASSWORD:-root}" shopware -N -B -e \
            "SELECT LOWER(HEX(sc.id)) FROM sales_channel sc
             LEFT JOIN sales_channel_translation sct ON sct.sales_channel_id = sc.id
             WHERE sct.name = '${key}' LIMIT 1;" 2>/dev/null || true)
    fi

    if [ -z "${sc_id}" ]; then
        echo "::warning::Sales channel '${key}' not found, skipping."
        continue
    fi

    mysql -hmariadb -uroot -p"${MYSQL_ROOT_PASSWORD:-root}" shopware -e \
        "UPDATE sales_channel_domain
            SET url = '${url}'
          WHERE sales_channel_id = UNHEX('${sc_id}')
          LIMIT 1;"
    echo "✓ ${key} → ${url}"
done
