# 🛒 Shopware Shop Deployment Template

A reusable starter for **Shopware 6** projects. Built around the **official
Shopware tooling** (`shopware/deployment-helper`, Deployer recipe,
`ghcr.io/shopware/docker-base` images, `shopware-cli`) — not hand-rolled
equivalents.

One repository, four deployment paths, one shared post-upload pipeline.

## 🧰 Requirements

Versions are the tested floor; later patch releases work.

| Tool | Min. version | Where to get |
| --- | --- | --- |
| Docker | 24+ | Docker Desktop / distro package |
| Docker Compose v2 | 2.20+ | bundled with recent Docker |
| make | any | distro package |
| git | 2.40+ | distro package (needed for signed commits) |
| gh (optional) | 2.30+ | brew / scoop / apt |
| shopware-cli (optional) | latest | https://sw-cli.fos.gg/ |

`make doctor` checks all of these + your local setup and prints a fix
suggestion for anything red.

## 📦 What you get

**🚀 Deploy**

- **One global config** — [`deployment.config`](./deployment.config) is the
  single source of truth for Shopware/PHP/Node versions, deploy mode, image
  references, install defaults
- **Four deploy modes**, dispatched by one Makefile target:
    - `docker` — local docker-compose only
    - `kubernetes` — Kustomize overlays + `kubectl apply`
    - `managed-container` — single Docker host (TimmeHosting, Hetzner, DO)
    - `bare-metal` — Deployer + SSH/rsync (no Docker on remote)
- **Identical post-upload pipeline** on all four paths: every mode ends with
  `vendor/bin/shopware-deployment-helper run` — plugins / migrations / theme
  compile / one-time tasks. Configured in [`.shopware-project.yml`](./.shopware-project.yml)
- **release-please** automates `CHANGELOG.md` + git tags from conventional
  commits; staging deploys auto-trigger on tag, production stays manual

**⚡ Run**

- **Edge cache** — official `ghcr.io/shopware/varnish-shopware` with xkey
  surrogate-key invalidation; opt-out per overlay
- **S3-ready filesystem** — Flysystem config for media/theme/thumbnail/sitemap
  pointing at AWS / R2 / Backblaze / MinIO
- **DB read-replica routing** via `DATABASE_REPLICA_*_URL` (opt-in)
- **Encrypted DB backups** to S3 + **weekly restore drill** that fails the
  Job if the backup doesn't restore cleanly
- **LGTM observability** — Prometheus + Loki + Tempo + Grafana + Pyroscope,
  open source first; Tideways via opt-in build arg
- **Blackbox probes** for external uptime + TLS-expiry alerts

**🛡 Security**

- **Signed commits** enforced at three layers (pre-commit hook + CI verify +
  branch protection)
- **Image scanning** with Trivy + CycloneDX SBOM
- **Secret scanning** with gitleaks
- **Two-layer rate limiting** — Ingress (per-IP) + Shopware app
  (per-account, per-route)
- **NetworkPolicies** default-deny; **CSP + security headers** at the
  Ingress; **Pod-Security** at `baseline`

**🛠 Develop**

- **Docker-based local dev** with full service mesh (MariaDB, OpenSearch,
  Redis, RabbitMQ, Mailpit) routed via Dinghy on `*.shop.docker`
- **Full test framework** — PHPUnit (unit + integration) + Playwright +
  PHPStan + PHP-CS-Fixer + PHPCS + PHPMD
- **k3s harness + k6 stresstest** with 6 profiles (smoke / baseline / peak /
  endurance / spike / regression) and a blocking CI perf gate
- **Renovate** auto-grouping (Shopware / Symfony / Doctrine / dev-deps)
  with auto-merge for safe updates
- **CI reports** — PHPUnit + Playwright counts auto-published into the PR
  body; Trivy findings + k6 perf summary in the Job-Summary panel

**🤖 Operate with Claude Code**

