# Testing the template

How we verify the template itself works — distinct from testing the
Shopware shop built on top of it. Five tiers, fastest to slowest. Run
the lower tiers often, the higher tiers before tagged releases.

| Tier | What it catches | How long | When |
| --- | --- | --- | --- |
| 1. **Syntactic + dry-run** | YAML / JSON / Bash / Kustomize / Helm parse errors, manifest schema breaks, composer.json drift | < 30 s | every commit (locally), CI `config` job |
| 2. **Local end-to-end** | `make up` actually boots; storefront serves 200; tests scaffolding works | 5-15 min | before a deploy-mode change PR; before tagging a release |
| 3. **CI rehearsal** (`act`) | The pre-baked CI image builds + boots; PHPUnit + Playwright runs; image build + Trivy pass | 10-30 min | when changing CI workflows or the Dockerfile |
| 4. **k3s rehearsal** | K8s manifests deploy; Varnish + ingress + observability come up; HPA reacts; backups + restore-drill cycle works | 30-60 min | before a major-version bump; quarterly DR check |
| 5. **Real-deploy smoke** | The whole `make deploy ENV=staging` chain end-to-end against a real remote | hours-to-days | release candidates only |

Most of the time you live in tiers 1-3. Tiers 4-5 are for big changes.

---

## Tier 1 — `make verify`

Single command, runs every static check the template owns. Zero side
effects, no Docker, no network. Use it as your pre-PR smoke.

```bash
make verify
```

What it does:

| Check | Tool | What it catches |
| --- | --- | --- |
| Deployment config loads | `scripts/load-config.sh` | typos / missing vars in `deployment.config` |
| `composer.json` matches template | `make composer-json-check` | drift between `deployment.config` SHOPWARE_VERSION and the rendered constraint |
| GitHub workflows valid | `actionlint` | YAML errors, broken `${{ … }}` references, bad action versions |
| Shell scripts | `shellcheck` | unquoted vars, broken pipes, missing exits |
| K8s manifests parse | `kustomize build k8s/overlays/*` | YAML errors, missing files referenced in `kustomization.yaml` |
| K8s manifests valid | `kubectl apply -k --dry-run=server` (if cluster reachable) or `--dry-run=client` (no cluster) | schema errors, deprecated APIs |
| Helm values parse | `helm template --debug` against each values file | template syntax errors |
| YAML hygiene | `yq` parses every `*.yml` / `*.yaml` | invalid YAML |
| JSON hygiene | `jq` parses every `*.json` (incl. renovate.json) | trailing commas, syntax |
| Renovate config | `renovate-config-validator` (if available) | schema errors |
| Markdown links (optional) | `lychee` if available | dead `[text](./foo.md)` refs |

Each individual tool is optional — if `shellcheck` isn't installed,
`make verify` skips that step with a warning rather than failing.

---

## Tier 2 — Local end-to-end smoke

After `make verify` passes, **boot the stack**:

```bash
make doctor                       # sanity-check the local environment
make up                           # boots compose stack
curl -fsSL http://shop.docker/ | head -1   # → HTTP/1.1 200 OK
make test-unit                    # the smoke test passes
```

Optional next levels:

```bash
make e2e-install                  # one-time: Playwright + Chromium
make e2e                          # smoke spec passes
make monitoring-up                # LGTM stack reachable
open http://grafana.shop.docker

make image-build                  # produces the prod image (no push)
```

The verify step **only proves the artefacts are syntactically valid**.
Tier 2 proves they actually do something. Worth doing before any PR
that touches `compose.yaml`, the Dockerfile, the deploy scripts, or
the entrypoint shell.

---

## Tier 3 — Full CI rehearsal locally with `act`

