# Object storage (S3 / R2 / Backblaze) for media

Local volumes don't scale past one replica per shared asset bucket. Moving
`public/media`, `public/thumbnail`, `public/theme`, `public/sitemap`, and
`public/bundles` to an object store is the single biggest unlock for
horizontal scaling, and the only way the K8s overlay's `replicas > 1`
makes sense in production.

This template wires up Shopware's native filesystem layer (Flysystem)
so the switch is one env-var flip in the overlay.

## What you need

| Provider                   | What works                                              |
| -------------------------- | ------------------------------------------------------- |
| **AWS S3 + CloudFront**    | Native, fully supported                                 |
| **Cloudflare R2**          | S3-compatible — point `AWS_ENDPOINT` at the R2 endpoint |
| **Backblaze B2**           | S3-compatible — same trick                              |
| **Hetzner Object Storage** | S3-compatible — same trick                              |
| **MinIO (self-hosted)**    | S3-compatible — runs as a sidecar in your cluster       |

## Composer dependencies

Shopware recommends the AsyncAws variant — lower memory footprint, same API
surface as the v3 client.

```bash
composer require league/flysystem-async-aws-s3
```

(Already in [`composer.json.example`](../composer.json.example).)

> 📖 [Shopware filesystem docs](https://developer.shopware.com/docs/guides/hosting/infrastructure/filesystem.html)

## Configuration

The template does **not** ship a `config/packages/filesystem.yaml` —
Dockware (local dev) and `shopware/docker-base` (k8s/prod) ship sane
local-disk defaults that just work. To flip a real environment to S3,
override `shopware.filesystem.*` per-environment.

### Why not a templated file with `%env(...)%`

Shopware validates the `shopware.filesystem.*` schema at container-build
time, before env-var resolution. Passing a `%env(SHOPWARE_FILESYSTEM_PUBLIC)%`
string where the schema expects an `{type, config}` array produces:

```
A dynamic value is not compatible with a "Symfony\Component\Config\Definition\ArrayNode"
node type at path "shopware.filesystem.public".
```

So env-var injection of whole filesystem blocks doesn't work — the structure
must be present as literal YAML at compile time.

### How to set up S3 in a real environment

Drop the YAML directly into your overlay or project. **For Kubernetes**, add
a `patch-filesystem.yaml` to your overlay:

```yaml
# k8s/overlays/production/patch-filesystem.yaml — apply this and add to
# kustomization.yaml's patches list.
apiVersion: v1
kind: ConfigMap
metadata: { name: shopware-config }
data:
    SHOPWARE_FILESYSTEM_PUBLIC: |
        {"type":"amazon-s3","config":{"bucket":"shop-public","region":"eu-central-1","root":"public","endpoint":null,"url":"https://cdn.example.com"}}
    SHOPWARE_FILESYSTEM_THEME: |
        {"type":"amazon-s3","config":{"bucket":"shop-public","region":"eu-central-1","root":"theme","url":"https://cdn.example.com/theme"}}
    SHOPWARE_FILESYSTEM_SITEMAP: |
        {"type":"amazon-s3","config":{"bucket":"shop-public","region":"eu-central-1","root":"sitemap","url":"https://cdn.example.com/sitemap"}}
    SHOPWARE_FILESYSTEM_ASSET: |
        {"type":"amazon-s3","config":{"bucket":"shop-public","region":"eu-central-1","root":"bundles","url":"https://cdn.example.com/bundles"}}
    SHOPWARE_FILESYSTEM_PRIVATE: |
        {"type":"amazon-s3","config":{"bucket":"shop-private","region":"eu-central-1","root":"files","visibility":"private"}}
```

Credentials go into the Secret:

```yaml
apiVersion: v1
kind: Secret
metadata: { name: shopware-secrets }
stringData:
    AWS_ACCESS_KEY_ID: "..."
    AWS_SECRET_ACCESS_KEY: "..."
    AWS_REGION: "eu-central-1"
```

For R2 / Backblaze, add `AWS_ENDPOINT` too:

```
AWS_ENDPOINT=https://<account-id>.r2.cloudflarestorage.com
```

## Removing the emptyDir volumes

Once S3 is wired up, the `media` / `thumbnail` / `theme` / `sitemap` /
`bundles` volumes in the web Deployment can go. The production overlay
already includes a `patch-volumes.yaml` slot for this — see
[`k8s/overlays/production/patch-volumes.yaml`](../k8s/overlays/production/patch-volumes.yaml).

## CDN setup

Public assets are read **directly from the CDN by the browser**, not via
the Shopware container. Set `AWS_BUCKET_PUBLIC_URL` to the CDN origin
(`https://cdn.example.com`) and the Shopware URL helpers will rewrite
storefront URLs accordingly.

Cache busting works out of the box: Shopware appends content hashes to
asset URLs (`/bundles/storefront/theme/abc123.css`), so the CDN can cache
indefinitely.

## Backups

Per-bucket lifecycle rules:

| Bucket               | Lifecycle                                                |
| -------------------- | -------------------------------------------------------- |
| `shop-public`        | Versioning on, 30-day retention on deleted objects       |
| `shop-private`       | Versioning on, 90-day retention                          |
| (sitemap, theme)     | Re-generated on deploy — versioning optional             |

## Migration from local

```bash
# 1. Wire up S3 (overlay change), deploy.
# 2. Sync existing media:
kubectl -n shopware-production exec -it deploy/shopware-web -- bash
> aws s3 sync /var/www/html/public/media     s3://shop-public/media
> aws s3 sync /var/www/html/public/thumbnail s3://shop-public/thumbnail
> aws s3 sync /var/www/html/public/theme     s3://shop-public/theme

# 3. After verification, remove the emptyDir mounts in the next deploy.
```
