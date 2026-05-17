#!/usr/bin/env bash
# Liveness target — works for both FrankenPHP (port 8000) and FPM-behind-nginx
# (port 8080). The base image picks one at build time and exports the port via
# the SERVER_PORT env var.

set -euo pipefail

PORT="${HEALTHCHECK_PORT:-${SERVER_PORT:-8000}}"
PATH_="${HEALTHCHECK_PATH:-/}"

curl -sf -o /dev/null -w '%{http_code}' "http://127.0.0.1:${PORT}${PATH_}" \
    | grep -qE '^(200|301|302)$'