- **Auto-loaded project memory** in [`CLAUDE.md`](./CLAUDE.md) — conventions,
  file map, dos/don'ts
- **4 Shopware-aware subagents** — `shopware-plugin`, `shopware-frontend`,
  `shopware-test-writer`, `migration-helper`
- **6 slash commands** — `/new-story`, `/adr`, `/new-plugin`, `/new-test`,
  `/audit-shopware`, `/changelog`
- **Permissions allowlist** pre-approves routine read-only commands (no
  prompt-fatigue for `make help`, `git log`, `gh pr view`, …)

## 📁 Repository layout

```
.
├── deployment.config              Global config — versions, mode, registry, install defaults
├── .shopware-project.yml          Deployment Helper config + dump anonymize rules
├── deploy.php                     Deployer recipe (bare-metal path)
├── composer.json.example          Required composer deps for the template
├── compose.yaml                   Local dev stack (Dockware-based)
├── Makefile                       Single entry point — `make help` for the full list
├── phpunit.xml.dist               PHPUnit config (unit + integration suites)
├── .env.example  .env.test        Env templates — local dev + test runtime
├── auth.json.example              Composer auth template (GH + packages.shopware.com)
├── sales-channel-hosts.local.map.dist  Multi-channel local-dev host map
├── .fetch-dump.local.env.example  Named SSH source profiles for `make fetch-dump`
│
├── CLAUDE.md                      Project memory — auto-loaded by Claude Code
├── CONTRIBUTING.md  SECURITY.md   Adopter-facing process + disclosure docs
├── LICENSE                        MIT (template scaffolding only)
├── .editorconfig  .gitattributes  Cross-editor style + LF normalisation + merge=ours
├── .trivyignore                   Project-specific CVE allowlist (with mandatory why-comments)
│
├── docker/
│   ├── Dockerfile                 Multi-stage (build → app → worker) on Shopware base
│   ├── varnish/                   Self-contained Varnish + VCL (fallback; prefer official image)
│   ├── backup/                    Tiny image with mariadb-client + openssl + aws-cli
│   ├── nginx/ingress.conf.template  Local Dinghy ingress between containers
│   ├── php/                       php.ini, www.conf
│   └── scripts/                   entrypoint, healthcheck, sales-channel-domains, fetch-dump
│
├── .github/
│   ├── workflows/                 ci · deploy · performance · release-please · verify-signatures · wiki-sync
│   ├── ci/                        Pre-baked CI image + scripts/ — bootstrap, phpunit, playwright, teardown
│   ├── ISSUE_TEMPLATE/            bug_report.yml + feature_request.yml + config.yml
│   ├── PULL_REQUEST_TEMPLATE.md
│   ├── CODEOWNERS                 Review-routing skeleton (TODO placeholders)
│   ├── renovate.json              Auto-PR grouping + auto-merge rules
│   └── release-please-config.json
│
├── .githooks/                     pre-commit (gitleaks + style + signed-check) + commit-msg
│
├── .claude/
│   ├── settings.json              Permissions allowlist + env vars
│   ├── agents/                    4 Shopware-aware subagents
│   └── commands/                  6 slash commands
│
├── deploy/
│   ├── bare-metal/                Deployer-driven SSH deploys + shell fallback
│   ├── managed-container/         compose-based single-host deploys
│   ├── kubernetes/                Pointer to k8s/
│   └── docker/                    Pointer to compose.yaml
│
├── k8s/
│   ├── base/                      Deployments, StatefulSets, Ingress, HPA, NetworkPolicy,
│   │                              ServiceMonitor, Varnish, CronJobs (backup + restore-drill)
│   └── overlays/
│       ├── staging/
│       └── production/            inc. patch-volumes (S3 cutover) + tightened rate limits
│
├── k3s/
│   ├── install-k3s.sh             k3d-based local k3s
│   └── stresstest/                k6 Job + 6 scenarios incl. spike + CI regression gate
│
├── monitoring/
│   ├── compose.monitoring.yaml    Prometheus + Grafana + Loki + Tempo + Pyroscope + OTel
│   ├── prometheus/  loki/  promtail/  tempo/  grafana/   LGTM configs + dashboards
│   └── k8s/                       Helm values incl. blackbox exporter
│
├── apm/
│   ├── opentelemetry/             OTel Collector pipeline (traces + metrics + logs)
│   ├── pyroscope/                 Continuous PHP profiling
│   └── tideways/                  Commercial APM, opt-in
│
├── tests/
│   ├── unit/  integration/  e2e/  PHPUnit (unit + integration) + Playwright
│   └── README.md
│
├── config/packages/               shopware.yaml (rate-limiter + http-cache),
│                                  filesystem.yaml (S3), staging.yaml (system:setup:staging)
├── .build/                        phpstan.neon, php-cs-fixer.php, phpcs.xml, phpmd.xml, phpunit-bootstrap.php
├── scripts/load-config.sh         Sources deployment.config for non-Makefile consumers
├── .release-please-manifest.json
│
└── docs/                          See docs/README.md for the categorised index
    ├── README.md                  THE index — operations / performance / Claude / adapting
    ├── conventions.md             How docs are organised, named, linked, published
    ├── onboarding.md  architecture.md  deployment.md  caching.md  database.md
    ├── object-storage.md  monitoring.md  stresstest.md  frontend-performance.md
    ├── secrets.md  security.md  signed-commits.md
    ├── template-reuse.md  ideas.md  user-story-template.md
    ├── decision-records/          ADRs — 0000-template.md, 0001-deployment-modes.md, README
    └── stories/                   `<YYYY-MM-DD>-<slug>.md` (auto-published via wiki-sync)
```

