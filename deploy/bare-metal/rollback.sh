#!/usr/bin/env bash
# Atomic rollback — flips `current` back to the previous release.
#
# Usage:
#   ENV=production deploy/bare-metal/rollback.sh           # → previous release
#   ENV=production deploy/bare-metal/rollback.sh 20260512-141055-abc1234  # → exact

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${REPO_ROOT}"

ENV="${ENV:-staging}"
. scripts/load-config.sh

ENV_FILE="deploy/bare-metal/env/${ENV}.env"
[ -f "${ENV_FILE}" ] || { echo "::error::Missing ${ENV_FILE}" >&2; exit 1; }
# shellcheck disable=SC1090
. "${ENV_FILE}"

SSH_OPTS=(-p "${REMOTE_PORT:-22}" -i "${REMOTE_SSH_KEY/#\~/$HOME}" -o StrictHostKeyChecking=accept-new)
TARGET="${REMOTE_USER}@${REMOTE_HOST}"
EXPLICIT_RELEASE="${1:-}"

# Resolve target release.
if [ -n "${EXPLICIT_RELEASE}" ]; then
    TARGET_RELEASE="${EXPLICIT_RELEASE}"
else
    TARGET_RELEASE=$(ssh "${SSH_OPTS[@]}" "${TARGET}" \
        "cd '${REMOTE_PATH}/releases' && ls -1tr | tail -2 | head -1" \
        2>/dev/null || true)
fi

if [ -z "${TARGET_RELEASE}" ]; then
    echo "::error::No previous release found — nothing to roll back to." >&2
    exit 1
fi

# Sanity-check the target exists.
ssh "${SSH_OPTS[@]}" "${TARGET}" \
    "test -d '${REMOTE_PATH}/releases/${TARGET_RELEASE}'" \
    || { echo "::error::Release ${TARGET_RELEASE} does not exist" >&2; exit 1; }

printf "\033[1;33m▶\033[0m Rolling %s back to release: %s\n" "${ENV}" "${TARGET_RELEASE}"

ssh "${SSH_OPTS[@]}" "${TARGET}" bash -s <<EOF
    set -euo pipefail
    cd '${REMOTE_PATH}'
    ln -nfs 'releases/${TARGET_RELEASE}' 'current.new'
    mv -Tf 'current.new' 'current'
EOF

# Flush opcache.
if [ "${NO_FPM_RELOAD:-0}" = "1" ]; then
    ssh "${SSH_OPTS[@]}" "${TARGET}" "touch '${REMOTE_PATH}/current/public/index.php'"
else
    ssh "${SSH_OPTS[@]}" "${TARGET}" "${REMOTE_FPM_RELOAD_CMD}"
fi

printf "\033[1;32m✓\033[0m Rolled back %s → %s\n" "${ENV}" "${TARGET_RELEASE}"

# Smoke test the URL if configured.
if [ -n "${PUBLIC_URL:-}" ]; then
    code=$(curl -s -o /dev/null -w '%{http_code}' "${PUBLIC_URL}" || echo "000")
    printf "Smoke test %s → HTTP %s\n" "${PUBLIC_URL}" "${code}"
fi
