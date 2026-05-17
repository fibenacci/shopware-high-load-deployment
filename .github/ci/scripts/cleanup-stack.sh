#!/usr/bin/env bash
# Idempotent — safe to run when nothing is up.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "${REPO_ROOT}"

docker compose -f .github/ci/compose.ci.yml down --remove-orphans 2>/dev/null || true
docker rm -f shopware-ci >/dev/null 2>&1 || true
