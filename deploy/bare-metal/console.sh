#!/usr/bin/env bash
# Run `bin/console <args>` against the live remote release. Useful for
# one-off operations (plugin:list, cache:clear, custom data fixes).
#
# Usage:
#   ENV=production deploy/bare-metal/console.sh cache:clear
#   ENV=production deploy/bare-metal/console.sh plugin:list

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${REPO_ROOT}"

ENV="${ENV:-staging}"
. scripts/load-config.sh
# shellcheck disable=SC1090
. "deploy/bare-metal/env/${ENV}.env"

SSH_OPTS=(-p "${REMOTE_PORT:-22}" -i "${REMOTE_SSH_KEY/#\~/$HOME}" -t)
ssh "${SSH_OPTS[@]}" "${REMOTE_USER}@${REMOTE_HOST}" \
    "cd '${REMOTE_PATH}/current' && ${REMOTE_PHP_BIN} bin/console $*"
