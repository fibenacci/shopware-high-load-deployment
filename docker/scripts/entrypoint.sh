#!/usr/bin/env bash
# Production entrypoint. Same image, four roles selected via the CMD:
#
#   web        FrankenPHP / php-fpm front-end (default — base image handles it)
#   worker     bin/console messenger:consume loop
#   cron       bin/console scheduled-task:run (one-shot, k8s CronJob calls this)
#   migrate    shopware-deployment-helper run — DB migrations, plugin install,
#              theme compile, asset install, one-time tasks. Used by the
#              pre-deploy k8s Job and by Deployer's `sw:deployment:helper` task.
#   shell      drop into bash
#
# The deployment-helper is the canonical Shopware post-upload pipeline:
#   https://developer.shopware.com/docs/guides/hosting/installation-updates/deployments/deployment-helper.html

set -euo pipefail

ROLE="${1:-web}"
shift || true

cd /var/www/html

# Wait for DB on roles that touch it. The deployment-helper does its own
# wait, but workers and the web role boot faster if we gate here too.
case "${ROLE}" in
    web|worker|migrate)
        if [ -n "${DATABASE_URL:-}" ]; then
            php -r 'if (preg_match("|mysql://([^:]+):([^@]+)@([^:/]+):?(\d+)?|", getenv("DATABASE_URL"), $m)) { [$_, $u, $p, $h, $port] = $m + [4 => 3306]; for ($i = 0; $i < 60; $i++) { $c = @mysqli_connect($h, $u, $p, "", (int)$port); if ($c) { echo "✓ DB ready\n"; exit; } sleep(1); } fwrite(STDERR, "DB unreachable\n"); exit(2); }'
        fi
        ;;
esac

case "${ROLE}" in
    web)
        # FrankenPHP / FPM is the PID-1 in the Shopware base image. We
        # exec into its default entrypoint by passing control back to it.
        # The base sets `docker-entrypoint` on PATH.
        exec docker-entrypoint
        ;;
    worker)
        exec bin/console messenger:consume \
            ${MESSENGER_QUEUES:-async low_priority failed} \
            --time-limit="${MESSENGER_TIME_LIMIT:-3600}" \
            --memory-limit="${MESSENGER_MEMORY_LIMIT:-512M}" \
            -v
        ;;
    cron)
        bin/console scheduled-task:run --time-limit=300 -v
        exec bin/console messenger:consume scheduler_default \
            --time-limit=300 --memory-limit=256M -v
        ;;
    migrate)
        # The official Shopware deployment-helper handles the entire
        # post-upload pipeline (plugin install/activate/update, migrations,
        # theme compile, asset install, one-time tasks). Configured via
        # .shopware-project.yml at repo root.
        exec vendor/bin/shopware-deployment-helper run
        ;;
    shell)
        exec bash
        ;;
    *)
        echo "Unknown role: ${ROLE}" >&2
        exit 2
        ;;
esac
