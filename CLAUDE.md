# CLAUDE.md

This file is loaded automatically by Claude Code at session start. Keep it
concise — point at deeper docs rather than duplicating them.

## What this repo is

A **Shopware 6 deployment template**. The shop itself is brought by the
team that adopts it; this repo provides:

- Docker dev + Kubernetes / managed-container / bare-metal deploy paths
- CI/CD with the official Shopware tools (`shopware/deployment-helper`,
  Deployer recipe, `ghcr.io/shopware/docker-base`, `shopware-cli`)
- LGTM observability stack (Prometheus, Loki, Tempo, Grafana, Pyroscope)
- k6 stresstests with regression gate
- Security gates (gitleaks, Trivy, signed commits, rate limiters,
  NetworkPolicies)
- Test framework (PHPUnit unit + integration, Playwright e2e, PHPStan,
  PHP-CS-Fixer, PHPCS, PHPMD)

**Single source of truth**: [`deployment.config`](./deployment.config).
Every version pin, deploy mode, image reference lives there. Override on
the CLI: `make image-build SHOPWARE_VERSION=6.6.6.0`.

## Where things are

| You want… | Look at… |
| --- | --- |
| Deploy modes / Deployer recipe | [`deploy/`](./deploy/) and [`deploy.php`](./deploy.php) |
| Shopware deployment-helper config | [`.shopware-project.yml`](./.shopware-project.yml) |
| K8s manifests | [`k8s/base/`](./k8s/base/) + [`k8s/overlays/`](./k8s/overlays/) |
| Docker prod image | [`docker/Dockerfile`](./docker/Dockerfile) (FrankenPHP-based) |
| Local dev stack | [`compose.yaml`](./compose.yaml) (Dockware) |
| CI workflows | [`.github/workflows/`](./.github/workflows/) |
| Documentation | [`docs/README.md`](./docs/README.md) — categorised index |
| Backlog of unbuilt ideas | [`docs/ideas.md`](./docs/ideas.md) |

## Conventions Claude MUST follow

These are not preferences — they're enforced by CI gates. Skipping them
means red builds.

1. **Signed commits** — `commit.gpgsign=true` (SSH or GPG). See
   [`docs/signed-commits.md`](./docs/signed-commits.md). The pre-commit
   hook blocks unsigned commits locally; `verify-signatures.yml` blocks
   them in CI.
2. **Conventional Commits** — `feat:` / `fix:` / `perf:` / `security:` /
   `deps:` / `refactor:` / `docs:` / `test:` / `build:` / `ci:` /
   `chore:`. The `commit-msg` hook warns; release-please uses these to
   generate `CHANGELOG.md`.
3. **No hardcoded secrets** — every credential is an env-var reference.
   Real values live in `.env.local` (local), GitHub Actions secrets
   (CI), K8s Secrets (cluster). gitleaks blocks committed secrets.
4. **Use the official Shopware tools** — `shopware-deployment-helper`,
   the `shopware/docker-base` image, `shopware-cli`. We don't ship
   hand-rolled alternatives when an upstream tool exists.
5. **Shopware-version drift** — the `compatibility_date` in
   `.shopware-project.yml` controls plugin compat checks. Update it
   alongside `SHOPWARE_VERSION` in `deployment.config`.
6. **`composer.json` is rendered, not edited** — it comes from
   `composer.json.example` + `deployment.config` via `make composer-json`.
   `shopware/*` constraints pin to the EXACT `SHOPWARE_VERSION`. Edit the
   template; CI's `composer-json-check` blocks drift.

## Conventions Claude SHOULD follow

Project preferences. Push back if there's a good reason, but the default
is yes.

- **Tests over fixtures-in-YAML** — PHP builder pattern, not YAML/JSON
  fixtures. See [`docs/ideas.md`](./docs/ideas.md) for the exporter
  design and [`tests/integration/`](./tests/integration/) for the
  current style.
- **Integration tests use `IntegrationTestBehaviour`** — auto-rollback
  per test. Never leave fixtures lying around.
- **Twig overrides via `sw_extends` + `sw_block`** — don't copy whole
  upstream templates. Override only the blocks that change.
- **Admin modules in Vue** — Shopware 6.6 uses Vue 2; 6.7+ uses Vue 3.
  Check `SHOPWARE_VERSION` before choosing API style.
- **Storefront JS via `PluginManager.register()`** — Shopware's plugin
  system, not arbitrary scripts in the page.
- **DAL writes via Repository, not raw SQL** — unless there's a perf
  reason documented in an ADR.
- **DI in `services.xml`** — not PHP attributes (Shopware convention
  through 6.6; may change in 6.7+).
- **Run formatters before committing** — `make php-cs-fixer` for PHP.
  The pre-commit hook also dry-runs it.

## Workflows that exist

Slash commands available in this repo (`.claude/commands/`):

- `/new-story` — scaffolds a user story with INVEST + acceptance criteria
- `/adr` — creates an Architecture Decision Record
- `/new-plugin <PluginName>` — scaffolds a Shopware plugin
- `/new-test <type> <subject>` — generates a unit/integration test
- `/audit-shopware` — Shopware-flavoured security + perf audit
- `/changelog` — previews the release-please CHANGELOG block

Subagents available (`.claude/agents/`):

- `shopware-plugin` — plugin code (PHP + DI + migrations + tests)
- `shopware-frontend` — Vue admin modules, Storefront JS, Twig
- `shopware-test-writer` — fixtures + integration tests
- `migration-helper` — Shopware version upgrades + breaking changes

## What Claude should NOT do without checking

- **Run `make deploy ENV=production`** — always confirm first.
- **Push to `main`** — only via PRs that have passed CI.
- **Edit `k8s/base/secret.yaml` values** — placeholders only; real
  values come from a secret manager.
- **Bump `SHOPWARE_VERSION`** — that's a project, not a chore.
  Run `/audit-shopware` first and use the migration-helper agent.
- **`composer update` without `--lock`** — composer.lock is committed
  for a reason.
- **Skip `--no-verify`** on commits — it bypasses the local signing
  + secrets check. CI will catch it but you'll get a red PR.

## Quick reference

```bash
make help                     # every target, grouped + colorised
make config                   # resolved version pins + deploy mode
make up                       # local dev stack
make test-unit test-integration e2e
make deploy ENV=staging       # dispatches by DEPLOYMENT_MODE
make rollback ENV=staging
make setup-hooks              # one-time, points git at .githooks/
```

When in doubt: [`docs/README.md`](./docs/README.md).