When you change CI workflows, you don't want to find out it's broken
after pushing. [`act`](https://github.com/nektos/act) runs GitHub
Actions locally:

```bash
# install act (macOS):
brew install act

# run the whole ci.yml on a simulated PR:
act pull_request --workflows .github/workflows/ci.yml --container-architecture linux/amd64

# run only one job:
act pull_request -j tests --workflows .github/workflows/ci.yml

# wiki sync (against your fork):
act push --workflows .github/workflows/wiki-sync.yml --secret-file .secrets
```

`.secrets` is a gitignored env file with the secrets `act` should
inject — see [`.github/ci/scripts/bootstrap.sh`](../.github/ci/scripts/bootstrap.sh) for the
list our workflows actually use. Common minimum:

```env
COMPOSER_AUTH_TOKEN=ghp_…
SHOPWARE_PACKAGES_TOKEN=…
GITHUB_TOKEN=ghp_…
```

Faster alternative if you don't need full workflow simulation:

```bash
make ci-bootstrap                 # builds + boots the pre-baked CI image
make ci-phpunit                   # PHPUnit inside the image
make ci-e2e                       # Playwright against the in-container storefront
make ci-teardown WITH_LOGS=1
```

This is what the CI workflow runs — minus the GitHub-specific scaffolding.

---

## Tier 4 — k3s rehearsal

The Kubernetes path is the most failure-prone because manifests can
parse fine but still misbehave at runtime. Catch this before a real
cluster sees it.

```bash
./k3s/install-k3s.sh              # 2-5 min, one-shot local k3s
kubectl apply -k k8s/overlays/staging
kubectl -n shopware-staging rollout status deploy/shopware-web --timeout=10m
kubectl -n shopware-staging rollout status deploy/shopware-worker --timeout=10m

# Smoke
kubectl -n shopware-staging port-forward svc/shopware-web 8000:80 &
curl -fsSL http://localhost:8000/

# Performance
make stresstest                   # k6 Job, baseline profile

# Disaster-recovery
kubectl -n shopware-staging create job --from=cronjob/shopware-db-backup manual-backup
kubectl -n shopware-staging logs job/manual-backup -f
kubectl -n shopware-staging create job --from=cronjob/shopware-restore-drill manual-drill
kubectl -n shopware-staging logs job/manual-drill -f
```

What this catches that earlier tiers don't:

- Probe timing — readiness too eager (failing health checks) vs too
  patient (Service routes to dead pods during rollout)
- PVC sizing — backups too big for the throwaway volume
- NetworkPolicy gaps — pod can't reach the namespace it needs
- HPA reactivity — does scaling kick in before tail-latency rises?
- Backup → restore round-trip — actually verify the encrypted dump
  decrypts AND restores AND the schema is sane

---

## Tier 5 — Real-deploy smoke

Only when shipping a release candidate. Procedure depends on your
`DEPLOYMENT_MODE`:

| Mode | What to run |
| --- | --- |
| `kubernetes` | `make deploy ENV=staging` against a real cluster, then watch Grafana + run k6 baseline |
| `managed-container` | `make deploy ENV=staging` against the real Docker host |
| `bare-metal` | `vendor/bin/dep deploy env=staging` |

Document any deviations from the expected behaviour in a story file
under `docs/stories/` and link them from the next ADR.

---

## What the verify target does NOT cover

Be honest about the gap:

- **Plugin compatibility** — `shopware-cli extension validate` runs per
  plugin in the CI `shopware-validate` job, not in `make verify`. The
  reason: it needs network access to packages.shopware.com.
- **Live cluster state** — `kubectl --dry-run=server` requires cluster
  access, so `make verify` falls back to `--dry-run=client`. Schema
  warnings that need server-side validation won't surface.
- **Real plugin code** — the template ships zero plugins. Adopters
  inherit the CI gates for their own plugin code, but `make verify` on
  the empty template can't exercise them.
- **External integrations** — payment, ERP, PIM, mail providers. These
  belong to the shop, not the template.

---

## Quick reference

```bash
make verify                       # Tier 1 — always
make up && make test-unit && make e2e  # Tier 2 — before PR
act pull_request                  # Tier 3 — when touching workflows
./k3s/install-k3s.sh && kubectl apply -k k8s/overlays/staging  # Tier 4 — pre-release
make deploy ENV=staging           # Tier 5 — RC only
```