## ⚙️ Global configuration

Everything you'd normally edit in multiple places lives in one file:

```bash
# deployment.config
SHOPWARE_VERSION=6.6.5.1
PHP_VERSION=8.3
NODE_VERSION=22

DEPLOYMENT_MODE=kubernetes    # docker | kubernetes | managed-container | bare-metal

REGISTRY=ghcr.io
IMAGE_APP=ghcr.io/example/shopware-shop/shopware

INSTALL_LOCALE=de-DE
INSTALL_CURRENCY=EUR
TIDEWAYS_ENABLE=0
```

`make config` prints the resolved values. Override any key on the command
line: `make image-build SHOPWARE_VERSION=6.6.6.0`.

## 🧩 Canonical Shopware tooling

This template wires up the **official Shopware tools**, not hand-rolled
equivalents:

| Concern | Tool | Configured in |
| --- | --- | --- |
| Post-upload pipeline | `shopware/deployment-helper` | [`.shopware-project.yml`](./.shopware-project.yml) |
| Bare-metal deploys | Deployer + deployment-helper | [`deploy.php`](./deploy.php) |
| Docker base | `ghcr.io/shopware/docker-base:8.3-frankenphp` | [`docker/Dockerfile`](./docker/Dockerfile) |
| Build pipeline | `ghcr.io/shopware/shopware-cli` → `shopware-cli project ci` | [`docker/Dockerfile`](./docker/Dockerfile) build stage |
| DB dumps | `shopware-cli project dump --clean --anonymize` | [`docker/scripts/fetch-dump.sh`](./docker/scripts/fetch-dump.sh) |
| Edge cache | `ghcr.io/shopware/varnish-shopware` (xkey VCL) | [`k8s/base/deployment-varnish.yaml`](./k8s/base/deployment-varnish.yaml) |
| Filesystem (S3) | `league/flysystem-async-aws-s3` (Shopware-recommended) | per-overlay patch — see [`docs/object-storage.md`](./docs/object-storage.md) |
| Rate limiter | Shopware built-in (login / oauth / contact / …) | [`config/packages/shopware.yaml`](./config/packages/shopware.yaml) |
| Staging mode | `bin/console system:setup:staging` + `config/packages/staging.yaml` | Runs as a one-time-task |
| GitHub Actions deploy | `shopware/github-actions/project-deployer` | [`.github/workflows/deploy.yml`](./.github/workflows/deploy.yml) |
| Log routing | `shopware/docker` composer package | Listed in [`composer.json.example`](./composer.json.example) |

