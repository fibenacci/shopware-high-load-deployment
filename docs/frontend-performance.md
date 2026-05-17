# Frontend performance

Theme-Code is out of scope for this template — you ship your own Twig
templates and the CSS/JS that goes with them. But there's a layer
**between** infrastructure and theme code where the template can move the
needle without touching a single `.twig` file. This doc lists the levers
we expose.

> 📖 Shopware's own performance starting points:
> [Performance Tweaks](https://developer.shopware.com/docs/guides/hosting/performance/performance-tweaks.html) ·
> [Caches](https://developer.shopware.com/docs/guides/hosting/performance/caches.html)

## Levers the template already pulls

| Lever | Where | Effect |
| --- | --- | --- |
| **Varnish edge cache** | `docker/varnish/`, [`docs/caching.md`](./caching.md) | 80–95% of storefront requests never reach PHP |
| **WebP thumbnails** | Shopware default since 6.4 — built into `bin/console media:generate-thumbnails` | ~30% smaller hero images vs JPEG, automatic |
| **Asset fingerprinting** | Shopware default — `bin/console assets:install` writes hashed filenames | Allows `Cache-Control: public, max-age=1y, immutable` on the CDN |
| **HTTP/2** | FrankenPHP base image speaks h2 + h2c out of the box | Multiplexed requests, header compression |
| **Gzip/Brotli at the edge** | Set by Varnish + Ingress (`nginx.ingress.kubernetes.io/server-snippet`) | ~70% smaller text payloads. Brotli only — gzip fallback for old clients |
| **`<img loading="lazy">`** | Storefront base layout sets it since Shopware 6.4 | Defers off-screen image load |
| **Resource hints — `preconnect` to CDN** | Storefront base layout auto-adds when `shopware.cdn.url` is set | Saves the TLS handshake to the asset domain |

## Levers the template *exposes* but doesn't enforce

These are settings you tune per project — defaults are reasonable, but
high-load shops should validate them.

### Brotli at the edge

The official Shopware Varnish image (`ghcr.io/shopware/varnish-shopware`)
ships Brotli compression via `vmod_brotli`. No config needed unless you
override the VCL. For the in-pod FrankenPHP fallback path, Caddy's
`encode` directive handles it.

### Early Hints (HTTP 103)

FrankenPHP supports `103 Early Hints` natively — the kernel can ship
`Link: </theme/storefront.css>; rel=preload` headers before the response
body is ready. Shopware sets these when configured to. To enable:

```yaml
# config/packages/shopware.yaml — add to the existing block
shopware:
    storefront:
        early_hints:
            enabled: true
            preload_assets: true
```

Then verify with `curl -I --http2-prior-knowledge -v https://shop.example.com/`
— you should see a `103` response before the `200`.

### Image variant generation

`bin/console media:generate-thumbnails --strict --tenant-id=...` runs at
deploy time (handled by `shopware-deployment-helper run`). Adjust the
thumbnail breakpoints in `config/packages/shopware.yaml` when adding new
viewport sizes:

```yaml
shopware:
    media:
        types:
            image:
                thumbnails:
                    - { width: 400,  height: 400  }
                    - { width: 800,  height: 800  }
                    - { width: 1920, height: 1920 }
```

### CDN URL

Set `shopware.cdn.url` (or the env var `APP_URL` on a separate domain)
to push all `/bundles`, `/theme`, `/media`, `/thumbnail` requests to your
CDN. Already covered in [`object-storage.md`](./object-storage.md) — this
is the same lever from a different angle.

## What the template **doesn't** do — and why

| Thing | Why not |
| --- | --- |
| **Critical CSS extraction** | Theme-specific. Belongs in your `bin/build-storefront.sh` step, plus a tool like `critical` or `penthouse`. Generic critical CSS extraction breaks more than it helps. |
| **JS code-splitting** | Theme-specific. Modern Shopware storefronts already split per route. |
| **Lighthouse CI as a gate** | Lighthouse results vary per-run by ±5 points on the same code; using it as a blocking gate produces flaky CI. Use it as a **trend dashboard** instead (Grafana datasource for Lighthouse JSON exports). |
| **Preloading the world** | More `<link rel=preload>` ≠ faster. Browser does a better job auto-prioritising. Only preload `above-the-fold` assets you can prove are render-blocking. |
| **Bundle-size budgets** | Theme-specific. Set in your `package.json` with `bundlesize` or `size-limit` once you have a real bundle to measure. |

## Measure before you tune

The Pyroscope / OTel / Grafana stack already in this template gives you
**backend** perf signals. For **frontend** you need real-user metrics:

- **Web Vitals (LCP, INP, CLS)** — easiest way to collect them is
  Shopware Cloud Analytics OR a tiny `web-vitals` JS snippet posting to
  your OTel collector via the `otelhttp` endpoint already exposed at
  `otel-collector.observability:4318`.
- **Lighthouse runs from CI** — useful for trend, not for gating. Run on
  `main` only, store JSON, plot in Grafana.

## Quick wins checklist

Order roughly by impact-per-hour:

1. ✅ Verify Varnish hit rate is > 80% in Grafana (already wired). If
   not, you have an invalidation bug, not a perf bug.
2. ✅ Check `Cache-Control` headers on `/theme/...` and `/bundles/...` —
   should be `max-age=31536000, immutable`. If not, your CDN config is
   undoing Shopware's defaults.
3. ⏱ Enable Early Hints (above) — ~50–200 ms saved on cold loads.
4. ⏱ Run `bin/console media:generate-thumbnails --strict` once after
   import-dump in local dev — most "slow" local shops are slow because
   they're generating thumbnails on every request.
5. ⏱ Add a CDN if you don't have one (see [`object-storage.md`](./object-storage.md)).
6. 🔬 *Then* measure. Don't tune what you can't see.
