#!/usr/bin/env bash
# Tear down the CI stack. Dumps recent logs first when called with --with-logs.
#
# Usage:
#   .github/ci/scripts/teardown.sh
#   .github/ci/scripts/teardown.sh --with-logs

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "${REPO_ROOT}"

if [ "${1:-}" = "--with-logs" ]; then
    echo "▶ Service status"
    docker compose -f .github/ci/compose.ci.yml ps || true
    echo "▶ Recent shopware logs"
    docker compose -f .github/ci/compose.ci.yml logs --tail=300 shopware || true
fi

"$(dirname "${BASH_SOURCE[0]}")/cleanup-stack.sh"
