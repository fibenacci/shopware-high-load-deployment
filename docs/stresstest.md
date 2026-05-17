# Stresstest

k6 against a Shopware cluster, running **inside** the cluster as a Job. Tests
emit metrics straight into the same Prometheus that scrapes the shop, so you
can correlate load-curves with pod CPU, FPM saturation, DB connections, and
RabbitMQ backlog in a single Grafana dashboard.

> 📖 Shopware ships its own k6 guidance: [Performance test with k6](https://developer.shopware.com/docs/guides/hosting/performance/k6.html).
> Worth a read for Shopware-specific endpoints to exercise.

## Profiles

The same script (`k3s/stresstest/k6/loadtest.js`) supports six shapes:

| Profile      | Shape                            | Typical use                                       |
| ------------ | -------------------------------- | ------------------------------------------------- |
| `smoke`      | 1 VU, 30 s                       | sanity check post-rollout                         |
| `baseline`   | ramp to 50 VU, 15 min total      | day-to-day baseline numbers                       |
| `peak`       | ramp to 500 VU, 20 min total     | sales-event / Black Friday rehearsal              |
| `endurance`  | 100 VU, 60 min                   | leak hunting, slow query growth, GC               |
| `spike`      | 0 → 300 VU in 30 s, 2 min hold   | does the HPA react fast enough?                   |
| `regression` | 20 RPS constant arrival, 3 min   | CI-blocking gate — deterministic, comparable runs |

Select via the `K6_PROFILE` env var on the Job. Each profile has its
own threshold set (tight on `regression`, lenient on `peak`).

The CI `performance.yml` workflow runs the `regression` profile on every
PR that touches perf-relevant paths, plus nightly on `main` as a drift
detector.

## Quickstart

```bash
# 1. Materialize the script into a ConfigMap (idempotent)
kubectl -n shopware-staging create cm shopware-stresstest-script \
    --from-file=loadtest.js=k3s/stresstest/k6/loadtest.js \
    --dry-run=client -o yaml | kubectl apply -f -

# 2. Run the Job
kubectl -n shopware-staging set env job/shopware-stresstest K6_PROFILE=peak
kubectl apply -f k3s/stresstest/k6-job.yaml

# 3. Watch
kubectl -n shopware-staging logs -f job/shopware-stresstest
```

The Makefile wraps steps 1–3 into `make stresstest`.

## Thresholds

The script fails the run when any threshold breaks:

```js
thresholds: {
    http_req_failed:           ['rate<0.02'],   // <2% errors overall
    http_req_duration:         ['p(95)<1500'],  // p95 under 1.5 s
    shopware_page_load_ms:     ['p(95)<2000'],
    shopware_cart_add_success: ['rate>0.95'],
},
```

A failed run exits non-zero → the Job goes into `Failed` and CI bails. Tighten
the thresholds when your numbers improve; loosen them when adding new code paths.

## Reading the results

Three places to look:

1. **k6 console output** at the end of the run — quick overview.
2. **Grafana "k6" dashboard** (auto-installed via the Prometheus remote write
   exporter) — every metric over time.
3. **Grafana "Shopware — Overview"** dashboard during the run — correlate
   load with infrastructure load.

## What this catches that unit tests don't

- **HPA misconfiguration**: pods scale to max but RPS still bottlenecks.
- **DB connection exhaustion**: MariaDB rejects connections before the app
  is CPU-bound.
- **PHP-FPM `pm.max_children`**: requests queue up at the FPM master.
- **Cache stampede after deploy**: cold caches cause a 10x latency spike for
  the first 2 minutes.
- **Worker starvation**: messenger backlog grows faster than the worker pool
  can drain.

These are the failure modes that take down shops on Black Friday, and they
only show up under realistic load.
