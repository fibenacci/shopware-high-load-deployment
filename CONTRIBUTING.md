# Contributing

Thanks for considering a contribution. This file is the **shortest path
from clone to merged PR**. Deeper context lives in [`docs/`](./docs/).

## Quick setup

```bash
# 1. Clone + bootstrap (idempotent — safe to re-run any time)
git clone <repo>
cd shopware-shop
make setup                     # doctor + env files + composer.json + git hooks

# 2. Fill in the two tokens the setup printed as TODOs
$EDITOR auth.json

# 3. Boot the stack
make up
open http://shop.docker
```

Full one-screen walkthrough: [`docs/onboarding.md`](./docs/onboarding.md).

## Conventions you MUST follow

CI enforces all of these. Skipping them produces red builds.

1. **Sign your commits** — `commit.gpgsign=true`. SSH or GPG, both
   work. Full setup: [`docs/signed-commits.md`](./docs/signed-commits.md).
2. **Conventional Commits** in subjects — `feat:`, `fix:`, `perf:`,
   `security:`, `deps:`, `docs:`, `refactor:`, `test:`, `build:`, `ci:`,
   `chore:`. The `commit-msg` hook warns; release-please uses these to
   bucket the CHANGELOG.
3. **No secrets in commits** — gitleaks blocks them. Real secrets go
   into `.env.local` (local), GitHub Actions secrets (CI), K8s Secrets
   (cluster). Inventory: [`docs/secrets.md`](./docs/secrets.md).
4. **`make audit-shopware`** must pass before opening a PR. It runs the
   Shopware-flavoured security + perf checks.

## Conventions we'd LIKE you to follow

Default expectations. Push back in the PR if you have a good reason.

- **Use the official Shopware tooling** — `shopware-deployment-helper`,
  `shopware/docker-base`, `shopware-cli`. We don't ship hand-rolled
  alternatives.
- **Write a test for every fix** — not because of coverage targets, but
  because regressions hurt. The `shopware-test-writer` agent in Claude
  Code handles the fixture pattern correctly; let it.
- **One concern per PR** — refactor + feature + test in the same PR
  costs reviewers 3× more time and almost always merges later than
  three separate PRs would.
- **Update the docs alongside the code** — if behaviour changes, the
  docs that describe it change. Reviewers will ask.
- **Add an ADR** when the choice is non-obvious and expensive to
  reverse. Use `/adr` in Claude Code or `docs/decision-records/0000-template.md`.

## How to actually open a PR

```bash
# 1. Make changes on a branch.
git switch -c feat/checkout-staff-discount

# 2. Iterate. Pre-commit runs gitleaks + php-cs-fixer + syntax check.
git commit -m "feat(checkout): apply staff discount automatically"

# 3. Run the local audit before pushing.
make audit-shopware            # security + perf review of the diff
make test-unit                 # fast feedback
make test-integration          # boots kernel; slower
make phpstan                   # static analysis

# 4. Push and open the PR.
git push -u origin feat/checkout-staff-discount
gh pr create                   # uses .github/PULL_REQUEST_TEMPLATE.md
```

The PR template asks for **What / Why / How / Test plan / Deployment
notes / Rollback plan**. None of these are decorative — reviewers use
all six.

## What CI runs on your PR

Listed in dependency order. Earlier failures cancel later stages.

| Stage | What it checks |
| --- | --- |
| `config` | Reads `deployment.config`, fans versions to every job |
| `secrets-scan` | `gitleaks` against the PR diff |
| `quality` | PHPStan + PHP-CS-Fixer dry-run |
| `lint` | TypeScript / Vue lint on touched files |
| `audit` | `composer audit` + `npm audit` |
| `shopware-validate` | `shopware-cli extension validate` per plugin |
| `tests` | PHPUnit (unit + integration) + Playwright |
| `image` | Multi-stage docker build + Trivy scan + SBOM |
| `verify-signatures` | Every commit in the PR must be signed |
| `publish-results` | Renders test results into the PR body |
| `ci-passed` | Aggregate gate — the single required check |
| `performance` | k6 regression profile (runs on perf-relevant paths) |

Make `ci-passed` your required branch-protection check; the others can
be added/removed without touching protection rules.

## Where to find what you need

- **Architecture**: [`docs/architecture.md`](./docs/architecture.md)
- **Deploy paths**: [`docs/deployment.md`](./docs/deployment.md)
- **Secrets / signed commits**: [`docs/secrets.md`](./docs/secrets.md),
  [`docs/signed-commits.md`](./docs/signed-commits.md)
- **Testing**: [`tests/README.md`](./tests/README.md)
- **Claude Code agents + commands**: [`CLAUDE.md`](./CLAUDE.md) (auto-loaded),
  `.claude/agents/`, `.claude/commands/`
- **Backlog of unbuilt ideas**: [`docs/ideas.md`](./docs/ideas.md)
- **Full doc index**: [`docs/README.md`](./docs/README.md)

## Writing docs

`docs/` is **flat** (no subdirectories except `decision-records/` and
`stories/`) — the [`docs/README.md`](./docs/README.md) index does the
grouping. Why we don't nest: cross-reference churn beats whatever
mental-grouping benefit the subdirs would add.

When you add a new doc:

1. kebab-case filename, topic-first (`caching.md`, not `http-caching-guide.md`)
2. Use **relative `.md` links** for cross-references — the wiki-sync
   workflow rewrites them at publish time
3. **Add a row to `docs/README.md`** — the index. Orphan docs rot
4. At least one inbound link from a related doc

The docs are auto-published to the GitHub Wiki on every push to `main`
via [`.github/workflows/wiki-sync.yml`](./.github/workflows/wiki-sync.yml).
**Edit `docs/`, never the wiki directly** — the next push overwrites it.

Full conventions: [`docs/conventions.md`](./docs/conventions.md).

## What needs human review (not just CI)

CI catches lint, types, tests, secrets, vulnerabilities. It can't catch:

- API contract changes for plugin consumers
- Database migrations with destructive intent
- Performance regressions outside the load-test profile
- Wording in customer-facing strings / emails / receipts

If your PR touches any of these, **flag it in the PR description** so
the reviewer knows to check.

## Reporting issues

- **Bugs**: open a [bug report](https://github.com/EXAMPLE/shopware-shop/issues/new?template=bug_report.yml)
- **Feature ideas (template-wide)**: [feature request](https://github.com/EXAMPLE/shopware-shop/issues/new?template=feature_request.yml)
- **Story-level work** (one shop's feature): use `/new-story` in Claude Code or
  the user-story template at [`docs/user-story-template.md`](./docs/user-story-template.md)
- **Security vulnerabilities**: [Security Advisories](https://github.com/EXAMPLE/shopware-shop/security/advisories/new),
  never via public issue. Details in [`SECURITY.md`](./SECURITY.md).
