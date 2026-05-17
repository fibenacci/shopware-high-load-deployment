# APM & profiling

Three layers, all optional, all open source. Pick the ones you actually need
— they compose cleanly.

> 📖 Shopware itself is APM-agnostic — there's no dedicated upstream guide.
> The OTel-PHP auto-instrumentation picks up Symfony controller spans,
> Doctrine queries, Twig renders, and HTTP-client calls without code changes.
> Shopware ships an OTel-flavoured base image variant
> ([`ghcr.io/shopware/docker-base:8.3-frankenphp-otel`](https://github.com/shopware/docker-base))
> for teams that want pre-installed instrumentation.

| Layer       | Tool                     | What it tells you                                  | Cost |
| ----------- | ------------------------ | -------------------------------------------------- | ---- |
| **Traces**  | OpenTelemetry → Tempo    | "where did this request spend 2.3 s?"              | free |
| **Profiling** | Pyroscope (Excimer)    | "which function is hot right now in production?"   | free |
| **APM**     | Tideways (opt-in)        | Commercial — turn-key. Use only if you already pay | paid |

## OpenTelemetry — traces + metrics

The PHP auto-instrumentation extension (`open-telemetry/opentelemetry-auto-symfony`)
captures Symfony controller spans, Doctrine queries, Twig renders, and HTTP
client calls automatically.

```bash
composer require open-telemetry/opentelemetry-auto-symfony \
                 open-telemetry/sdk \
                 open-telemetry/exporter-otlp
```

Then in your container:

```ini
; docker/php/php.ini
extension = opentelemetry.so
OTEL_PHP_AUTOLOAD_ENABLED = true
```

The Collector config in [`opentelemetry/otel-collector.yaml`](./opentelemetry/otel-collector.yaml)
fans traces out to Tempo, metrics to Prometheus (remote write), and logs to Loki.

## Pyroscope — continuous PHP profiling

Pyroscope uses the [Excimer](https://github.com/wikimedia/mediawiki-php-excimer)
extension for low-overhead sampling. Add the [`grafana/pyroscope-php`](https://github.com/grafana/pyroscope-php)
package to your project; it auto-detects the configured server.

```bash
composer require grafana/pyroscope-php
```

```php
// In src/Kernel.php boot() — once per process.
\Pyroscope\Pyroscope::init([
    'application_name' => 'shopware-web',
    'server_address'   => $_ENV['PYROSCOPE_SERVER_ADDRESS'] ?? 'http://pyroscope:4040',
    'tags' => ['env' => $_ENV['APP_ENV'], 'instance' => $_ENV['INSTANCE_ID']],
]);
```

Grafana → "Explore Profiles" gives flame graphs, per-function CPU
percentages, and diff views between deployments.

## Tideways (commercial, opt-in)

Tideways is wired in as a build arg. Default: **disabled**.

```bash
docker buildx build \
    --build-arg TIDEWAYS_ENABLE=1 \
    --build-arg TIDEWAYS_VERSION=2024.1.2 \
    --target app \
    -t ghcr.io/EXAMPLE/shopware:tideways .
```

At runtime, set `TIDEWAYS_APIKEY` in the secret. See
[`tideways/README.md`](./tideways/README.md) for the full toggle.
