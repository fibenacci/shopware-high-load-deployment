# Documentation index

This template is opinionated about **using the official Shopware tooling**.
Every doc here cross-references the upstream Shopware page so you can
verify behaviour against the source of truth.

## Operations

| Doc | Topic | Shopware reference |
| --- | --- | --- |
| [`architecture.md`](./architecture.md) | Process model, data flow, failure modes | — |
| [`deployment.md`](./deployment.md) | CI + four deploy paths (docker / k8s / managed-container / bare-metal) | [Deployments overview](https://developer.shopware.com/docs/guides/hosting/installation-updates/deployments/) · [Deployment Helper](https://developer.shopware.com/docs/guides/hosting/installation-updates/deployments/deployment-helper.html) · [Deployer integration](https://developer.shopware.com/docs/guides/hosting/installation-updates/deployments/deployment-with-deployer.html) |
| [`secrets.md`](./secrets.md) | Secret inventory, GitHub Actions checklist, rotation, gitleaks gate | — |
| [`security.md`](./security.md) | Image scanning, rate limiting (Shopware + Ingress), NetworkPolicies, audit trails | [Rate limiter](https://developer.shopware.com/docs/guides/hosting/infrastructure/rate-limiter.html) |
| [`signed-commits.md`](./signed-commits.md) | Three-layer enforcement of signed commits (local hook + CI + branch protection) | — |
| [`onboarding.md`](./onboarding.md) | 8-step human onboarding — first day, ~45 min | — |
| [`conventions.md`](./conventions.md) | How docs are organised, named, linked, published. Read once. | — |

## Performance

| Doc | Topic | Shopware reference |
| --- | --- | --- |
| [`caching.md`](./caching.md) | Varnish edge cache, Symfony HttpCache, Redis cache layers, Shopware caches | [Reverse HTTP cache](https://developer.shopware.com/docs/guides/hosting/infrastructure/reverse-http-cache.html) · [Caches](https://developer.shopware.com/docs/guides/hosting/performance/caches.html) · [Redis](https://developer.shopware.com/docs/guides/hosting/infrastructure/redis.html) |
| [`database.md`](./database.md) | Read-replica routing, ProxySQL, managed-DB switch, backups | [Database](https://developer.shopware.com/docs/guides/hosting/infrastructure/database.html) |
| [`object-storage.md`](./object-storage.md) | S3 / R2 / Backblaze for media + CDN | [Filesystem](https://developer.shopware.com/docs/guides/hosting/infrastructure/filesystem.html) |
| [`stresstest.md`](./stresstest.md) | k6 profiles (smoke/baseline/peak/endurance/spike/regression) + what they catch | [k6 performance test](https://developer.shopware.com/docs/guides/hosting/performance/k6.html) |
| [`frontend-performance.md`](./frontend-performance.md) | Template-level levers (Brotli, Early Hints, CDN, thumbnails) — theme code stays out of scope | [Performance Tweaks](https://developer.shopware.com/docs/guides/hosting/performance/performance-tweaks.html) |
| [`monitoring.md`](./monitoring.md) | LGTM stack — Prometheus, Loki, Tempo, Grafana, Pyroscope + blackbox external probes | — |

## Adapting the template

| Doc | Topic |
| --- | --- |
| [`template-reuse.md`](./template-reuse.md) | What was lifted from `ugg-unified-shop`, what's new, how to adapt to a new shop |
| [`testing-the-template.md`](./testing-the-template.md) | 5-tier testing strategy + `make verify` static/dry-run gate |
| [`ideas.md`](./ideas.md) | Backlog — ideas captured but not built yet, with sketches and reuse notes |
| [`decision-records/`](./decision-records/) | Architecture Decision Records — why a choice was made (use `/adr` to scaffold) |
| [`user-story-template.md`](./user-story-template.md) | Template for new stories (use `/new-story` to scaffold) |
| [`stories/`](./stories/) | User stories land here, one file per story |

## Claude Code integration

| File | Purpose |
| --- | --- |
| [`../CLAUDE.md`](../CLAUDE.md) | Auto-loaded project memory — conventions Claude must follow + where things live |
| [`../.claude/settings.json`](../.claude/settings.json) | Permissions allowlist — common reads pre-approved, destructive ops still prompt |
| [`../.claude/agents/`](../.claude/agents/) | Subagents: `shopware-plugin`, `shopware-frontend`, `shopware-test-writer`, `migration-helper` |
| [`../.claude/commands/`](../.claude/commands/) | Slash commands: `/new-story`, `/adr`, `/new-plugin`, `/new-test`, `/audit-shopware`, `/changelog` |

## Other entry points

| Where | What |
| --- | --- |
| [`../tests/README.md`](../tests/README.md) | Testing layout — PHPUnit suites, Playwright, plugin-local tests |
| [`../apm/README.md`](../apm/README.md) | OTel auto-instrumentation, Pyroscope continuous profiling, Tideways opt-in |
| [`../apm/pyroscope/README.md`](../apm/pyroscope/README.md) | Pyroscope wiring details |
| [`../apm/tideways/README.md`](../apm/tideways/README.md) | Tideways opt-in build arg |
| [`../monitoring/k8s/README.md`](../monitoring/k8s/README.md) | Helm values for the cluster-side LGTM install |
| [`../k3s/README.md`](../k3s/README.md) | Local k3s rehearsal cluster |
| [`../deploy/docker/README.md`](../deploy/docker/README.md) | `DEPLOYMENT_MODE=docker` pointer |
| [`../deploy/kubernetes/README.md`](../deploy/kubernetes/README.md) | `DEPLOYMENT_MODE=kubernetes` pointer |
| [`../deploy/managed-container/README.md`](../deploy/managed-container/README.md) | `DEPLOYMENT_MODE=managed-container` — TimmeHosting / Hetzner / DO |
| [`../deploy/bare-metal/README.md`](../deploy/bare-metal/README.md) | `DEPLOYMENT_MODE=bare-metal` — Deployer + deployment-helper |

## Conventions

- **Shopware references** appear as `> 📖 [link](...)` callouts in the
  prose, or in the "Reference" table above. Whenever this template makes
  a design choice that aligns with (or deviates from) Shopware's
  recommendation, the doc says so explicitly.
- **Snippets are runnable** unless prefixed with `# example —`. Copy-paste
  should work; if it doesn't, that's a doc bug worth filing.
- **Secrets** are never spelled out. Every credential in a snippet is an
  env-var reference (`${MYSQL_ROOT_PASSWORD}`, `${AWS_ACCESS_KEY_ID}`).
