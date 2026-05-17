#!/usr/bin/env bash
# Local dev entrypoint, executed by `make up` once the container is healthy.
# Idempotent — re-runs skip the heavy steps using the .setup_complete and
# .db_imported sentinel files.

set -e

SETUP_FLAG="/var/www/html/.setup_complete"
DB_IMPORT_FLAG="/var/www/html/.db_imported"
DOMAIN="${VIRTUAL_HOST:-shop.docker}"
DOMAIN="${DOMAIN%%,*}"
DUMP_FILE="/dump.sql.gz"
DOMAIN_MAP="/var/www/html/sales-channel-hosts.local.map"

step()    { printf "\033[1;34m▶\033[0m %s\n" "$1"; }
success() { printf "\033[1;32m✓\033[0m %s\n" "$1"; }
warn()    { printf "\033[1;33m⚠\033[0m %s\n" "$1"; }
fail()    { printf "\033[1;31m✗\033[0m %s\n" "$1"; }

apply_domains() {
    set +e
    bash /apply-sales-channel-domains.sh "${DOMAIN_MAP}"
    status=$?
    set -e
    if [ "$status" = "10" ]; then
        warn "No sales-channel mapping found, falling back to http://${DOMAIN}"
        bin/console sales-channel:update:domain "${DOMAIN}" --no-interaction
    fi
}

step "Waiting for MariaDB"
for i in $(seq 1 30); do
    if mysql -hmariadb -uroot -p"${MYSQL_ROOT_PASSWORD:-root}" -e "SELECT 1" >/dev/null 2>&1; then
        success "MariaDB ready"; break
    fi
    sleep 2
done

cd /var/www/html

# --- Database bootstrap ---------------------------------------------------
# Self-healing logic: the schema state is the primary gate, NOT the
# .db_imported flag. The flag is informational — it tracks "we did the
# heavy work once" — but if the schema is empty (e.g. partial earlier run
# that touched the flag but never finished install), we re-bootstrap
# instead of silently skipping. Three paths in priority order:
#   1. schema present (table_count > 10)         → nothing to do
#   2. schema missing + dump.sql.gz exists       → import dump
#   3. schema missing + no dump                  → bin/console system:install
table_count=$(mysql -hmariadb -uroot -p"${MYSQL_ROOT_PASSWORD:-root}" shopware -N -e \
    "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'shopware';" 2>/dev/null || echo "0")

if [ "$table_count" -gt 10 ]; then
    success "Database already populated ($table_count tables) — skipping bootstrap"
    touch "$DB_IMPORT_FLAG"
elif [ -f "$DUMP_FILE" ]; then
    step "Schema missing — importing dump.sql.gz"
    mysql -hmariadb -uroot -p"${MYSQL_ROOT_PASSWORD:-root}" -e "DROP DATABASE IF EXISTS shopware;"
    mysql -hmariadb -uroot -p"${MYSQL_ROOT_PASSWORD:-root}" -e "CREATE DATABASE shopware CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
    gunzip < "$DUMP_FILE" | mysql -hmariadb -uroot -p"${MYSQL_ROOT_PASSWORD:-root}" shopware
    success "Database imported"
    touch "$DB_IMPORT_FLAG"
else
    step "Schema missing — running 'bin/console system:install --basic-setup'"
    bin/console system:install --create-database --basic-setup --force \
        --shop-locale="${INSTALL_LOCALE:-de-DE}" \
        --shop-currency="${INSTALL_CURRENCY:-EUR}"
    success "Shopware installed (admin: ${INSTALL_ADMIN_USERNAME:-admin} / ${INSTALL_ADMIN_PASSWORD:-shopware})"
    touch "$DB_IMPORT_FLAG"
fi

# --- One-time setup -------------------------------------------------------
if [ -f "$SETUP_FLAG" ]; then
    apply_domains
    bin/console cache:clear --quiet || true
    success "Setup already done — skipping heavy steps"
    exit 0
fi

step "composer install"
composer install --no-interaction --optimize-autoloader --quiet
success "Composer dependencies installed"

apply_domains

step "Admin user (${INSTALL_ADMIN_USERNAME:-admin})"
admin_user="${INSTALL_ADMIN_USERNAME:-admin}"
admin_pass="${INSTALL_ADMIN_PASSWORD:-shopware}"
admin_email="${INSTALL_ADMIN_EMAIL:-admin@localhost.local}"
bin/console user:create "${admin_user}" --admin --password="${admin_pass}" --email="${admin_email}" \
    --firstName=Admin --lastName=User 2>/dev/null \
    || bin/console user:change-password "${admin_user}" --password="${admin_pass}" 2>/dev/null \
    || true

step "Cache clear"
bin/console cache:clear --quiet

touch "$SETUP_FLAG"
success "Setup complete"
