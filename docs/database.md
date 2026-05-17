# Database — sizing, replication, pooling

For high-load shops the in-cluster MariaDB StatefulSet is a starter, not
a destination. Once traffic warrants it, swap in a managed offering and
turn on read replicas + connection pooling.

## Read replica routing

Shopware's DAL natively reads `DATABASE_REPLICA_*_URL` env vars and routes
read-only SELECT queries to one of them. Writes still go through
`DATABASE_URL`.

Add the replicas to the production overlay's Secret (or ConfigMap if the
credentials match the writer):

```yaml
# k8s/overlays/production/patch-replicas-db.yaml
apiVersion: v1
kind: Secret
metadata: { name: shopware-secrets }
stringData:
    DATABASE_REPLICA_0_URL: "mysql://reader:***@reader-0.internal:3306/shopware"
    DATABASE_REPLICA_1_URL: "mysql://reader:***@reader-1.internal:3306/shopware"
```

Reference the patch in `kustomization.yaml`:

```yaml
patches:
    - path: patch-replicas-db.yaml
```

Reader DSNs should use a **read-only DB user** so a wrongly-routed write
fails loud instead of silently writing to a soon-to-be-overwritten replica.

## Connection pooling

PHP-FPM + Shopware opens a new DB connection per request. At a few
hundred concurrent requests per pod, the connection count blows up.

**ProxySQL** sits in front of the DB and pools connections across the
fleet. Recommended setup:

```
shopware-web pod ─→ ProxySQL DaemonSet (one per node) ─→ MariaDB primary
                                                      └→ MariaDB readers
```

ProxySQL also handles the read-write split, so when you adopt it you can
drop `DATABASE_REPLICA_*_URL` and let ProxySQL decide.

This template doesn't ship ProxySQL by default — it's only needed past
~20 pods. Add via:

```bash
helm repo add proxysql https://proxysql.github.io/proxysql-helm-chart
helm install proxysql proxysql/proxysql -n shopware-production \
    --set servers.writers="db-primary.internal:3306" \
    --set servers.readers="reader-0.internal:3306,reader-1.internal:3306"
```

Then point `DATABASE_URL` at the in-cluster ProxySQL service.

## Managed alternatives

| Provider                   | Notes                                                  |
| -------------------------- | ------------------------------------------------------ |
| **AWS RDS for MariaDB / Aurora MySQL** | Native read replicas + automated failover |
| **Google Cloud SQL**       | Same                                                   |
| **Hetzner Managed DB**     | EU jurisdiction, replicas in private network           |
| **DigitalOcean Managed DB**| Read pools out of the box                              |

When switching, **delete the `mariadb.yaml` StatefulSet from the overlay's
kustomization** (or comment it out in `k8s/base/kustomization.yaml` for
the env). Point `DATABASE_URL` at the managed endpoint.

## Backups

Two layers, complementary:

**Layer 1: K8s-native CronJob** — `k8s/base/cronjob-backup.yaml` runs
`mysqldump --single-transaction` daily, encrypts with `openssl enc
-aes-256-cbc` using a per-env passphrase, uploads to S3-compatible
storage. Retention via the bucket's lifecycle rules (recommended:
30d STANDARD_IA → 90d GLACIER → 365d DEEP_ARCHIVE → delete).

Restore from any backup is one command:

```bash
kubectl run restore -it --rm \
    --image=ghcr.io/EXAMPLE/shopware-backup:latest \
    --env-from=secretRef:shopware-secrets \
    --env-from=secretRef:shopware-backup-secrets \
    --command -- /restore.sh s3://shop-db-backups/production/20260516-031722.sql.gz.enc
```

Suspicious-size guard built in: dumps smaller than 1 MB fail the Job, so
silently-empty backups don't go unnoticed for weeks.

**Layer 2: Velero** — for cluster-wide DR (PVC snapshots, multi-resource
restores, namespace clones). Install separately:

```bash
helm install velero vmware-tanzu/velero \
    -n velero --create-namespace \
    --set configuration.provider=aws \
    --set configuration.backupStorageLocation.bucket=cluster-velero-backups
```

Use this when you need point-in-time recovery that goes beyond the DB
(media volumes if you haven't migrated to S3 yet, ConfigMap/Secret
state, etc).

## Tuning checkpoints

| Symptom                                  | First check                                     |
| ---------------------------------------- | ----------------------------------------------- |
| `Too many connections` errors            | `max_connections`, pool size, ProxySQL needed?  |
| p95 latency creeping up                  | Slow query log; add indexes; OpenSearch reindex |
| RabbitMQ backlog growing                 | Worker DB contention — reduce write replicas    |
| Replication lag > 5 s                    | Reader undersized; check binlog format = ROW    |
| HPA flapping                             | Cache hit rate dropped — check Varnish + Redis  |
| Backup size dropped > 50%                | mysqldump may have hit a permissions issue      |