## 🔐 Secrets

**Rule**: no secret is committed in plaintext. Every credential is read
from an environment variable; the env var is populated from a different
place depending on context.

- **Local dev (compose)** — `.env.local` (gitignored).
- **CI (GitHub Actions)** — `secrets.*` mapped into `env:` per job.
- **Kubernetes prod / staging** — `Secret/shopware-secrets`, referenced via `envFrom: secretRef`.
- **Bare-metal / managed-container** — `deploy/<mode>/env/<env>.env` (gitignored); paste the body into a GH Actions secret for CI deploys.

See [`docs/secrets.md`](./docs/secrets.md) for the **full checklist** —
which GitHub Actions secrets to set for each deployment mode, the K8s
Secret schema, rotation cadence, and the gitleaks audit step (already
wired into CI as a blocking gate).

## 💻 Local development

### One-time setup (per laptop)

Full walkthrough: [`docs/onboarding.md`](./docs/onboarding.md). Short form:

```bash
make setup                          # diagnose + copy env files + render
                                    # composer.json + wire git hooks
$EDITOR auth.json                   # fill in GH-OAuth + packages.shopware.com tokens
make up
open http://shop.docker             # admin / shopware
```

`make setup` is **idempotent** — safe to re-run any time and never
touches secrets you've filled in. It prints a TODO list at the end of
what still needs human input (typically: `auth.json` tokens + configure
signed commits).

`make up` boots the Dinghy reverse-proxy on demand, brings up every service
defined in [`compose.yaml`](./compose.yaml), and runs the idempotent
`entrypoint-dev.sh` setup script (composer install, DB import if
`dump.sql.gz` is present, admin user, cache clear). Subsequent runs skip the
heavy steps via the `.setup_complete` and `.db_imported` sentinels.

### Daily commands

`make help` prints the full target list, grouped and self-documenting.
The most-used commands:

| What you want | Command |
| --- | --- |
| **Stack lifecycle** ||
| Start the stack | `make up` |
| Stop containers (keep volumes) | `make stop` |
| Remove containers (keep volumes) | `make down` |
| Reset setup flags + re-run install | `make reset && make up` |
| Tail app logs | `make logs` |
| Drop into a shell on the app container | `make shell` |
| **Frontend dev** ||
| Storefront watcher (HMR) | `make watch-storefront` |
| Admin watcher (HMR) | `make watch-admin` |
| Rebuild storefront assets once | `make build-storefront` |
| Rebuild admin assets once | `make build-admin` |
| Recompile theme | `make theme` |
| Clear Symfony cache | `make cache` |
| **Database** ||
| Fresh-install Shopware schema (empty DB, no dump) | `make install-shop` |
| Fetch anonymized dump from a remote (named profile) | `make fetch-dump PROFILE=staging` |
| Fetch with interactive wizard (one-off / legacy migration) | `make fetch-dump` |
| Import an existing `dump.sql.gz` | `make import-dump` |
| Export the current DB to `dump.sql.gz` | `make export-dump` |
| Fix sales-channel domains for local | `make fix-domain` |
| Show current sales-channel domains | `make check-domain` |
| **Search & queues** ||
| Reindex storefront + admin + drain queue | `make reindex-all` |
| Drain Messenger queues once | `make messenger-consume` |
| Show queue depth | `make messenger-stats` |
| **Tests** ||
| Unit tests | `make test-unit` |
| Integration tests (boots kernel + DB) | `make test-integration` |
| Playwright e2e (first time: `make e2e-install`) | `make e2e` |
| Open last Playwright HTML report | `make e2e-report` |
| **Code quality** ||
| PHPStan | `make phpstan` |
| Auto-fix style | `make php-cs-fixer` |
| Dry-run style check (same scope as CI) | `make php-cs-fixer-check` |
| PHPCS / PHPMD | `make phpcs` / `make phpmd` |
| **Monitoring stack** (optional) ||
| Start LGTM stack (Prometheus/Grafana/Loki/Pyroscope) | `make monitoring-up` |
| Stop it | `make monitoring-down` |
| **Bootstrap + sanity** ||
| One-shot initial bootstrap (idempotent) | `make setup` |
| Diagnose missing tools / files | `make doctor` |
| Tier-1 static + dry-run checks | `make verify` |
| Print resolved versions + deploy mode | `make config` |
| Print every target | `make help` |

