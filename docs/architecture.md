# Architecture

```
                        ┌─────────────────────────┐
                        │   GitHub Actions CI     │
                        │  (pre-baked CI image)   │
                        └────────────┬────────────┘
                                     │ push to ghcr.io
                                     ▼
        ┌────────────────────────────────────────────────────────┐
        │                Container registry (GHCR)                │
        │   ghcr.io/.../shopware             (web stage)          │
        │   ghcr.io/.../shopware-worker      (worker stage)       │
        │   ghcr.io/.../shopware/cron        (cron stage)         │
        └────────────────────────┬───────────────────────────────┘
                                 │ kubectl apply -k overlays/...
                                 ▼
   ┌────────────────────────────────────────────────────────────────┐
   │                  Kubernetes cluster (k8s/k3s)                  │
   │                                                                │
   │  ┌──────────────┐   ┌─────────────────┐   ┌──────────────────┐ │
   │  │ Ingress nginx│──▶│ shopware-web    │   │ shopware-worker  │ │
   │  │  + cert-mgr  │   │  (Deployment +  │   │  (Deployment)    │ │
   │  └──────────────┘   │   HPA + PDB)    │   └──────────────────┘ │
   │                     └────────┬────────┘            │           │
   │                              │                     │           │
   │                              ▼                     ▼           │
   │  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────────────┐│
   │  │ MariaDB  │  │ Redis    │  │ RabbitMQ │  │ OpenSearch       ││
   │  │ (STS)    │  │ (STS)    │  │ (STS)    │  │ (STS)            ││
   │  └──────────┘  └──────────┘  └──────────┘  └──────────────────┘│
   │                                                                │
   │  ┌──────────────────────────────────────────────────────────┐  │
   │  │ Observability namespace                                  │  │
   │  │ ┌──────────────┐  ┌────────┐  ┌──────┐  ┌─────────────┐  │  │
   │  │ │ Prometheus + │  │ Loki + │  │ Tempo│  │ Pyroscope   │  │  │
   │  │ │ Alertmanager │  │Promtail│  │      │  │             │  │  │
   │  │ └──────────────┘  └────────┘  └──────┘  └─────────────┘  │  │
   │  │                          │           │                   │  │
   │  │                          ▼           ▼                   │  │
   │  │                   ┌──────────────────────────┐           │  │
   │  │                   │   Grafana (LGTM UI)      │           │  │
   │  │                   └──────────────────────────┘           │  │
   │  └──────────────────────────────────────────────────────────┘  │
   │                                                                │
   │  ┌──────────────────────────────────────────────────────────┐  │
   │  │ Stresstest namespace                                     │  │
   │  │   k6 Job  ──▶  shopware-web.shopware-staging.svc          │  │
   │  └──────────────────────────────────────────────────────────┘  │
   └────────────────────────────────────────────────────────────────┘
```

## Process model — three roles, one image

The production image (`docker/Dockerfile`) builds **once** on
[`ghcr.io/shopware/docker-base`](https://developer.shopware.com/docs/guides/hosting/installation-updates/docker.html)
and is reused by three Deployments through different `args`:

| Role     | CMD       | Started by              | Purpose                          |
| -------- | --------- | ----------------------- | -------------------------------- |
| `web`    | `web`     | `Deployment/shopware-web` | nginx + php-fpm via supervisord  |
| `worker` | `worker`  | `Deployment/shopware-worker` | Long-running messenger consumer |
| `cron`   | `cron`    | `CronJob/shopware-scheduled-task` | Scheduled tasks, runs every 5 min |
| `migrate`| `migrate` | One-shot Job (per deploy) | DB migrations + cache warmup     |

Switching roles is just changing the `args` field. The kernel, plugins, and
cache state are byte-identical across all roles → fewer "works on web, breaks
on worker" surprises.

## Data flow

1. **Browser** → Ingress (TLS termination) → `shopware-web` Service → pod
2. **Pod** → in-pod nginx → in-pod php-fpm via `127.0.0.1:9000`
3. **Pod** → MariaDB / Redis / OpenSearch / RabbitMQ (Cluster IP services)
4. **Pod** → OTel Collector (OTLP gRPC) for traces + metrics + logs
5. **Pod** → Pyroscope server (HTTP push) for CPU samples every 10 s

## Failure modes the design handles

- **Web pod OOM**: kubelet restarts it; HPA may scale up if memory pressure
  is sustained. PDB prevents the rollout from dropping below `minAvailable`.
- **DB migration failure**: pre-deploy migration Job fails, rollout is never
  triggered. Old pods keep serving the old code on the old schema.
- **Worker backlog**: RabbitMQ alert fires; HPA on worker queue depth (set
  up in the overlay with custom metrics) scales out.
- **Bad deploy**: `kubectl rollout undo` reverts to the previous ReplicaSet
  in seconds.
