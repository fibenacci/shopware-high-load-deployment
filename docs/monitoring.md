# Monitoring & observability

The "LGTM" stack (Loki, Grafana, Tempo, Mimir/Prometheus) plus Pyroscope for
continuous profiling. All open source, all wired up out of the box.

> 📖 No single canonical Shopware monitoring guide — the stack here is
> infrastructure-agnostic. Shopware-specific signals worth scraping are
> documented in [Performance Tweaks](https://developer.shopware.com/docs/guides/hosting/performance/performance-tweaks.html)
> and [Caches](https://developer.shopware.com/docs/guides/hosting/performance/caches.html).

## Local dev

```bash
make monitoring-up
open http://grafana.shop.docker     # admin / admin
```

This boots Prometheus + Grafana + Loki + Tempo + Pyroscope + the OTel
Collector on the same Docker network as the shop, so scrape targets work
without any extra config.

## Production

`monitoring/k8s/` ships values files for the upstream Helm charts:

```bash
helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
    -n observability --values monitoring/k8s/kube-prometheus-stack-values.yaml

helm upgrade --install loki      grafana/loki      -n observability -f monitoring/k8s/loki-values.yaml
helm upgrade --install promtail  grafana/promtail  -n observability -f monitoring/k8s/promtail-values.yaml
helm upgrade --install tempo     grafana/tempo     -n observability -f monitoring/k8s/tempo-values.yaml
helm upgrade --install pyroscope grafana/pyroscope -n observability -f monitoring/k8s/pyroscope-values.yaml
```

Once those are running, `k8s/base/servicemonitor.yaml` is picked up
automatically. The Pod annotations (`prometheus.io/scrape`, `port`, `path`)
also make the in-pod php-fpm exporter discoverable.

## What gets collected

| Signal      | Source                          | Backend       | Retention |
| ----------- | ------------------------------- | ------------- | --------- |
| Metrics     | nginx-exporter, php-fpm-exporter, kube-state-metrics, node-exporter, MariaDB exporter, Redis exporter, RabbitMQ exporter | Prometheus | 15 days |
| Logs        | nginx JSON stdout + php-fpm stderr (Promtail) | Loki | 7 days |
| Traces      | otel-php-auto + Symfony auto-instrumentation → OTLP | Tempo | 7 days |
| Profiles    | Excimer → Pyroscope             | Pyroscope     | 30 days |
| Synthetic   | k6 Job + Prometheus remote-write | Prometheus    | 15 days |

## Key dashboards

- **Shopware — Overview** (`grafana/dashboards/shopware-overview.json`): RPS,
  5xx rate, p95 latency, PHP-FPM saturation, recent errors.

Add your own JSON dashboards under `monitoring/grafana/dashboards/` — they
are auto-loaded by the provisioning provider in
`monitoring/grafana/provisioning/dashboards/dashboards.yaml`.

## Alerts

`monitoring/prometheus/alerts.yaml` ships starter rules:

| Alert                       | Triggers when                                            | Severity |
| --------------------------- | -------------------------------------------------------- | -------- |
| `ShopwareWebUnavailable`    | No nginx traffic AND no healthy php-fpm for 3 min        | critical |
| `ShopwareHigh5xxRate`       | 5xx rate > 2% over 5 min                                  | warning  |
| `ShopwareHighRequestLatency`| p95 latency > 2 s for 10 min                              | warning  |
| `PhpFpmSaturated`           | active/total > 85% for 5 min                              | warning  |
| `PhpFpmMaxChildrenReached`  | `pm.max_children` reached at any point in last 10 min     | critical |
| `MariaDBConnectionsHigh`    | connections > 80% of max for 10 min                       | warning  |
| `RedisHighMemory`           | used > 85% for 10 min                                     | warning  |
| `RabbitMQQueueBacklog`      | ready msgs > 5000 for 10 min                              | warning  |