### Service URLs (local)

Every URL below resolves via the Dinghy proxy. The base host is set by
`PROJECT_DOMAIN` in [`deployment.config`](./deployment.config) (default:
`shop.docker`) — change that one value and the whole table rewrites itself.

**Application + watchers (after `make up`)**

| Service | URL | Default credentials |
| --- | --- | --- |
| Storefront | http://shop.docker | — |
| Wildcard sales channels | http://*.shop.docker | — |
| Admin panel | http://shop.docker/admin | `admin` / `shopware` |
| Storefront HMR watcher | http://watch-storefront.shop.docker | — |
| Admin HMR watcher | http://watch-admin.shop.docker | — |

**Backing services (after `make up`)**

| Service | URL | Default credentials |
| --- | --- | --- |
| Mailpit (caught emails) | http://mail.shop.docker | — |
| Adminer (DB browser) | http://adminer.shop.docker | server=`mariadb`, user=`root`, password=`$MYSQL_ROOT_PASSWORD` |
| Redis Commander | http://redis.shop.docker | — |
| RabbitMQ management | http://rabbitmq.shop.docker | `shopware` / `shopware` |
| OpenSearch REST | http://opensearch.shop.docker | — |
| OpenSearch Dashboards | http://opensearch-dashboards.shop.docker | — |

**Observability (after `make monitoring-up`)**

| Service | URL | Default credentials |
| --- | --- | --- |
| Grafana | http://grafana.shop.docker | `admin` / `admin` |
| Prometheus | http://prometheus.shop.docker | — |
| Loki API | http://loki.shop.docker | — |
| Pyroscope | http://pyroscope.shop.docker | — |
| Tempo (traces) | _internal-only_ — queried via Grafana | — |
| OTel Collector | _internal-only_ — receives OTLP from the app | — |

**Direct ports (not behind the proxy)**

Available on `localhost` via Docker port publishing — useful for IDE
integration (DB clients, Redis CLI, etc.). The exact host port is
randomised by Compose; resolve with `docker compose port <service> <port>`:

```bash
docker compose port mariadb 3306    # → 0.0.0.0:54321 (example)
docker compose port redis 6379
docker compose port rabbitmq 5672
docker compose port opensearch 9200
```

All credentials default to **local-dev only** values from `.env.example`.
Override in `.env.local` (gitignored). See [`docs/secrets.md`](./docs/secrets.md)
for the full inventory.

### Service URLs (Kubernetes)

In-cluster DNS (`<service>.<namespace>.svc.cluster.local`); accessed from
the outside via the Ingress configured in the overlay.

