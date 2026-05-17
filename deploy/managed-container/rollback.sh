#!/usr/bin/env bash
# Roll the managed-container deploy back to the previous known-good tag.
#
# The deploy.sh script records each successful deploy at
# ~/.shopware-deploy/<env>/last-good-tag (with the prior generation kept
# at .prev). This script reads .prev, pins IMAGE_TAG, and re-invokes deploy.sh.
#
# Usage:
#   ENV=production deploy/managed-container/rollback.sh                # → previous tag
#   ENV=production deploy/managed-container/rollback.sh abc1234         # → explicit

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${REPO_ROOT}"

ENV="${ENV:-production}"
. scripts/load-config.sh
# shellcheck disable=SC1090
. "deploy/managed-container/env/${ENV}.env"

SSH_OPTS=(-p "${REMOTE_PORT:-22}" -i "${REMOTE_SSH_KEY/#\~/$HOME}")
TARGET="${REMOTE_USER}@${REMOTE_HOST}"
EXPLICIT="${1:-}"

if [ -n "${EXPLICIT}" ]; then
    ROLLBACK_TAG="${EXPLICIT}"
else
    ROLLBACK_TAG=$(ssh "${SSH_OPTS[@]}" "${TARGET}" \
        "cat \${HOME:-/root}/.shopware-deploy/${ENV}/last-good-tag.prev 2>/dev/null || true")
fi

if [ -z "${ROLLBACK_TAG}" ]; then
    echo "::error::No previous tag recorded — pass one explicitly: rollback.sh <tag>" >&2
    exit 1
fi

printf "\033[1;33m▶\033[0m Rolling %s back to image tag: %s\n" "${ENV}" "${ROLLBACK_TAG}"
ENV="${ENV}" IMAGE_TAG="${ROLLBACK_TAG}" \
    "${REPO_ROOT}/deploy/managed-container/deploy.sh"
