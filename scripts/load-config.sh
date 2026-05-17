#!/usr/bin/env bash
# Source the global config and export every key into the calling shell.
# Resolves `${VAR}` substitutions so consumers don't need to.
#
# Use from a script:  . "$(dirname "$0")/../scripts/load-config.sh"
# Use from CI:        scripts/load-config.sh --github-env >> "$GITHUB_ENV"

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_FILE="${SHOPWARE_DEPLOYMENT_CONFIG:-${REPO_ROOT}/deployment.config}"

if [ ! -f "${CONFIG_FILE}" ]; then
    echo "::error::Missing ${CONFIG_FILE}" >&2
    return 1 2>/dev/null || exit 1
fi

# Sourcing a `KEY=${OTHER}` file requires `set -a` so the expansions resolve
# at read-time and the keys land in the environment.
set -a
# shellcheck disable=SC1090
. "${CONFIG_FILE}"
set +a

if [ "${1:-}" = "--github-env" ]; then
    # Emit lines suitable for `>> $GITHUB_ENV` in a GitHub Actions step.
    awk -F= '/^[A-Z_][A-Z0-9_]*=/ {print}' "${CONFIG_FILE}" | while IFS= read -r line; do
        key="${line%%=*}"
        # Use the *resolved* value from the environment, not the raw `${...}`
        # line from the file.
        printf '%s=%s\n' "${key}" "$(printenv "${key}" || true)"
    done
fi
