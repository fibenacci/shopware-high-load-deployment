# Secrets management

**Single rule**: no secret is committed in plaintext. Every credential is
read at runtime from an environment variable, which is sourced from a
different place depending on where the code is running.

| Where the code runs           | How secrets reach it                                                          |
| ----------------------------- | ----------------------------------------------------------------------------- |
| **Local dev** (compose)       | `.env.local` (gitignored). Compose loads it via `--env-file .env.local`        |
| **CI** (GitHub Actions)       | `secrets.*` mapped into `env:` per job. See the checklist below                |
| **Kubernetes prod / staging** | `Secret/shopware-secrets` referenced via `envFrom: secretRef:` in deployments  |
| **Bare-metal** (Deployer)     | `deploy/bare-metal/env/<env>.env` (gitignored, materialised from `secrets.MANAGED_CONTAINER_ENV`) |
| **Managed-container**         | `deploy/managed-container/env/<env>.env` (gitignored, same flow as bare-metal) |

Production secrets should be backed by a real secret manager:
**External Secrets Operator**, **Sealed Secrets**, **SOPS + age**, **Vault**,
or your cloud provider's offering. The placeholder `Secret` manifest in
`k8s/base/secret.yaml` is **only** a shape reference — replace it before
going live.

## Required GitHub Actions secrets

Settings → Secrets and variables → Actions. All scoped to the repository
unless noted.

### Always required

| Secret name                  | Used by                                                | What it is                              |
| ---------------------------- | ------------------------------------------------------ | --------------------------------------- |
| `COMPOSER_AUTH_TOKEN`        | `ci.yml` (every PHP job), image build, deploys         | GitHub PAT with `read:packages` (private composer repos) |
| `SHOPWARE_PACKAGES_TOKEN`    | same                                                   | Bearer token for `packages.shopware.com` |
| `GITHUB_TOKEN`               | image push to GHCR, managed-container GHCR login        | Provided automatically by Actions       |

### Required when `DEPLOYMENT_MODE=kubernetes`

| Secret name                  | Used by                                | What it is                              |
| ---------------------------- | -------------------------------------- | --------------------------------------- |
| `KUBECONFIG`                 | `deploy.yml` → `deploy-kubernetes`     | Base64-encoded kubeconfig for the cluster |

The cluster also needs `shopware-secrets` populated — see
`k8s/base/secret.yaml` for the schema. Drive it from your secret manager,
not from CI.

### Required when `DEPLOYMENT_MODE=bare-metal`

| Secret name                  | Used by                                                | What it is                              |
| ---------------------------- | ------------------------------------------------------ | --------------------------------------- |
| `DEPLOY_HOST`                | `deploy-bare-metal` (shopware/github-actions/project-deployer) | SSH hostname                  |
| `DEPLOY_USER`                | same                                                   | SSH user                                |
| `DEPLOY_SSH_KEY`             | same                                                   | Private SSH key (PEM-encoded)           |

### Required when `DEPLOYMENT_MODE=managed-container`

| Secret name                  | Used by                                                | What it is                              |
| ---------------------------- | ------------------------------------------------------ | --------------------------------------- |
| `DEPLOY_HOST`                | `deploy-managed-container` SSH key install              | SSH hostname for `ssh-keyscan`          |
| `DEPLOY_SSH_KEY`             | same                                                   | Private SSH key (PEM-encoded)           |
| `MANAGED_CONTAINER_ENV`      | `deploy-managed-container` materialise step             | Full body of `deploy/managed-container/env/<env>.env` |

### Optional

| Secret name                  | Used when                                              | What it is                              |
| ---------------------------- | ------------------------------------------------------ | --------------------------------------- |
| `TIDEWAYS_APIKEY`            | `TIDEWAYS_ENABLE=1` in `deployment.config`             | Tideways license key                    |

### Repository variables (not secrets)

Settings → Secrets and variables → Actions → Variables tab.

| Variable name                | Used by                                  | What it is                              |
| ---------------------------- | ---------------------------------------- | --------------------------------------- |
| `SMOKE_TEST_URL`             | `deploy.yml` smoke-test step             | Public URL the post-deploy probe hits   |

### One-time GitHub repo settings (not secrets, not variables)

These can't be configured from the repo files — set them once in the
GitHub UI per repository:

| Setting | Path | Required for |
| --- | --- | --- |
| Allow GitHub Actions to create and approve pull requests | Settings → Actions → General → Workflow permissions | `release-please` workflow — otherwise the release PR can't be opened |
| Require signed commits | Settings → Branches → Branch protection rules → main | Signed-commits policy (in addition to our `verify-signatures.yml` workflow) |
| Require status checks: `CI` | Settings → Branches → Branch protection rules → main | Make `ci-passed` the single required check |

## What goes into `shopware-secrets` (Kubernetes)

These are the keys the running pods expect via `envFrom: secretRef`. See
`k8s/base/secret.yaml` for the placeholder shape.

