#!/usr/bin/env bash
# Fetch an anonymized DB dump from a remote Shopware instance.
#
# Profiles live in .fetch-dump.local.env (gitignored). Each profile is a set
# of <PROFILE_UPPER>_* env vars (SSH destination, DB connection). Passwords
# live in the same file — never committed.
#
# Connection security model:
#   1. SSH ControlMaster tunnel: localhost → remote DB via the SSH session.
#      No port exposure. Cleaned up unconditionally via EXIT trap.
#   2. shopware-cli is invoked from a temp dir whose .env carries DATABASE_URL.
#      The password is therefore NEVER on the command line — no `ps` leak.
#   3. Anonymisation is on by default. The user has to opt OUT with
#      ALLOW_UNANONYMIZED=1 (recorded in .fetch-dump-audit.log for GDPR).
#
# Reference for the underlying tool:
#   https://developer.shopware.com/docs/products/cli/project-commands/mysql-dump.html
#
# Usage:
#   make fetch-dump                          # interactive wizard
#   make fetch-dump PROFILE=staging
#   make fetch-dump PROFILE=prod ALLOW_UNANONYMIZED=1   # GDPR-loud override

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${ROOT_DIR}"

OUTPUT_FILE="${DUMP_OUTPUT:-dump.sql.gz}"
PROFILE="${PROFILE:-}"
ALLOW_UNANONYMIZED="${ALLOW_UNANONYMIZED:-0}"
PROFILE_FILE=".fetch-dump.local.env"
AUDIT_LOG=".fetch-dump-audit.log"

SSH_CONTROL_DIR=""
SSH_CONTROL_SOCKET=""
SSH_DESTINATION=""
TMP_WORKDIR=""

log()     { printf "\033[1;34m▶\033[0m %s\n" "$*"; }
success() { printf "\033[1;32m✓\033[0m %s\n" "$*"; }
warn()    { printf "\033[1;33m⚠\033[0m %s\n" "$*" >&2; }
fail()    { printf "\033[1;31m✗\033[0m %s\n" "$*" >&2; exit 1; }

cleanup() {
    if [ -n "${SSH_CONTROL_SOCKET}" ] && [ -n "${SSH_DESTINATION}" ]; then
        ssh -S "${SSH_CONTROL_SOCKET}" -O exit "${SSH_DESTINATION}" >/dev/null 2>&1 || true
    fi
    if [ -n "${SSH_CONTROL_DIR}" ]; then
        rm -rf "${SSH_CONTROL_DIR}" >/dev/null 2>&1 || true
    fi
    if [ -n "${TMP_WORKDIR}" ]; then
        rm -rf "${TMP_WORKDIR}" >/dev/null 2>&1 || true
    fi
}
trap cleanup EXIT INT TERM

ensure_tools() {
    command -v ssh          >/dev/null 2>&1 || fail "ssh is required."
    command -v nc           >/dev/null 2>&1 || fail "nc is required to wait for the tunnel."
    command -v shopware-cli >/dev/null 2>&1 || fail "shopware-cli is required. Install from https://sw-cli.fos.gg/"
    command -v python3      >/dev/null 2>&1 || fail "python3 is required (used for URL-encoding the DB password)."
}

find_free_local_port() {
    for port in $(seq 3307 3399); do
        nc -z 127.0.0.1 "${port}" >/dev/null 2>&1 || { printf "%s" "${port}"; return; }
    done
    fail "No free local port found in 3307-3399."
}

wait_for_tunnel() {
    local port="$1"
    for _ in $(seq 1 30); do
        nc -z 127.0.0.1 "${port}" >/dev/null 2>&1 && return 0
        sleep 1
    done
    return 1
}

prompt()        { local v; read -r -p "$1 [${2:-}]: " v; printf "%s" "${v:-$2}"; }
prompt_secret() { local v; read -r -s -p "$1: " v; printf "\n" >&2; printf "%s" "$v"; }

load_profile() {
    if [ -z "${PROFILE}" ]; then
        return
    fi
    if [ ! -f "${PROFILE_FILE}" ]; then
        fail "PROFILE=${PROFILE} given but ${PROFILE_FILE} missing — copy ${PROFILE_FILE}.example first."
    fi

    set -a
    # shellcheck source=/dev/null
    . "./${PROFILE_FILE}"
    set +a

    local up
    up="$(printf "%s" "${PROFILE}" | tr '[:lower:]-' '[:upper:]_')"

    local ssh_dest_var="${up}_SSH_DEST"
    local ssh_port_var="${up}_SSH_PORT"
    local db_host_var="${up}_DB_HOST"
    local db_port_var="${up}_DB_PORT"
    local db_name_var="${up}_DB_NAME"
    local db_user_var="${up}_DB_USER"
    local db_pass_var="${up}_DB_PASSWORD"

    SSH_DESTINATION="${!ssh_dest_var:-}"
    SSH_PORT="${!ssh_port_var:-22}"
    REMOTE_DB_HOST="${!db_host_var:-127.0.0.1}"
    REMOTE_DB_PORT="${!db_port_var:-3306}"
    DB_NAME="${!db_name_var:-}"
    DB_USER="${!db_user_var:-}"
    DB_PASSWORD="${!db_pass_var:-}"

    [ -n "${SSH_DESTINATION}" ] || fail "Profile '${PROFILE}' missing ${ssh_dest_var}"
    [ -n "${DB_NAME}" ]         || fail "Profile '${PROFILE}' missing ${db_name_var}"
    [ -n "${DB_USER}" ]         || fail "Profile '${PROFILE}' missing ${db_user_var}"
    [ -n "${DB_PASSWORD}" ]     || fail "Profile '${PROFILE}' missing ${db_pass_var}"

    log "Loaded profile: ${PROFILE} (ssh=${SSH_DESTINATION}, db=${DB_NAME}@${REMOTE_DB_HOST}:${REMOTE_DB_PORT})"
}

