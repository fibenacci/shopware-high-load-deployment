#!/usr/bin/env bash
# Deploy to a managed-container host (TimmeHosting / Hetzner / generic VPS).
#
# Flow:
#   1. SSH to host, log in to GHCR if needed
#   2. `docker compose pull` — fetch the new image tag
#   3. Run `migrate` as a one-shot — shopware-deployment-helper run
#   4. `docker compose up -d --remove-orphans` — rolling restart of web/worker/cron
#   5. Smoke test the public URL
#   6. Save the new image tag as last-good for rollback
#
# Usage:
#   ENV=production deploy/managed-container/deploy.sh
#   ENV=production IMAGE_TAG=abc1234 deploy/managed-container/deploy.sh
#
# Reads:
#   deployment.config                          global versions + mode
#   deploy/managed-container/env/$ENV.env      SSH target, image tag, domain

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${REPO_ROOT}"

ENV="${ENV:-production}"

# shellcheck source=../../scripts/load-config.sh
. scripts/load-config.sh

ENV_FILE="deploy/managed-container/env/${ENV}.env"
if [ ! -f "${ENV_FILE}" ]; then
    echo "::error::No env file at ${ENV_FILE} — copy from example.env first" >&2
    exit 1
fi
# shellcheck disable=SC1090
. "${ENV_FILE}"

# Resolved image tag — CLI override wins.
IMAGE_TAG="${IMAGE_TAG:-stable}"

SSH_OPTS=(-p "${REMOTE_PORT:-22}" -i "${REMOTE_SSH_KEY/#\~/$HOME}" -o StrictHostKeyChecking=accept-new)
TARGET="${REMOTE_USER}@${REMOTE_HOST}"
REMOTE_DIR="${REMOTE_PATH}"

step()    { printf "\n\033[1;34m▶\033[0m \033[1m%s\033[0m\n" "$1"; }
success() { printf "\033[1;32m✓\033[0m %s\n" "$1"; }
fail()    { printf "\033[1;31m✗\033[0m %s\n" "$1" >&2; }

# ---------------------------------------------------------------------------
# Pre-flight
# ---------------------------------------------------------------------------
step "Pre-flight"
ssh "${SSH_OPTS[@]}" "${TARGET}" "command -v docker compose >/dev/null && command -v rsync >/dev/null" \
    || { fail "Remote lacks docker/compose/rsync"; exit 2; }
ssh "${SSH_OPTS[@]}" "${TARGET}" "mkdir -p '${REMOTE_DIR}/env' '${HOME:-/root}/.shopware-deploy/${ENV}'"
success "Remote ready"

# ---------------------------------------------------------------------------
# Ship compose + env to the remote.
# ---------------------------------------------------------------------------
step "Sync compose + env to ${REMOTE_DIR}"
rsync -az -e "ssh ${SSH_OPTS[*]}" \
    deploy/managed-container/compose.production.yaml \
    "${TARGET}:${REMOTE_DIR}/compose.yaml"
rsync -az -e "ssh ${SSH_OPTS[*]}" \
    "${ENV_FILE}" \
    "${TARGET}:${REMOTE_DIR}/env/${ENV}.env"
rsync -az -e "ssh ${SSH_OPTS[*]}" \
    deployment.config \
    "${TARGET}:${REMOTE_DIR}/deployment.config"
success "Compose files synced"

# ---------------------------------------------------------------------------
# GHCR login if credentials provided.
# ---------------------------------------------------------------------------
if [ -n "${GHCR_USER:-}" ] && [ -n "${GHCR_TOKEN:-}" ]; then
    step "Logging in to GHCR on the remote"
    ssh "${SSH_OPTS[@]}" "${TARGET}" \
        "echo '${GHCR_TOKEN}' | docker login ghcr.io -u '${GHCR_USER}' --password-stdin"
    success "GHCR login OK"
fi

