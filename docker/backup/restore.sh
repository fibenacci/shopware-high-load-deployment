#!/usr/bin/env bash
# Restore a Shopware DB backup produced by the shopware-db-backup CronJob.
#
# Run from inside the backup image:
#   kubectl run restore -it --rm --image=ghcr.io/EXAMPLE/shopware-backup:latest \
#       --env-from=secretRef:shopware-secrets \
#       --env-from=secretRef:shopware-backup-secrets \
#       --command -- /restore.sh s3://shop-db-backups/staging/20260516-031722.sql.gz.enc
#
# Or locally — useful for spot-checking a backup against a fresh dev DB:
#   AWS_ACCESS_KEY_ID=...  AWS_SECRET_ACCESS_KEY=... \
#   BACKUP_PASSPHRASE=...  DATABASE_URL=mysql://root:root@127.0.0.1/restore_check \
#   ./restore.sh s3://shop-db-backups/staging/20260516-031722.sql.gz.enc

set -euo pipefail

SRC="${1:-}"
[ -z "${SRC}" ] && { echo "Usage: $0 <s3-url>" >&2; exit 2; }
[ -n "${DATABASE_URL:-}" ]      || { echo "DATABASE_URL required" >&2; exit 2; }
[ -n "${BACKUP_PASSPHRASE:-}" ] || { echo "BACKUP_PASSPHRASE required" >&2; exit 2; }

eval "$(echo "$DATABASE_URL" | \
    sed -nE 's|mysql://([^:]+):([^@]+)@([^:/]+):?([0-9]*)/([^?]+).*|user=\1 pass=\2 host=\3 port=\4 db=\5|p')"
: "${port:=3306}"

echo "▶ Restoring ${SRC} → ${user}@${host}:${port}/${db}"
echo "  (CTRL-C within 5 s to abort)"
sleep 5

aws s3 cp "${SRC}" /tmp/backup.enc \
    ${BACKUP_ENDPOINT:+--endpoint-url=$BACKUP_ENDPOINT}

openssl enc -aes-256-cbc -d -pbkdf2 -salt \
    -pass "env:BACKUP_PASSPHRASE" \
    -in /tmp/backup.enc \
| gunzip \
| MYSQL_PWD="$pass" mysql -h "$host" -P "$port" -u "$user" "$db"

echo "✓ restore complete"
