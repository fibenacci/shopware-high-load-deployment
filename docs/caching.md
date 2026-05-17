# Caching

Three layers, each addressing a different problem. The layers are
complementary — turning one off doesn't break the others, but high-load
shops want all three.

```
Browser
  │
  ▼  HTTP
┌──────────────────────────────────────┐
│  1. Edge HTTP cache — Varnish        │  ← whole-response cache, per URL
│     • 80–95 % hit rate on storefront │
│     • Shopware-aware VCL              │
│     • PURGE/xkey from kernel          │
└──────────────────────────────────────┘
  │ MISS
  ▼
┌──────────────────────────────────────┐
│  2. Symfony HttpCache (in-process)   │  ← per-pod fallback
│     • Backs Varnish on bypass        │
│     • Used when no Varnish in path   │
└──────────────────────────────────────┘
  │
  ▼  PHP execution
┌──────────────────────────────────────┐
│  3. Object/data caches — Redis       │  ← per-object cache hits
│     • DAL / Twig / Doctrine metadata │
│     • Sessions / increment / lock    │
└──────────────────────────────────────┘
```

> 📖 [Reverse HTTP cache](https://developer.shopware.com/docs/guides/hosting/infrastructure/reverse-http-cache.html) ·
> [Caches](https://developer.shopware.com/docs/guides/hosting/performance/caches.html) ·
> [Redis](https://developer.shopware.com/docs/guides/hosting/infrastructure/redis.html) ·
> [Session](https://developer.shopware.com/docs/guides/hosting/performance/session.html)

---

## 1. Varnish — edge HTTP cache

Single biggest perf lever for storefront traffic. Caches anonymous page
responses at the edge so HTTP requests never hit PHP-FPM until invalidation
fires.

### Image — prefer the official one

```yaml
# k8s/base/deployment-varnish.yaml
image: ghcr.io/shopware/varnish-shopware:latest
```

Shopware maintains `shopware/varnish-shopware` ([repo](https://github.com/shopware/varnish-shopware))
which ships the canonical VCL **plus the `xkey` module** used by Shopware's
surrogate-key invalidation. The `docker/varnish/` Dockerfile in this repo
is a self-contained fallback for air-gapped clusters; prefer the upstream
image whenever possible.

### Required Shopware env

```env
SHOPWARE_HTTP_CACHE_ENABLED=1
SHOPWARE_HTTP_DEFAULT_TTL=7200      # 2 hours, override per project
```

(Set in `k8s/base/configmap.yaml`.)

### Invalidation contract

Shopware fires invalidations from the kernel after entity writes — product
update, theme:compile, cache:clear. Two transports:

- **`xkey` surrogate keys** (preferred, used by the official image).
  Shopware annotates responses with `Xkey` headers; the kernel sends
  `BAN /` with `X-Invalidation-Pattern: <key>` to wipe just those entries.
- **HTTP PURGE per URL** (fallback when xkey isn't available).

The `purgers` ACL in the VCL restricts who may invalidate — only the
in-cluster Shopware pods. The base VCL allows RFC1918 ranges; tighten in
your overlay if you run cross-namespace.

### Bypass conditions

Varnish *never* caches:

- `Set-Cookie` responses (unless `X-Shopware-Allow-Nocache` says otherwise)
- Requests with the `session-*` cookie (logged-in customers, hot carts)
- `/admin`, `/api`, `/store-api`, `/account`, `/checkout`, `/widgets/{checkout,account}`

This matches the bypass rules in [`docker/varnish/default.vcl`](../docker/varnish/default.vcl)
and Shopware's upstream defaults.

### Observability

The Prometheus exporter sidecar (`jonnenauha/prometheus_varnish_exporter`)
in [`k8s/base/deployment-varnish.yaml`](../k8s/base/deployment-varnish.yaml)
exposes hit rate, backend health, eviction count. The Grafana dashboard at
`monitoring/grafana/dashboards/shopware-overview.json` already plots
hit-rate alongside request rate — a drop in hit rate is usually the first
visible sign of a cache invalidation bug.

### When Varnish is wrong

Skip it (and route Ingress straight to `shopware-web`) for:

- Staging — debugging cache invalidation is easier without a cache in the way
- A/B testing setups that vary by request fingerprint outside Varnish's hash
- Storefronts where >95 % of traffic is logged-in users anyway (e.g. B2B)

The staging overlay already does this by default; production routes through
Varnish.

---

## 2. Symfony HttpCache — in-process fallback

When `SHOPWARE_HTTP_CACHE_ENABLED=1` but no Varnish is in the request path,
Symfony's built-in `HttpCache` kernel layer takes over. Same contract as
Varnish — `Cache-Control`, `Vary`, etc. — but it's per-pod (not shared
across replicas).

Useful for:

- Single-replica staging
- Local dev (where you don't bother with Varnish)
- The `web` role bypass when ingress routes directly to `shopware-web`

You don't configure this separately — it's the same env vars as Varnish,
just without a Varnish process.

---

## 3. Redis — object / data caches

Shopware uses Redis for **five** distinct concerns, each pointed at a
different Redis DB number:

| Concern | Env DSN | Default DB |
| --- | --- | --- |
| App / DAL cache (`shopware.cache.invalidation.delay`) | `REDIS_DSN` | `1` |
| HTTP cache backend (Symfony HttpCache adapter, when not using Varnish) | shared with app | `1` |
| Sessions | `REDIS_SESSION_*` | `0` |
| Increment storage (number ranges, lock attempts) | `LOCK_DSN=redis://...` | shared |
| Cart storage (optional — usually still DB-backed) | configurable | — |

Configured in [`k8s/base/configmap.yaml`](../k8s/base/configmap.yaml).
See [Shopware Redis docs](https://developer.shopware.com/docs/guides/hosting/infrastructure/redis.html)
for the per-feature env vars.

### Tuning

- `maxmemory-policy allkeys-lru` (already set in [`k8s/base/redis.yaml`](../k8s/base/redis.yaml))
- `maxmemory 1gb` for small shops, scale with the catalogue size
- Single replica is fine until you need HA — then switch to Redis Sentinel
  or a managed Redis (ElastiCache, Aiven, Upstash, Redis Cloud)

### Sessions

> 📖 [Session storage docs](https://developer.shopware.com/docs/guides/hosting/performance/session.html)

`REDIS_SESSION_*` env vars route Symfony sessions to Redis. Without it
Shopware writes to disk per pod → broken when sticky sessions aren't on,
and they aren't on in our Ingress.

---

## Cache invalidation gotchas

1. **`make cache` in dev** clears the Symfony cache but NOT Varnish.
   Varnish reaches into the running container; on a fresh `make up` it
   doesn't exist yet locally anyway.
2. **`theme:compile` is the only command** that triggers a full Varnish
   purge through Shopware's kernel. Manual `redis-cli FLUSHALL` works too
   but bypasses Shopware's expected cleanup hooks (cache-tag side effects).
3. **HPA flapping** is usually a sign of a Varnish hit-rate drop after a
   deploy. The Grafana dashboard surfaces this in one panel.
4. **Logged-in users** never see Varnish content. If your shop has
   account-required pricing or B2B portals, expect a different hit-rate
   curve than catalogue-driven shops.
