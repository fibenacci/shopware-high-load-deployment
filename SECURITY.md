# Security Policy

## Reporting a vulnerability

**Do not open a public GitHub issue for security reports.**

Send the details privately to **`security@<your-domain>`** (TODO: replace
before adoption). Encrypted mail welcome — the team key is published at
`https://<your-domain>/.well-known/security.txt`.

Please include:

- Affected component (deployment-helper config, Dockerfile, K8s manifest,
  Shopware plugin path, etc.)
- Reproduction steps or a proof-of-concept
- Impact you observed
- Suggested remediation, if you have one
- Disclosure timeline you'd like — we default to 90 days but flex on
  user-impact severity

You'll get a response within **3 business days** acknowledging receipt
and within **10 business days** with a triage decision (accept / decline
/ needs-info). We'll keep you in the loop until the issue is closed.

## Scope

In scope:

- This template's CI workflows, Makefile, Dockerfiles, K8s manifests
- The Shopware shop code that builds on this template
- Deployment + secret-management flows
- The Claude-Code agents + commands shipped in `.claude/`

Out of scope (report directly upstream):

- Vulnerabilities in **Shopware Core** itself —
  [security@shopware.com](mailto:security@shopware.com)
- Vulnerabilities in third-party plugins — vendor's security contact
- Generic Symfony / PHP issues unrelated to our usage

## What we've already wired up

Security expectations + ongoing controls are documented in
[`docs/security.md`](./docs/security.md). Highlights:

- **Signed commits** enforced at three layers (local + CI + branch
  protection). See [`docs/signed-commits.md`](./docs/signed-commits.md).
- **Image scanning** with Trivy on every CI run; HIGH/CRITICAL blocks.
- **Secret scanning** with gitleaks; blocking CI gate.
- **Two-layer rate limiting** (Ingress + Shopware application).
- **Network policies** denying by default, explicit allowances.
- **Encrypted DB backups** with weekly restore drill.
- **Secret-management** patterns documented in [`docs/secrets.md`](./docs/secrets.md).

## Coordinated disclosure

If a CVE is assigned, we'll coordinate the disclosure date with you.
Default: public advisory in a GitHub Security Advisory + CHANGELOG.md
entry on the same day the patched version ships.

If you'd like attribution in the advisory, say so in your report. If
you'd prefer anonymity, also say so — we'll respect either choice.
