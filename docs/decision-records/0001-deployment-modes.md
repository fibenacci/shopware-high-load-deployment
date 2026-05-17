# ADR-0001: Four deployment modes dispatched by a single Makefile target

- **Status**: Accepted
- **Date**: 2026-05-15
- **Decision-makers**: template-author
- **Consulted**: —
- **Informed**: future template adopters

## Context

The template targets Shopware shops of very different sizes and host
profiles. A solo dev with a single VPS has wildly different operational
constraints from a team running on managed Kubernetes. We can either:

1. Ship one opinionated path and tell everyone else to fork it.
2. Ship multiple paths and pick at runtime.

Forking-as-the-answer historically produces a constellation of slightly-
different forks that all suffer the same bugs and never share fixes.

## Decision drivers

1. **Same operator skill profile across modes** — `make deploy ENV=foo`
   should work everywhere.
2. **Single source of truth** for versions / image tags / install
   defaults across modes.
3. **Same post-upload pipeline** regardless of how the code got there —
   so plugin install / migrations / theme compile aren't four different
   implementations.
4. **No mode-specific knowledge bleeding into the others** — adding a
   fifth mode shouldn't touch the existing four.

## Considered options

- **Option A — One opinionated mode (Kubernetes only)**: refuse to ship
  anything else.
- **Option B — Four modes behind one dispatcher** (`DEPLOYMENT_MODE` in
  `deployment.config`, `make deploy` switches).
- **Option C — One repo per mode**: separate template per deploy style.

## Decision

Picked: **Option B**, four modes (`docker`, `kubernetes`,
`managed-container`, `bare-metal`) dispatched by `DEPLOYMENT_MODE` in
[`deployment.config`](../../deployment.config).

All four converge on Shopware's official
`vendor/bin/shopware-deployment-helper run` for the actual deploy work.
Mode-specific code only handles "how the code physically arrives on the
host" — copy via rsync (bare-metal), pull via `docker compose`
(managed-container), `kubectl apply` (kubernetes), or `compose up`
(docker).

We are explicitly NOT shipping:
- Blue/green deployments (would require Argo Rollouts or Flagger — out
  of template scope; users can layer on top)
- Multi-region active/active (project-specific architecture decision)

## Consequences

### Positive
- Same `make deploy` flow for every adopter; same training material
  works for everyone.
- Adding a fifth mode (e.g. AWS ECS) is additive — new `deploy/<mode>/`
  directory, new dispatcher case, zero changes to existing modes.
- The Shopware deployment-helper is the single point Shopware's
  conventions land — when Shopware adds a step (cache warmup, asset
  install ordering), we get it for free across all four modes.

### Negative
- The `deployment.config` is now more complex than a typical
  `.env.example`. Onboarding cost: ~30 minutes of reading.
- Four codepaths to keep working = four codepaths to keep tested. CI
  doesn't actually test the bare-metal path end-to-end (would need a
  reachable SSH target); this is a known gap.
- Some operational nuances differ between modes — e.g. `make rollback`
  is `kubectl rollout undo` in K8s but symlink-flip in bare-metal. The
  abstraction leaks at the edges.

### Neutral
- The template ships more files than a single-mode template would.
  Adopters who only need one mode can delete the other three
  directories without breaking anything.

## Validation

- **Success signal**: a team picks up the template and ships their
  first deploy in <2 hours of reading.
- **Reconsider when**: more than 50% of adopters end up running a fifth
  mode we didn't anticipate, OR the dispatcher logic in the Makefile
  grows past ~50 lines.

## Links

- Implementation: [`Makefile`](../../Makefile) (`deploy:` target)
- Config: [`deployment.config`](../../deployment.config)
- Per-mode docs: [`deploy/`](../../deploy/) directories
- Shopware reference: [Deployment Helper](https://developer.shopware.com/docs/guides/hosting/installation-updates/deployments/deployment-helper.html)
