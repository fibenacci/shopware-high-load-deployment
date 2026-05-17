# Pyroscope — continuous PHP profiling

Grafana Pyroscope is a free, open source profiling backend. The PHP client
uses [Excimer](https://github.com/wikimedia/mediawiki-php-excimer) for
low-overhead CPU + wall-clock sampling (~1% in production).

## Why Excimer (not Xhprof / Spx)

| Tool       | Production-safe        | Continuous            | Hot/Cold diffing |
| ---------- | ---------------------- | --------------------- | ---------------- |
| Xhprof     | High overhead          | No                    | Manual           |
| php-spx    | Yes (but interactive)  | No                    | Manual           |
| **Excimer**| **~1% overhead**       | **Yes**               | **Built in**     |

## Install (image side)

`docker/Dockerfile` already builds with pecl. Add Excimer to the same RUN:

```dockerfile
RUN apk add --no-cache --virtual .build-deps $PHPIZE_DEPS \
    && pecl install excimer redis apcu \
    && docker-php-ext-enable excimer redis apcu \
    && apk del .build-deps
```

## Wire up the SDK

```bash
composer require grafana/pyroscope-php
```

```php
// src/Kernel.php boot() — once per worker.
\Pyroscope\Pyroscope::init([
    'application_name' => 'shopware-web',
    'server_address'   => $_ENV['PYROSCOPE_SERVER_ADDRESS'],
    'tags' => [
        'env'      => $_ENV['APP_ENV'],
        'instance' => $_ENV['INSTANCE_ID'] ?? gethostname(),
        'role'     => $_SERVER['HTTP_HOST'] ?? 'cli',
    ],
]);
```

## In Grafana

- Explore → Profiles → datasource `Pyroscope`
- Compare two time ranges to spot regressions after a deploy
- Use tag filters (env, role, instance) to drill into a single pod
