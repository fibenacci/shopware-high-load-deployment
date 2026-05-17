#!/usr/bin/env bash
# Bare-metal Shopware deploy — FALLBACK PATH.
#
# The canonical bare-metal deploy is Deployer + shopware/deployment-helper,
# entry point at /deploy.php in the repo root:
#
#   vendor/bin/dep deploy env=staging
#
# That uses the same SSH-target file (deploy/bare-metal/env/<env>.env) as
# this script, and calls `vendor/bin/shopware-deployment-helper run` under
# the hood to handle plugins / migrations / theme compile / one-time tasks.
#
# This shell-only script is the FALLBACK for hosts where:
#   • Deployer can't run on the CI/dev machine (no PHP available)
#   • The remote doesn't have composer installed
#   • You want to inspect every shell step explicitly without indirection
#
# It still calls `shopware-deployment-helper run` on the remote whenever the
# tool is available — only the SSH/rsync orchestration differs.
#
# Usage:
#   ENV=staging deploy/bare-metal/deploy.sh
#   ENV=production REVISION=v1.4.2 deploy/bare-metal/deploy.sh
#
# Reads:
#   deployment.config                  global versions + mode
#   deploy/bare-metal/env/$ENV.env     SSH target, remote paths, shared dirs

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${REPO_ROOT}"

ENV="${ENV:-staging}"
REVISION="${REVISION:-$(git rev-parse HEAD)}"
STAMP="$(date -u +%Y%m%d-%H%M%S)-${REVISION:0:7}"

# shellcheck source=../../scripts/load-config.sh
. scripts/load-config.sh

ENV_FILE="deploy/bare-metal/env/${ENV}.env"
if [ ! -f "${ENV_FILE}" ]; then
    echo "::error::No env file at ${ENV_FILE} — copy from example.env first" >&2
    exit 1
fi
# shellcheck disable=SC1090
. "${ENV_FILE}"

SSH_OPTS=(-p "${REMOTE_PORT:-22}" -i "${REMOTE_SSH_KEY/#\~/$HOME}" -o StrictHostKeyChecking=accept-new)
RSYNC_SSH="ssh ${SSH_OPTS[*]}"
TARGET="${REMOTE_USER}@${REMOTE_HOST}"

step()    { printf "\n\033[1;34m▶\033[0m \033[1m%s\033[0m\n" "$1"; }
success() { printf "\033[1;32m✓\033[0m %s\n" "$1"; }
fail()    { printf "\033[1;31m✗\033[0m %s\n" "$1" >&2; }

# ---------------------------------------------------------------------------
# Pre-flight
# ---------------------------------------------------------------------------
step "Pre-flight checks"

ssh "${SSH_OPTS[@]}" "${TARGET}" "true" 2>/dev/null \
    || { fail "SSH to ${TARGET} failed"; exit 2; }
success "SSH reachable"

remote_php=$(ssh "${SSH_OPTS[@]}" "${TARGET}" "${REMOTE_PHP_BIN} -r 'echo PHP_MAJOR_VERSION . \".\" . PHP_MINOR_VERSION;'" 2>/dev/null || echo "?")
if [ "${remote_php}" != "${PHP_VERSION}" ]; then
    fail "Remote PHP is ${remote_php}, deployment.config wants ${PHP_VERSION}"
    exit 2
fi
success "Remote PHP ${remote_php} matches deployment.config"

ssh "${SSH_OPTS[@]}" "${TARGET}" \
    "test -d '${REMOTE_PATH}/shared' || mkdir -p '${REMOTE_PATH}/shared'"
ssh "${SSH_OPTS[@]}" "${TARGET}" \
    "test -d '${REMOTE_PATH}/releases' || mkdir -p '${REMOTE_PATH}/releases'"

# Lay down the empty shared/ skeleton on the very first deploy.
for dir in ${SHARED_DIRS}; do
    ssh "${SSH_OPTS[@]}" "${TARGET}" "mkdir -p '${REMOTE_PATH}/shared/${dir}'"
done

success "Pre-flight OK"

# ---------------------------------------------------------------------------
# Build (locally / on the runner)
# ---------------------------------------------------------------------------
step "Build release ${STAMP}"

BUILD_DIR="$(mktemp -d -t shopware-build-XXXX)"
trap 'rm -rf "${BUILD_DIR}"' EXIT

git archive --format=tar "${REVISION}" | tar -x -C "${BUILD_DIR}"

(
    cd "${BUILD_DIR}"
    if [ -f "${REPO_ROOT}/auth.json" ]; then
        cp "${REPO_ROOT}/auth.json" auth.json
    fi
    composer install --no-dev --optimize-autoloader --no-interaction --prefer-dist --no-scripts
    [ -f auth.json ] && rm auth.json
)

success "Vendor dir built ($(du -sh "${BUILD_DIR}/vendor" | cut -f1))"

# Per-plugin composer install (mirrors UGG's deploy step).
TARGET_PLUGINS="${TARGET_PLUGINS:-}"
if [ -n "${TARGET_PLUGINS}" ]; then
    for plugin in ${TARGET_PLUGINS}; do
        dir="${BUILD_DIR}/custom/plugins/${plugin}"
        if [ -d "${dir}" ] && [ -f "${dir}/composer.json" ]; then
            (cd "${dir}" && composer install --no-dev --optimize-autoloader --no-interaction --no-scripts)
        fi
    done
