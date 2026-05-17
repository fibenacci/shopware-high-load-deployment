#!/usr/bin/env bash
# Render composer.json from composer.json.example using values from
# deployment.config. Single source of truth for Shopware + PHP version
# constraints — bumping deployment.config and re-running this script is
# the canonical way to bump dependency constraints.
#
# Placeholders in composer.json.example:
#   __SHOPWARE_VERSION__ ← full SHOPWARE_VERSION as exact pin (e.g. 6.6.5.1)
#                           Used for shopware/core, shopware/storefront, etc.
#                           Exact-pinning policy: patch bumps need a coordinated
#                           commit touching deployment.config + composer.json
#                           + Docker image. Loose constraints invite drift
#                           between the runtime image and what composer resolves.
#   __SHOPWARE_MINOR__   ← first two segments only (6.6.5.1 → 6.6)
#                           Used ONLY for `extra.symfony.require` — Symfony Flex
#                           recipes are minor-bound (no patch granularity).
#   __PHP_VERSION__      ← PHP_VERSION as-is (8.3)
#
# CHECK mode: `--check` exits non-zero if composer.json would change.
# Used by CI to catch deployment.config / composer.json drift.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${REPO_ROOT}"

TEMPLATE="composer.json.example"
TARGET="composer.json"
MODE="render"
[ "${1:-}" = "--check" ] && MODE="check"

[ -f "${TEMPLATE}" ] || { echo "::error::${TEMPLATE} missing"; exit 1; }

# Belt-and-suspenders: if compose.yaml previously bind-mounted composer.json
# while it was missing on the host, Docker auto-created an empty directory
# there. Remove it so we can write the rendered file. preflight does this
# too, but running the renderer standalone shouldn't trip on it.
if [ "${MODE}" = "render" ] && [ -d "${TARGET}" ] \
   && [ -z "$(ls -A "${TARGET}" 2>/dev/null)" ]; then
    echo "▶ removing leftover empty ${TARGET}/ directory (created by a failed compose up)"
    rmdir "${TARGET}"
fi

# shellcheck source=../scripts/load-config.sh
. "${REPO_ROOT}/scripts/load-config.sh"

# Derive constraint inputs.
shopware_minor="$(printf '%s' "${SHOPWARE_VERSION}" | cut -d. -f1-2)"
php_version="${PHP_VERSION}"

[ -n "${shopware_minor}" ] || { echo "::error::could not derive SHOPWARE_MINOR from SHOPWARE_VERSION=${SHOPWARE_VERSION}"; exit 1; }
[ -n "${php_version}" ]    || { echo "::error::PHP_VERSION missing in deployment.config"; exit 1; }

# Render in-memory; only write if changed.
rendered="$(
    sed -e "s|__SHOPWARE_VERSION__|${SHOPWARE_VERSION}|g" \
        -e "s|__SHOPWARE_MINOR__|${shopware_minor}|g" \
        -e "s|__PHP_VERSION__|${php_version}|g" \
        "${TEMPLATE}" \
    | grep -vE '^\s*"_'
)"
# Strip ALL underscore-prefixed keys (`_template`, `_comment_*`, …) — they
# are documentation for humans reading the source file. Composer would
# choke on `_comment_x: "Exact pin on purpose..."` because it tries to
# parse "Exact" as a version constraint. Underscore-prefixed package names
# aren't valid in composer (vendor/name format required), so this filter
# is safe — only template-internal metadata starts with `"_`.

if [ "${MODE}" = "check" ]; then
    if [ ! -f "${TARGET}" ]; then
        echo "::error::${TARGET} missing — run 'make composer-json' to render it from ${TEMPLATE}"
        exit 2
    fi
    if ! diff -u <(printf '%s\n' "${rendered}") "${TARGET}" >/dev/null 2>&1; then
        echo "::error::${TARGET} is out of sync with ${TEMPLATE} + deployment.config"
        echo ""
        diff -u "${TARGET}" <(printf '%s\n' "${rendered}") | head -40 || true
        echo ""
        echo "Fix: run 'make composer-json' and commit the result."
        exit 1
    fi
    echo "✓ ${TARGET} is in sync with ${TEMPLATE} (SHOPWARE=${SHOPWARE_VERSION}, PHP=${php_version})"
    exit 0
fi

# Render mode — write only if changed.
if [ -f "${TARGET}" ] && diff -q <(printf '%s\n' "${rendered}") "${TARGET}" >/dev/null 2>&1; then
    echo "✓ ${TARGET} already in sync (SHOPWARE=${SHOPWARE_VERSION}, PHP=${php_version})"
    exit 0
fi

printf '%s\n' "${rendered}" > "${TARGET}"
echo "✓ wrote ${TARGET} (SHOPWARE=${SHOPWARE_VERSION}, MINOR=${shopware_minor}, PHP=${php_version})"
echo ""
echo "  Next: 'composer update --lock' to refresh composer.lock if you bumped versions"
