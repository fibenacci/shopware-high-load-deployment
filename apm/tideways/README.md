# Tideways (optional, opt-in)

Tideways is a commercial PHP APM. This template ships the **build-arg toggle**
to bake the daemon + extension into the image — the default keeps it OFF so
unrelated teams don't pull in a license obligation.

If your team already pays for Tideways, flip the switch:

## 1. Build with Tideways baked in

```bash
docker buildx build \
    --build-arg TIDEWAYS_ENABLE=1 \
    --build-arg TIDEWAYS_VERSION=2024.1.2 \
    --target app \
    -t ghcr.io/EXAMPLE/shopware:tideways .
```

## 2. Provide the API key at runtime

```yaml
# k8s/base/secret.yaml — patched via your secret manager
stringData:
    TIDEWAYS_APIKEY: "your-real-key"
```

And surface it as an env var. The container env already includes it because
`shopware-secrets` is loaded via `envFrom` (see deployment-web.yaml).

## 3. Configure sampling

```ini
; docker/php/php.ini — appended only when TIDEWAYS_ENABLE=1
tideways.sample_rate = 25
tideways.framework = symfony4
tideways.connection = unix:///var/run/tideways/tidewaysd.sock
```

## Open source alternative

If you ever want to drop Tideways, the [`opentelemetry/`](../opentelemetry/) +
[`pyroscope/`](../pyroscope/) pair gives you traces + profiling at parity for
most use cases. Grafana's "Service Graph" and "Explore Profiles" UIs are
roughly the Tideways "Service Map" + "Callgraph" equivalents.
