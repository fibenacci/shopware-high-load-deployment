# Reusing this template for a new Shopware shop

What was lifted from `ugg-unified-shop`, what's new, and the steps to bend
this template to a different project.

## What was lifted (and why)

| Pattern                                | Source                                              | Why it's reusable                                                   |
| -------------------------------------- | --------------------------------------------------- | ------------------------------------------------------------------- |
| Multi-service `compose.yaml`           | `ugg-unified-shop/compose.yaml`                     | dev/prod parity; one container per process; named volumes for state |
| Dinghy + `*.docker` ingress            | `ugg-unified-shop/docker/ingress.conf`              | Wildcard-DNS routing for sales-channel domains on the host          |
| Idempotent `docker-entrypoint.sh`      | `ugg-unified-shop/docker/docker-entrypoint.sh`      | `.setup_complete` / `.db_imported` sentinels survive container restarts |
| `Makefile` as single entry point       | `ugg-unified-shop/Makefile`                         | One command for every workflow, self-documenting via the `help` target |
| Pre-baked CI image                     | `ugg-unified-shop/.github/ci/Dockerfile`            | Composer / plugin:install / theme:compile cached in image layers     |
| Symfony CI overrides drop-in           | `ugg-unified-shop/.github/ci/symfony-ci-overrides.yaml` | sync messenger + fs cache → no Redis/Rabbit sidecars in CI       |
| Gated CI with `continue-on-error`+Gate | `ugg-unified-shop/.github/workflows/ci.yml`         | All suites run; gate step decides what fails the build               |
| JUnit + Playwright artefact uploads    | same                                                | Failed runs still produce reports                                     |
| Sales-channel host mapping             | `ugg-unified-shop/docker/apply-sales-channel-domains.sh` | Multi-channel local dev                                          |
| rsync deploy with `.rsyncexclude`      | `ugg-unified-shop/.github/workflows/deploy.yml`     | Useful as a fallback for legacy hosting                              |

## What's new in this template

- **Global config** (`deployment.config`) — versions + deploy mode + image
  registry, sourced by Makefile / Docker / CI.
- **Canonical Shopware tooling**: `shopware/deployment-helper`,
  `deploy.php` (Deployer recipe), `ghcr.io/shopware/docker-base:frankenphp`,
  `shopware-cli project ci`, `bin/console system:setup:staging`.
- **Four deploy modes** dispatched by one Makefile target:
  `docker` / `kubernetes` / `managed-container` / `bare-metal`.
- Multi-stage `docker/Dockerfile` producing `app` / `worker` / `cron` stages
  from one image.
- Kustomize base + staging / production overlays.
- Production `compose.yaml` for TimmeHosting / Hetzner / generic VPS.
- k3d-based local k3s cluster + k6 stresstest harness.
- LGTM monitoring stack (compose + Helm values).
- OTel Collector pipeline, Pyroscope continuous profiling, Tideways opt-in.
- Full test framework — PHPUnit (unit + integration) + Playwright + PHPStan +
  PHP-CS-Fixer + PHPCS + PHPMD.

## How to adapt to a new shop

1. **Rename**. Set `COMPOSE_PROJECT_NAME`, `PROJECT_DOMAIN`, and the
   `ghcr.io/EXAMPLE/...` image references in
   `k8s/base/kustomization.yaml` + both overlay `kustomization.yaml`s.
2. **Drop your code**. Replace `composer.json`, `src/`, `config/`,
   `custom/`, `public/index.php` with your Shopware project.
3. **Set the secrets**. Fill in `auth.json` locally and the K8s
   `shopware-secrets` Secret via your secret manager.
4. **Fetch a dump**. Either configure `.shopware-project.yml` so
   `bin/fetch-dump.sh` works against your remote, or drop a `dump.sql.gz`
   into the repo root before `make up`.
5. **Pick your APM**. Default = OpenTelemetry + Pyroscope (zero license
   cost). Set `TIDEWAYS_ENABLE=1` at image-build time if your org pays for it.
6. **Configure the ingress host**. Patch
   `k8s/overlays/<env>/patch-ingress.yaml` with your real domain and
   cert-manager `ClusterIssuer`.
7. **Map your CI secrets**. The CI workflow expects
   `COMPOSER_AUTH_TOKEN`, `SHOPWARE_PACKAGES_TOKEN`, `KUBECONFIG`, and
   optionally `SMOKE_TEST_URL` as a repo variable.