fi

# ---------------------------------------------------------------------------
# Sync release to remote
# ---------------------------------------------------------------------------
step "rsync to ${REMOTE_PATH}/releases/${STAMP}"

ssh "${SSH_OPTS[@]}" "${TARGET}" "mkdir -p '${REMOTE_PATH}/releases/${STAMP}'"

rsync -az --delete --checksum \
    -e "${RSYNC_SSH}" \
    --exclude-from="${REPO_ROOT}/.rsyncexclude" \
    --include='vendor/***' \
    --include='custom/plugins/*/vendor/***' \
    "${BUILD_DIR}/" \
    "${TARGET}:${REMOTE_PATH}/releases/${STAMP}/"

success "Release uploaded"

# ---------------------------------------------------------------------------
# Symlink shared/ into the release
# ---------------------------------------------------------------------------
step "Link shared paths into release"

ssh "${SSH_OPTS[@]}" "${TARGET}" bash -s <<EOF
    set -euo pipefail
    cd '${REMOTE_PATH}/releases/${STAMP}'
    for dir in ${SHARED_DIRS}; do
        rm -rf "\${dir}"
        mkdir -p "\$(dirname "\${dir}")"
        ln -nfs "${REMOTE_PATH}/shared/\${dir}" "\${dir}"
    done
    for file in ${SHARED_FILES}; do
        rm -f "\${file}"
        ln -nfs "${REMOTE_PATH}/shared/\${file}" "\${file}"
    done
EOF
success "Shared paths linked"

# ---------------------------------------------------------------------------
# Post-upload pipeline — single call to the official Shopware deployment-helper.
# Plugin install/activate/update, migrations, theme compile, asset install,
# one-time tasks, store login — all handled by the helper based on the
# .shopware-project.yml config in the release.
#
#   https://developer.shopware.com/docs/guides/hosting/installation-updates/deployments/deployment-helper.html
# ---------------------------------------------------------------------------
if [ "${SKIP_DEPLOYMENT_HELPER:-0}" != "1" ]; then
    step "shopware-deployment-helper run"
    ssh "${SSH_OPTS[@]}" "${TARGET}" bash -s <<EOF
        set -euo pipefail
        cd '${REMOTE_PATH}/releases/${STAMP}'
        touch install.lock
        if [ -x vendor/bin/shopware-deployment-helper ]; then
            ${REMOTE_PHP_BIN} vendor/bin/shopware-deployment-helper run
        else
            # Fallback for projects that haven't yet adopted the helper.
            ${REMOTE_PHP_BIN} bin/console database:migrate --all --no-interaction
            ${REMOTE_PHP_BIN} bin/console plugin:refresh --no-interaction
            ${REMOTE_PHP_BIN} bin/console assets:install --no-interaction
            ${REMOTE_PHP_BIN} bin/console theme:compile --no-interaction
            ${REMOTE_PHP_BIN} bin/console cache:clear --no-warmup --no-interaction
            ${REMOTE_PHP_BIN} bin/console cache:warmup --no-interaction
        fi
EOF
    success "Post-upload pipeline OK"
fi

# ---------------------------------------------------------------------------
# Atomic symlink swap — point of no return
# ---------------------------------------------------------------------------
step "Atomic symlink swap"

ssh "${SSH_OPTS[@]}" "${TARGET}" bash -s <<EOF
    set -euo pipefail
    cd '${REMOTE_PATH}'
    # ln -s + mv -T is atomic on POSIX filesystems.
    ln -nfs 'releases/${STAMP}' 'current.new'
    mv -Tf 'current.new' 'current'
EOF
success "Live now: ${REMOTE_PATH}/current → releases/${STAMP}"

# ---------------------------------------------------------------------------
# Opcache flush + sanity
# ---------------------------------------------------------------------------
step "Flush opcache"

if [ "${NO_FPM_RELOAD:-0}" = "1" ]; then
    # Fallback for hosts without sudo: touch a file that opcache validates
    # (only works when opcache.validate_timestamps=1 on the remote).
    ssh "${SSH_OPTS[@]}" "${TARGET}" "touch '${REMOTE_PATH}/current/public/index.php'"
else
    ssh "${SSH_OPTS[@]}" "${TARGET}" "${REMOTE_FPM_RELOAD_CMD}"
fi
success "Opcache flushed"

# ---------------------------------------------------------------------------
# Smoke test
# ---------------------------------------------------------------------------
if [ -n "${PUBLIC_URL:-}" ]; then
    step "Smoke test ${PUBLIC_URL}"
    for i in $(seq 1 20); do
        code=$(curl -s -o /dev/null -w '%{http_code}' "${PUBLIC_URL}" || echo "000")
        if [ "${code}" = "200" ]; then
            success "Smoke test OK (HTTP 200)"
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
# Prune old releases
# ---------------------------------------------------------------------------
step "Prune old releases (keep ${RELEASES_TO_KEEP:-5})"

ssh "${SSH_OPTS[@]}" "${TARGET}" bash -s <<EOF
    set -euo pipefail
    cd '${REMOTE_PATH}/releases'
    keep=${RELEASES_TO_KEEP:-5}
    ls -1tr | head -n -"\${keep}" | xargs -r rm -rf
EOF
success "Prune complete"

echo
printf "\033[1;32m✅ Deployment to %s complete: %s\033[0m\n" "${ENV}" "${STAMP}"
