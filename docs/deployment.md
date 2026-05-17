# Deployment

Four deployment paths, one shared pipeline. Pick via `DEPLOYMENT_MODE` in
[`deployment.config`](../deployment.config):

| Mode                | Driven by                                                  | When to use                                       |
| ------------------- | ---------------------------------------------------------- | ------------------------------------------------- |
| `docker`            | `docker compose` only                                       | Local development                                 |
| `kubernetes`        | Kustomize overlays + `kubectl apply`                        | Cloud, multi-replica, autoscaling                 |
| `managed-container` | `docker compose pull && up -d` via SSH                      | Single Docker host (TimmeHosting, Hetzner, DO)    |
| `bare-metal`        | **Deployer (`deploy.php`)** + `shopware-deployment-helper`  | Single-host, managed PHP, no container runtime    |

All four converge on the same canonical post-upload pipeline — Shopware's
official `vendor/bin/shopware-deployment-helper run`, configured in
[`.shopware-project.yml`](../.shopware-project.yml):

- plugin install / update / activate / deactivate
- DB migrations
- theme compile + asset install
- one-time tasks (idempotent data fixes)
- store login

This means **what happens after the code lands on the box is identical** no
matter how the code got there.

References:
- [Shopware Deployment Helper](https://developer.shopware.com/docs/guides/hosting/installation-updates/deployments/deployment-helper.html)
- [Shopware Deployer integration](https://developer.shopware.com/docs/guides/hosting/installation-updates/deployments/deployment-with-deployer.html)
- [Shopware Docker images](https://developer.shopware.com/docs/guides/hosting/installation-updates/docker.html)
- [Creating a staging instance](https://developer.shopware.com/docs/guides/hosting/installation-updates/creating-a-staging-instance.html)

## Global configuration

Versions, image references, deploy mode, install defaults — all live in one
file: `deployment.config`. The Makefile sources it, Docker build args
default to its values, GitHub Actions reads it once and fans the outputs to
every job. Override any key on the command line:

```bash
make image-build SHOPWARE_VERSION=6.6.6.0 TIDEWAYS_ENABLE=1
```

## CI pipeline (`.github/workflows/ci.yml`)

## CI pipeline (`.github/workflows/ci.yml`)

```
PR opened ──┬──▶ quality          (PHPStan + PHP-CS-Fixer)   ▶ green
            ├──▶ lint             (TypeScript)              ▶ green
            ├──▶ audit            (composer audit + npm audit) ▶ green
            ├──▶ shopware-validate (shopware-cli extension)   ▶ green
            │
            └─after-static─▶ tests       (PHPUnit + Playwright)
                          ▶ image       (multi-target docker build + push)
```

### Why the pre-baked CI image is the right answer

Every plain-vanilla "compose up + composer install + theme:compile + plugin:install"
CI run is **5-10 minutes of wall-clock waste before the first test even
starts**. By committing those steps to a Dockerfile (`.github/ci/Dockerfile`),
Docker's layer cache reuses everything that hasn't changed:

- composer.lock unchanged → composer install layer hit
- src/, config/, custom/ unchanged → theme:compile layer hit
- only the leaf source changed → seconds to rebuild

In CI this routinely cuts test setup time **from 8 min to ~30 s**.

## Deploy pipeline (`.github/workflows/deploy.yml`)

Triggered manually (`workflow_dispatch`) or by another workflow
(`workflow_call`). Reads `DEPLOYMENT_MODE` from `deployment.config` and
dispatches to one of two jobs:

### `deploy-kubernetes` (DEPLOYMENT_MODE=kubernetes)

1. **Loads kubeconfig** from a GitHub Actions Environment secret.
2. **Pins image tags** via `kustomize edit set image` to the commit SHA.
3. **Runs a one-shot migration Job** with the new image — the entrypoint's
   `migrate` role calls `shopware-deployment-helper run`. If it fails, the
   rollout never starts and the old pods keep serving traffic.
4. **Applies the overlay** (`kubectl apply -k k8s/overlays/<env>`).
5. **Waits for rollout** (`kubectl rollout status` with a timeout).
6. **Smoke tests** the public URL — bails the pipeline if it returns non-200
   after a short retry loop.

### `deploy-bare-metal` (DEPLOYMENT_MODE=bare-metal)

Uses the **official `shopware/github-actions/project-deployer` action**
which wraps Deployer + the deployment-helper.

Inside, Deployer executes the tasks defined in `deploy.php` at repo root:

1. `deploy:prepare` — initial setup on the remote
2. `deploy:vendors` → `shopware:composer:install` — `composer install --no-dev`
3. `deploy:shared` — symlink shared dirs/files (`.env.local`, `config/jwt`, `public/media`, …)
4. `deploy:writable` — chmod the writable tree
5. `shopware:touch_install_lock` — write `install.lock`
6. `shopware:deployment-helper` — `vendor/bin/shopware-deployment-helper run`
7. `deploy:symlink` — atomic `current` symlink swap
8. `shopware:fpm:reload` — reload PHP-FPM to flush opcache
9. `shopware:smoke-test` — HTTP probe the public URL
10. `deploy:cleanup` — prune old releases

A shell-only fallback lives at `deploy/bare-metal/deploy.sh` for hosts that
can't run Deployer locally.

### `deploy-managed-container` (DEPLOYMENT_MODE=managed-container)

For hosters that give you a Docker host but no Kubernetes — **TimmeHosting
Container Hosting**, Hetzner Cloud, DigitalOcean Droplets, generic VPS. The
GitHub job:

1. Installs the deploy SSH key from `secrets.DEPLOY_SSH_KEY`
2. Materialises `deploy/managed-container/env/<env>.env` from `secrets.MANAGED_CONTAINER_ENV`
3. Resolves the image tag (`inputs.image_tag` or `github.sha`)
4. Runs [`deploy/managed-container/deploy.sh`](../deploy/managed-container/deploy.sh)

The script:

1. SSHes to the host, logs in to GHCR with the actor token
2. `docker compose pull` — fetches the new image
3. `docker compose --profile deploy run --rm migrate` — runs the deployment-helper
4. `docker compose up -d --remove-orphans web worker cron` — rolling restart
5. Smokes the public URL
6. Records the tag at `~/.shopware-deploy/<env>/last-good-tag` for rollback

Rollback flips `last-good-tag.prev` back into place and re-runs the deploy:

```bash
ENV=production deploy/managed-container/rollback.sh
```

See [`deploy/managed-container/README.md`](../deploy/managed-container/README.md)
for the TimmeHosting-specific quickstart and the toggles for hoster-managed
DB / Redis vs in-stack services.

## Versioning

`release-please` watches commits to `main`, keeps an open "chore: release
X.Y.Z" PR that bumps `PROJECT_VERSION` in `deployment.config` and writes
`CHANGELOG.md`. Merging it cuts a `vX.Y.Z` git tag + GitHub Release.

Conventional-commit prefixes drive the bump:

| Prefix | Bump | CHANGELOG section |
| --- | --- | --- |
| `feat:` | minor | Features |
| `fix:` | patch | Bug Fixes |
| `perf:` | patch | Performance |
| `security:` | patch | Security |
| `deps:` | patch | Dependencies |
| `<type>!:` or `BREAKING CHANGE:` in body | major | (under each section) |
| `refactor:` `docs:` `test:` `build:` `ci:` `chore:` | none | hidden |

The local `.githooks/commit-msg` hook warns on non-conforming subjects
(set `COMMIT_MSG_STRICT=1` in your shell to hard-block).

### Using tags for bare-metal deploys

The Deployer release directory naturally uses the SHA — but for
human-readable rollback conversations, pass a tag:

```bash
make deploy ENV=production REVISION=v1.4.2
```

The release dir on the host becomes `releases/20260516-141055-v1.4.2`
instead of `releases/20260516-141055-7af3b2c`. Rolling back to "the
version we had on Tuesday" then becomes obvious in the file listing.

### Auto-deploy to staging on release

When release-please merges a release PR, the `release-please` workflow
auto-triggers `deploy.yml` against the `staging` environment with the
new tag. Production stays manual (`workflow_dispatch`) — promote when
ready via the same dropdown.

## Rollback

```bash
# Roll back to the previous ReplicaSet for either Deployment:
kubectl -n shopware-production rollout undo deploy/shopware-web
kubectl -n shopware-production rollout undo deploy/shopware-worker

# Or pin to a specific image tag:
kubectl -n shopware-production set image deploy/shopware-web shopware=ghcr.io/.../shopware:<sha>
```

The Pre-deploy migration Job is **idempotent** (named with the image short
SHA), so re-running the same commit re-applies cleanly.

## Cache busting on config change

The base Deployments carry a `checksum/config` annotation in their pod
template. When you update the ConfigMap, the overlay (or a sidecar hook in
CI) should overwrite that annotation so the kubelet sees a "spec change"
and rolls the pods. The Kustomize `configMapGenerator` in the overlays
already does the hashing — Kustomize creates a new ConfigMap on every change
of its contents (`name-suffix=hash`), which forces a rollout automatically.

## Production-only checklist

- [ ] Replace the in-cluster `mariadb` StatefulSet with a managed DB
- [ ] Move `media/`, `thumbnail/`, `theme/`, `bundles/` to a real
      ReadWriteMany volume or an object storage backend (S3 + CDN)
- [ ] Provision an external Redis (ElastiCache / Aiven / Upstash)
- [ ] Replace the single-node OpenSearch with the OpenSearch Operator
      or a managed offering
- [ ] Configure cert-manager to use the production ACME server
- [ ] Wire Alertmanager to your paging channel (Slack / PagerDuty)
- [ ] Lock down NetworkPolicies after running them in audit mode for a week
- [ ] Set up External Secrets / SOPS / Sealed Secrets for the Secret manifest
