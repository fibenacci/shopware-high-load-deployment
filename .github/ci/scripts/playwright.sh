#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <e2e-dir>" >&2
    exit 2
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
E2E_DIR="${REPO_ROOT}/${1#./}"

if [ ! -f "${E2E_DIR}/package.json" ]; then
    echo "::error::No package.json in ${E2E_DIR}" >&2
    exit 1
fi

STOREFRONT_PORT="${STOREFRONT_PORT:-8080}"
STOREFRONT_HOST_DEFAULT="localhost"
[ "${ACT:-}" = "true" ] && STOREFRONT_HOST_DEFAULT="host.docker.internal"
BASE_URL="${BASE_URL:-http://${STOREFRONT_HOST_DEFAULT}:${STOREFRONT_PORT}}"

cd "${E2E_DIR}"

echo "▶ Installing Playwright deps in ${E2E_DIR}"
if [ -f package-lock.json ]; then
    npm ci
else
    npm install --no-audit --no-fund
fi

echo "▶ Installing Chromium"
npx playwright install --with-deps chromium

echo "▶ Running Playwright (BASE_URL=${BASE_URL})"
BASE_URL="${BASE_URL}" npx playwright test