| Service | In-cluster DNS | External (per overlay) |
| --- | --- | --- |
| Storefront | `shopware-web.shopware-{staging,production}` | configured in `k8s/overlays/<env>/patch-ingress.yaml` |
| MariaDB | `mariadb.shopware-{staging,production}:3306` | not exposed |
| Redis | `redis.shopware-{staging,production}:6379` | not exposed |
| RabbitMQ | `rabbitmq.shopware-{staging,production}:5672` (mgmt: `:15672`) | not exposed |
| OpenSearch | `opensearch.shopware-{staging,production}:9200` | not exposed |
| Prometheus / Grafana / Loki / Tempo / Pyroscope | `*.observability` | port-forward or expose via Ingress |
| k6 stresstest target | `shopware-web.shopware-staging` | runs in-cluster (`k3s/stresstest/k6-job.yaml`) |

For ad-hoc access to internal services:

```bash
kubectl -n observability port-forward svc/kube-prometheus-stack-grafana 3000:80
kubectl -n shopware-staging exec -it deploy/shopware-web -- bin/console <cmd>
```

### When something feels stuck

```bash
make reset && make up        # re-runs setup (composer + DB import + admin user)
make cache                   # clear Symfony cache only
make reindex-all             # rebuild search + drain queue
docker compose down -v       # nuclear option — wipes volumes too

# 403 on / + 404 on /admin → Shopware skeleton missing or masked
make scaffold-shop           # extracts public/index.php + Kernel + config from Dockware
make reset && make up

# "ClassNotFoundError: App\Kernel" → stale vendor/ in the named volume
make dump-autoload           # fast: regenerates only the autoloader
# or, if dump-autoload doesn't help:
make composer-install        # full vendor refresh

# "Table 'shopware.sales_channel' doesn't exist" → empty DB, schema missing
make install-shop            # bin/console system:install --basic-setup (admin / shopware)
```

## 🚀 Deploy

```bash
# 1. Choose your mode
sed -i 's/^DEPLOYMENT_MODE=.*/DEPLOYMENT_MODE=managed-container/' deployment.config

# 2. Wire up per-env config (gitignored)
cp deploy/managed-container/env/example.env deploy/managed-container/env/production.env
$EDITOR deploy/managed-container/env/production.env

# 3. Deploy
make deploy ENV=production

# Emergency rollback
make rollback ENV=production
```

CI handles the same flow via `.github/workflows/deploy.yml` — pick the
environment from the workflow dispatch dropdown. See
[`docs/deployment.md`](./docs/deployment.md) for the full pipeline.

## 🏋️ k3s + stresstest

```bash
./k3s/install-k3s.sh             # one-shot local k3s install
kubectl apply -k k8s/overlays/staging
make stresstest                  # k6 Job runs inside the cluster
```

## 📊 Observability

```bash
make monitoring-up               # Prometheus + Grafana + Loki + Tempo + Pyroscope on docker
open http://grafana.shop.docker  # admin / admin (override in .env.local)
```

The stack joins the same Docker network as the shop, so Prometheus scrapes
your services without extra config. See [`docs/monitoring.md`](./docs/monitoring.md)
for the K8s helm-values + dashboard list.

## 🧪 Tests

Two distinct things to test, two distinct flows:

**The shop you build on top of the template:**

```bash
make test-unit           # PHPUnit unit suite
make test-integration    # PHPUnit integration (boots kernel + DB)
make e2e                 # Playwright against the local storefront
make phpstan php-cs-fixer-check phpcs phpmd   # static analysis
```

See [`tests/README.md`](./tests/README.md) for layout + conventions.

**The template itself — 5-tier strategy:**

```bash
make verify              # Tier 1 — static + dry-run, < 30s, zero side effects
make up && curl shop.docker  # Tier 2 — local end-to-end smoke
act pull_request         # Tier 3 — full CI rehearsal via nektos/act
./k3s/install-k3s.sh     # Tier 4 — k3s rehearsal incl. backup + restore-drill
make deploy ENV=staging  # Tier 5 — real-deploy smoke (RC only)
```

Full strategy: [`docs/testing-the-template.md`](./docs/testing-the-template.md).
`make verify` is also the first gate in CI, so every PR catches drift in
< 30s before the heavy jobs run.

