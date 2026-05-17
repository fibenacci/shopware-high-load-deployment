#!/usr/bin/env bash
# Bring up the pre-baked CI image. The heavy lifting (composer install +
# plugin:install + theme:compile + CI drop-in) happens at IMAGE BUILD time,
# declared in .github/ci/Dockerfile. This script just builds the image
# (cached layer by layer) and starts the container.
#
# Inputs (env):
#   COMPOSER_AUTH    Optional locally (auth.json fallback). Required in CI.
#   STOREFRONT_PORT  Optional. Default: 8080.
#   STOREFRONT_HOST  Optional. Default: localhost (host.docker.internal under `act`).

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "${REPO_ROOT}"

export STOREFRONT_PORT="${STOREFRONT_PORT:-8080}"

# act runs Playwright inside the runner container; the CI container is a
# sibling on Docker Desktop and reachable via host.docker.internal.
STOREFRONT_HOST_DEFAULT="localhost"
[ "${ACT:-}" = "true" ] && STOREFRONT_HOST_DEFAULT="host.docker.internal"
STOREFRONT_HOST="${STOREFRONT_HOST:-${STOREFRONT_HOST_DEFAULT}}"

# Composer auth: CI sets COMPOSER_AUTH from secrets; locally fall back to
# auth.json in the repo root.
if [ -z "${COMPOSER_AUTH:-}" ]; then
    if [ -s auth.json ] && grep -q '"github-oauth"\|"bearer"' auth.json 2>/dev/null; then
        COMPOSER_AUTH="$(tr -d '\n' < auth.json)"
        export COMPOSER_AUTH
    else
        echo "::error::Need either \$COMPOSER_AUTH or a populated auth.json."
        exit 1
    fi
fi

"$(dirname "${BASH_SOURCE[0]}")/cleanup-stack.sh"

echo "▶ Building CI image"
docker compose -f .github/ci/compose.ci.yml build

echo "▶ Starting CI container"
docker compose -f .github/ci/compose.ci.yml up -d --wait

echo "▶ Pointing sales channels at http://${STOREFRONT_HOST}:${STOREFRONT_PORT}"
# Direct UPDATE on purpose: `sales-channel:update:domain` fires a DAL event
# that wakes the AdminSearchRegistry listener (compiled into the Dockware
# DI container), which then tries to talk to OpenSearch even when disabled.
# mysql bypasses Symfony entirely.
docker exec shopware-ci mysql -u root -proot shopware -e \
    "UPDATE sales_channel_domain
        SET url = CONCAT('http://${STOREFRONT_HOST}:${STOREFRONT_PORT}',
                         SUBSTRING(url, LOCATE('/', url, 8)))
      WHERE url LIKE 'http://%';"

docker exec shopware-ci bin/console cache:clear --no-warmup --no-interaction >/dev/null

echo "✅ Ready — storefront on http://${STOREFRONT_HOST}:${STOREFRONT_PORT}"