# ---------------------------------------------------------------------------
# Pull new image — happens BEFORE the rollout so we can fail fast.
# ---------------------------------------------------------------------------
step "Pulling image tag: ${IMAGE_TAG}"
# Intentional client-side expansion of ${REMOTE_DIR}/${IMAGE_TAG}/${ENV}.
# shellcheck disable=SC2087
ssh "${SSH_OPTS[@]}" "${TARGET}" bash -s <<EOF
    set -euo pipefail
    cd '${REMOTE_DIR}'
    export IMAGE_TAG='${IMAGE_TAG}'
    export ENV='${ENV}'
    docker compose --env-file deployment.config --env-file env/${ENV}.env pull web worker cron
EOF
success "Image pulled"

# ---------------------------------------------------------------------------
# One-shot migration container BEFORE web restart.
# ---------------------------------------------------------------------------
step "Running shopware-deployment-helper (migrations + plugins + theme)"
# Intentional client-side expansion of ${REMOTE_DIR}/${IMAGE_TAG}/${ENV}.
# shellcheck disable=SC2087
ssh "${SSH_OPTS[@]}" "${TARGET}" bash -s <<EOF
    set -euo pipefail
    cd '${REMOTE_DIR}'
    export IMAGE_TAG='${IMAGE_TAG}'
    export ENV='${ENV}'
    docker compose --env-file deployment.config --env-file env/${ENV}.env \
        --profile deploy run --rm migrate
EOF
success "Migrations done"

# ---------------------------------------------------------------------------
# Rolling restart — `up -d` with the new tag in place. Compose's default
# stops + recreates one container at a time when no orchestration config is
# given. For zero-downtime web, the hoster's reverse proxy retries while
# the new container starts (healthcheck-gated by depends_on).
# ---------------------------------------------------------------------------
step "Rolling restart"
# Intentional client-side expansion of ${REMOTE_DIR}/${IMAGE_TAG}/${ENV}.
# shellcheck disable=SC2087
ssh "${SSH_OPTS[@]}" "${TARGET}" bash -s <<EOF
    set -euo pipefail
    cd '${REMOTE_DIR}'
    export IMAGE_TAG='${IMAGE_TAG}'
    export ENV='${ENV}'
    profile_args=""
    [ "\${STATEFUL:-}" = "stateful" ] && profile_args="--profile stateful"
    # shellcheck disable=SC2086
    docker compose --env-file deployment.config --env-file env/${ENV}.env \
        \$profile_args up -d --remove-orphans web worker cron
EOF
success "Containers up"

# ---------------------------------------------------------------------------
# Smoke test
# ---------------------------------------------------------------------------
if [ -n "${PUBLIC_URL:-}" ]; then
    step "Smoke test ${PUBLIC_URL}"
    for i in $(seq 1 20); do
        code=$(curl -s -o /dev/null -w '%{http_code}' "${PUBLIC_URL}" || echo "000")
        if [ "${code}" = "200" ] || [ "${code}" = "301" ] || [ "${code}" = "302" ]; then
            success "Smoke test OK (HTTP ${code})"
            break
        fi
        printf "  attempt %2d/20 → HTTP %s\n" "${i}" "${code}"
        sleep 3
        if [ "${i}" = "20" ]; then
            fail "Smoke test failed — last code ${code}. Run \`make rollback ENV=${ENV}\` if needed."
            exit 3
        fi
    done
fi

# ---------------------------------------------------------------------------
# Record last-good tag for rollback.
# ---------------------------------------------------------------------------
# Intentional client-side expansion of ${ENV}/${IMAGE_TAG}.
# shellcheck disable=SC2087
ssh "${SSH_OPTS[@]}" "${TARGET}" bash -s <<EOF
    set -euo pipefail
    mkdir -p "\${HOME:-/root}/.shopware-deploy/${ENV}"
    last_good="\${HOME:-/root}/.shopware-deploy/${ENV}/last-good-tag"
    if [ -f "\$last_good" ]; then
        cp "\$last_good" "\${last_good}.prev"
    fi
    echo '${IMAGE_TAG}' > "\$last_good"
EOF
success "Recorded last-good tag: ${IMAGE_TAG}"

echo
printf "\033[1;32m✅ Deployment to %s complete — image: %s\033[0m\n" "${ENV}" "${IMAGE_TAG}"