| Key                              | What it is                                     |
| -------------------------------- | ---------------------------------------------- |
| `APP_SECRET`                     | Symfony app secret (long random)               |
| `DATABASE_URL`                   | Full DSN — wins over per-field below           |
| `MYSQL_ROOT_PASSWORD`            | Root password for the in-cluster MariaDB       |
| `MYSQL_PASSWORD`                 | App-user password                              |
| `REDIS_CACHE_PASSWORD`           | Redis password (cache)                          |
| `REDIS_SESSION_PASSWORD`         | Redis password (sessions)                       |
| `REDIS_DSN`                      | Full DSN form                                   |
| `RABBITMQ_DEFAULT_USER`          | RabbitMQ user                                  |
| `RABBITMQ_DEFAULT_PASS`          | RabbitMQ password                              |
| `INSTALL_ADMIN_PASSWORD`         | Initial admin password (fresh-install only)    |
| `SHOPWARE_STORE_ACCOUNT_EMAIL`   | Shopware Store login (paid extensions)         |
| `SHOPWARE_STORE_ACCOUNT_PASSWORD`| same                                           |
| `SHOPWARE_STORE_LICENSE_DOMAIN`  | Domain bound to the store account              |
| `TIDEWAYS_APIKEY`                | Optional, see `apm/tideways/README.md`         |

## What goes into `shopware-backup-secrets` (Kubernetes)

Separate Secret so the backup-bucket credentials rotate independently of
the app credentials. Consumed by `k8s/base/cronjob-backup.yaml`.

| Key                       | What it is                                                   |
| ------------------------- | ------------------------------------------------------------ |
| `AWS_ACCESS_KEY_ID`       | IAM key for the backup bucket (write-only role recommended)   |
| `AWS_SECRET_ACCESS_KEY`   | matching secret                                              |
| `AWS_DEFAULT_REGION`      | bucket region                                                |
| `BACKUP_BUCKET`           | bucket name (e.g. `shop-db-backups`)                         |
| `BACKUP_ENDPOINT`         | optional — set for R2 / Backblaze / MinIO, empty for AWS S3   |
| `BACKUP_PASSPHRASE`       | symmetric passphrase for `openssl enc -aes-256-cbc`. Generate with `openssl rand -base64 48`. Rotate yearly; archive the old passphrase or you can't decrypt old backups. |

## What goes into `env/<env>.env` (bare-metal / managed-container)

The full body lives in a single GitHub Actions secret
(`secrets.MANAGED_CONTAINER_ENV` for managed-container; bare-metal uses
individual SSH secrets via the Shopware action). Copy
`deploy/<mode>/env/example.env`, fill in, and either:

- store it locally (gitignored) and `make deploy` from your laptop, or
- paste the full body into the GitHub Actions secret for CI deploys.

## Rotation

| Secret                | How often            | How                                                  |
| --------------------- | -------------------- | ---------------------------------------------------- |
| `APP_SECRET`          | yearly + after leak  | Rotate value, deploy, no migration needed             |
| DB passwords          | quarterly + after leak | Rotate DB password, update Secret, restart pods    |
| SSH deploy key        | yearly + on offboarding | New keypair, install pub on host, update Actions secret |
| `COMPOSER_AUTH_TOKEN` | when PAT expires      | New PAT, update Actions secret                       |
| Shopware Store token  | when shown in store   | Read in Shopware Store account UI, update Secret     |

## `fetch-dump` — pulling DB dumps from remote environments

Three guardrails, all on by default:

1. **SSH ControlMaster tunnel**, torn down on EXIT — no DB port stays
   open, no leaked tunnels after the script crashes.
2. **shopware-cli reads `DATABASE_URL` from a tmp-dir `.env`**, not from
   CLI args. The password therefore never appears in `ps -ef`.
3. **`--anonymize` is the default**. PII is rewritten on the way out.
   Opting out requires `ALLOW_UNANONYMIZED=1` + interactive `yes` +
   appears in `.fetch-dump-audit.log` (gitignored, kept for GDPR proof).

### Configuration files

| File | Role | Committed |
| --- | --- | --- |
| `.shopware-project.yml` `dump:` block | What ENDS UP in the dump (anonymize rules, nodata, ignore, where) | yes |
| `.fetch-dump.local.env` | WHERE the dump comes from (named SSH source profiles + DB credentials) | no — gitignored |
| `.fetch-dump.local.env.example` | Template — copy and fill in | yes |
| `.fetch-dump-audit.log` | Append-only audit trail of every dump pull | no — gitignored |

### Defining a profile

```bash
cp .fetch-dump.local.env.example .fetch-dump.local.env
$EDITOR .fetch-dump.local.env

# Example block — variable prefix = <PROFILE>_ (uppercase, hyphens → _)
PROD_SSH_DEST=deploy@shop.example.com
PROD_SSH_PORT=22
PROD_DB_HOST=127.0.0.1     # target inside the SSH host
PROD_DB_PORT=3306
PROD_DB_NAME=shopware
PROD_DB_USER=shopware_readonly      # prefer a read-only DB user
PROD_DB_PASSWORD=...                # paste from your password manager
```

### Running

```bash
make fetch-dump PROFILE=staging     # named profile, fully automated
make fetch-dump                     # interactive wizard, no profile needed
make fetch-dump PROFILE=prod ALLOW_UNANONYMIZED=1   # GDPR-loud override
make fetch-dump PROFILE=staging FORCE_OVERWRITE=1   # skip the overwrite prompt
```

### Audit log format

Tab-separated, append-only. Each row records who pulled what and whether
anonymization was on:

```
2026-05-16T08:42:03Z    ben@laptop    profile=staging    dest=deploy@staging.shop.example.com    db=shopware    anon=ON
```

Forward this to your SIEM if you have one — it's the GDPR receipt for
"who copied production data to a workstation, and was it anonymized".

## Audit

To spot accidentally-committed secrets, run [gitleaks](https://github.com/gitleaks/gitleaks):

```bash
docker run --rm -v "$PWD:/repo" zricethezav/gitleaks:latest detect --source=/repo -v
```

CI should run this on every PR — add a `gitleaks` job to `ci.yml` once your
codebase is steady.