## 📚 Documentation

Two views of the same source — pick whichever fits your context:

| View | When |
| --- | --- |
| **Source** — [`docs/README.md`](./docs/README.md) | Editing, PR review, IDE search |
| **GitHub Wiki** | Reading, sharing links, full-text search |

The Wiki is **auto-published** from `docs/` on every push to `main` via
[`.github/workflows/wiki-sync.yml`](./.github/workflows/wiki-sync.yml).
Edit `docs/`, never the wiki directly — the next push overwrites it.
Conventions: [`docs/conventions.md`](./docs/conventions.md).

**Operations**

- [`docs/onboarding.md`](./docs/onboarding.md) — 8-step first-day setup
- [`docs/architecture.md`](./docs/architecture.md) — process model, data flow, failure modes
- [`docs/deployment.md`](./docs/deployment.md) — CI + the four deploy paths in detail
- [`docs/secrets.md`](./docs/secrets.md) — full secret inventory + rotation
- [`docs/security.md`](./docs/security.md) — image scanning, rate limiting, NetworkPolicies
- [`docs/signed-commits.md`](./docs/signed-commits.md) — three-layer enforcement setup

**Performance**

- [`docs/caching.md`](./docs/caching.md) — Varnish, Symfony HttpCache, Redis layers
- [`docs/database.md`](./docs/database.md) — read replicas, ProxySQL, managed DBs, backups
- [`docs/object-storage.md`](./docs/object-storage.md) — S3 / R2 / Backblaze for media + CDN
- [`docs/monitoring.md`](./docs/monitoring.md) — LGTM stack, dashboards, alerts
- [`docs/stresstest.md`](./docs/stresstest.md) — k6 profiles + what they catch
- [`docs/frontend-performance.md`](./docs/frontend-performance.md) — template-level levers (theme code stays out of scope)

**Adapting + evolving**

- [`docs/template-reuse.md`](./docs/template-reuse.md) — adapting this template to a new shop
- [`docs/testing-the-template.md`](./docs/testing-the-template.md) — 5-tier strategy + `make verify`
- [`docs/conventions.md`](./docs/conventions.md) — how docs are organised
- [`docs/decision-records/`](./docs/decision-records/) — ADRs (use `/adr` in Claude Code)
- [`docs/user-story-template.md`](./docs/user-story-template.md) — story template (use `/new-story`)
- [`docs/ideas.md`](./docs/ideas.md) — backlog of unbuilt ideas with design sketches

**Pointers**

- [`tests/README.md`](./tests/README.md) — testing layout
- [`apm/README.md`](./apm/README.md) — OTel / Pyroscope / Tideways
- [`monitoring/k8s/README.md`](./monitoring/k8s/README.md) — Helm install for LGTM + blackbox
- [`k3s/README.md`](./k3s/README.md) — local k3s rehearsal cluster
- [`deploy/managed-container/README.md`](./deploy/managed-container/README.md) — TimmeHosting-style hosters
- [`deploy/bare-metal/README.md`](./deploy/bare-metal/README.md) — Deployer-driven SSH deploys

## 📄 Project files (top-level)

- [`CLAUDE.md`](./CLAUDE.md) — auto-loaded Claude Code project memory + conventions
- [`CONTRIBUTING.md`](./CONTRIBUTING.md) — PR process, CI gates, commit conventions
- [`SECURITY.md`](./SECURITY.md) — vulnerability disclosure (private, never via public issue)
- [`LICENSE`](./LICENSE) — MIT for the template scaffolding

## 📜 License

The template scaffolding is **MIT**. Replace the placeholder copyright
holder in [`LICENSE`](./LICENSE) before going to production.

Your shop code, plugins, and any license-encumbered dependencies
(Tideways, paid Shopware extensions, your team's IP) carry their own
terms — this license covers the scaffolding only.