interactive_wizard() {
    log "No PROFILE set — interactive wizard. Set PROFILE=<name> next time to skip."
    SSH_DESTINATION="$(prompt "SSH destination (user@host)" "${DUMP_SSH_DESTINATION:-}")"
    [ -n "${SSH_DESTINATION}" ] || fail "SSH destination is required."
    SSH_PORT="$(prompt "SSH port" "22")"
    REMOTE_DB_HOST="$(prompt "Remote DB host" "127.0.0.1")"
    REMOTE_DB_PORT="$(prompt "Remote DB port" "3306")"
    DB_NAME="$(prompt "Database name" "shopware")"
    DB_USER="$(prompt "Database user" "")"
    [ -n "${DB_USER}" ] || fail "Database user is required."
    DB_PASSWORD="$(prompt_secret "Database password")"
    [ -n "${DB_PASSWORD}" ] || fail "Database password is required."
}

write_audit() {
    local ts who
    ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    who="${USER:-unknown}@$(hostname -s 2>/dev/null || echo unknown)"
    printf "%s\t%s\tprofile=%s\tdest=%s\tdb=%s\tanon=%s\n" \
        "${ts}" "${who}" "${PROFILE:-interactive}" "${SSH_DESTINATION}" "${DB_NAME}" \
        "$( [ "${ALLOW_UNANONYMIZED}" = "1" ] && echo "OFF" || echo "ON" )" \
        >> "${AUDIT_LOG}"
}

main() {
    ensure_tools

    if [ -n "${PROFILE}" ]; then
        load_profile
    else
        interactive_wizard
    fi

    local anon_flag="--anonymize"
    if [ "${ALLOW_UNANONYMIZED}" = "1" ]; then
        warn "ALLOW_UNANONYMIZED=1 — dump will contain raw PII."
        warn "This is logged to ${AUDIT_LOG}. Ensure you have a GDPR-compliant reason."
        printf "Type 'yes' to confirm: "
        read -r confirm
        [ "${confirm}" = "yes" ] || fail "Aborted."
        anon_flag=""
    fi

    if [ -f "${OUTPUT_FILE}" ] && [ "${FORCE_OVERWRITE:-0}" != "1" ]; then
        printf "Overwrite %s? [y/N]: " "${OUTPUT_FILE}"
        read -r yn
        case "${yn}" in y|Y|yes|YES) rm -f "${OUTPUT_FILE}";; *) fail "${OUTPUT_FILE} exists.";; esac
    fi

    local local_port
    local_port="$(find_free_local_port)"
    SSH_CONTROL_DIR="$(mktemp -d "${TMPDIR:-/tmp}/shopware-dump-XXXXXX")"
    SSH_CONTROL_SOCKET="${SSH_CONTROL_DIR}/ctrl.sock"

    log "Opening SSH tunnel 127.0.0.1:${local_port} → ${REMOTE_DB_HOST}:${REMOTE_DB_PORT} via ${SSH_DESTINATION}"
    ssh -f -N -M -S "${SSH_CONTROL_SOCKET}" \
        -p "${SSH_PORT}" \
        -L "${local_port}:${REMOTE_DB_HOST}:${REMOTE_DB_PORT}" \
        "${SSH_DESTINATION}"
    wait_for_tunnel "${local_port}" \
        || fail "Tunnel did not become reachable on 127.0.0.1:${local_port}."
    success "Tunnel up"

    # Throw-away workdir holds a .env with DATABASE_URL. shopware-cli reads
    # it automatically (Symfony convention), so the password never appears
    # on the command line.
    TMP_WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/shopware-dump-cwd-XXXXXX")"
    cp .shopware-project.yml "${TMP_WORKDIR}/.shopware-project.yml" 2>/dev/null || true
    {
        printf 'DATABASE_URL=mysql://%s:%s@127.0.0.1:%s/%s\n' \
            "${DB_USER}" \
            "$(printf '%s' "${DB_PASSWORD}" | python3 -c 'import sys,urllib.parse;print(urllib.parse.quote(sys.stdin.read(),safe=""))')" \
            "${local_port}" \
            "${DB_NAME}"
    } > "${TMP_WORKDIR}/.env"
    chmod 600 "${TMP_WORKDIR}/.env"

    log "Running shopware-cli project dump (${anon_flag:-no-anonymize})"
    (
        cd "${TMP_WORKDIR}"
        # shellcheck disable=SC2086
        shopware-cli project dump \
            ${anon_flag} \
            --clean \
            --skip-lock-tables \
            --compression=gzip
    )

    local produced
    produced="$(find "${TMP_WORKDIR}" -maxdepth 1 -type f -name 'dump.sql*' -print -quit)"
    [ -n "${produced}" ] || fail "shopware-cli did not produce a dump file."
    mv -f "${produced}" "${OUTPUT_FILE}"

    write_audit
    success "Dump written: ${OUTPUT_FILE} ($(du -h "${OUTPUT_FILE}" | cut -f1))"
}

main "$@"
