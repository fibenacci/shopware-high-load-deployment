# Security model

Defence in depth across five concerns. Each section says what's enforced
where, and points at the file that actually implements it.

## 1. Secret management

Single rule: **no secret is committed in plaintext**.

See [`secrets.md`](./secrets.md) for the full inventory — which GitHub
Actions secrets per deployment mode, the K8s Secret schema, rotation
cadence. Highlights:

- **`.env.local`** — local dev only, gitignored
- **`secrets.*`** — GitHub Actions, mapped into `env:` per job
- **`Secret/shopware-secrets`** — K8s, referenced via `envFrom: secretRef`;
  back it with External Secrets / Sealed Secrets / SOPS / Vault before
  going to production
- **`deploy/<mode>/env/<env>.env`** — gitignored for managed-container and
  bare-metal; whole file ships as one GitHub Actions secret

### Audit gates

| Gate | Where | Blocks build? |
| --- | --- | --- |
| **gitleaks** — committed-secret scanner | `.github/workflows/ci.yml` `secrets-scan` job | yes |
| **`fetch-dump-audit.log`** — GDPR receipt for prod dumps | `docker/scripts/fetch-dump.sh` (local) | n/a |

The gitleaks job is part of the fast static-check block so red feedback
arrives in seconds, not after the 30-minute test job.

---

## 2. Image scanning

[`aquasecurity/trivy-action`](https://github.com/aquasecurity/trivy-action)
scans the built production image on every CI run.

| Setting | Value | Why |
| --- | --- | --- |
| `severity` | `HIGH,CRITICAL` | Don't block on noise; LOW/MEDIUM get reported but don't fail |
| `ignore-unfixed: true` | enabled | Skip CVEs with no upstream fix — actionable findings only |
| `exit-code: 1` | enabled | Failing CVE blocks the build |
| `trivyignores: .trivyignore` | repo root | Project-specific allowlist with mandatory `# why?` comment |

A **CycloneDX SBOM** is uploaded as an artefact on every run — useful for
downstream supply-chain audit (vendor questionnaires, regulatory review).

`.trivyignore` entries must explain *why* the CVE is suppressed. Empty
comments get cleared during the quarterly security review.

---

## 3. Rate limiting — two layers

The Ingress and the Shopware kernel rate-limit different things. **Run both.**

### Layer A: Ingress-NGINX (cheap, per-IP)

Catches obvious bursts before they hit PHP. Annotation-driven, per-Ingress
object.

| Ingress object | Limits (base / prod) | Paths |
| --- | --- | --- |
| `shopware-web` | 20 rps / 50 rps baseline | Everything else (most traffic, behind Varnish) |
| `shopware-web-throttled` | 5 rps / 10 rps tighter | `/account/login`, `/account/register`, `/account/recover`, `/store-api`, `/api`, `/admin`, `/search`, `/widgets/search` |

Implementation: [`k8s/base/ingress.yaml`](../k8s/base/ingress.yaml).

The throttled paths **bypass Varnish on purpose** — login/checkout/admin
should never hit a shared cache.

### Layer B: Shopware application rate limiter (per-account, per-route)

> 📖 [Rate limiter docs](https://developer.shopware.com/docs/guides/hosting/infrastructure/rate-limiter.html)

Shopware ships built-in rate limiting for security-sensitive endpoints
(Shopware 6.4.6.0+):

| Limiter | Default coverage |
| --- | --- |
| `login` | Storefront + Store API customer auth |
| `guest_login` | Post-order guest access |
| `oauth` | API + Administration login |
| `reset_password` | Customer password recovery |
| `user_recovery` | Admin user password reset |
| `contact_form` | Public contact-form submissions |

Configured in `config/packages/shopware.yaml`:

```yaml
shopware:
  api:
    rate_limiter:
      login:
        enabled: true
        policy: 'time_backoff'
        reset: '24 hours'
        limits:
          - { limit: 3, interval: '10 seconds' }
          - { limit: 5, interval: '60 seconds' }
```

`time_backoff` enforces progressive delays — first attempt costs 10 s, then
30 s, etc. Adopt the defaults; tighten only after you see real abuse.

### Why both?

| Threat | Caught by Ingress | Caught by Shopware |
| --- | --- | --- |
| Distributed scraping bot (100 IPs, 5 rps each) | partially (each IP under limit) | yes (per-account, per-route) |
| Single-IP credential stuffing | yes | yes |
| Application-layer DDoS targeting `/store-api` | yes | partially |
| Slow brute-force at 1 attempt/min | no | yes |

Ingress is the cheap front; Shopware is the precise back.

---

## 4. Network policies

[`k8s/base/networkpolicy.yaml`](../k8s/base/networkpolicy.yaml) — deny-by-default
namespace policy plus three explicit allowances:

| Policy | Allows |
| --- | --- |
| `default-deny` | Everything blocked unless another policy allows it |
| `allow-ingress-to-web` | `ingress-nginx` + `observability` namespaces → web pods |
| `allow-internal-egress` | DNS, in-namespace pods, observability collectors, outbound HTTPS (composer / payment / mail) |

Roll out in **audit mode** first (Calico / Cilium can log without enforcing)
for a week to find dependencies you'd otherwise break.

---

## 5. Pod & container hardening

Defaults in [`k8s/base/deployment-web.yaml`](../k8s/base/deployment-web.yaml):

| Setting | Value |
| --- | --- |
| `runAsNonRoot` | `true` |
| `runAsUser` / `runAsGroup` | `33` (www-data) |
| `allowPrivilegeEscalation` | `false` |
| `capabilities.drop` | `["ALL"]` |
| `readOnlyRootFilesystem` | `false` (composer cache / runtime writes — opt-in once tested) |
| Pod-Security namespace label | `enforce: baseline` + `warn: restricted` |

Tighten to `pod-security.kubernetes.io/enforce: restricted` once you've
verified every plugin survives — common breakage is plugins that write
outside `var/`.

---

## 6. Supply-chain integrity

- **Signed commits** enforced at three layers (local hook + CI verify
  workflow + GitHub branch protection). See [`signed-commits.md`](./signed-commits.md)
  for the developer setup. Without signed commits "did Alice write this"
  is a guess; with them, it's provable.
- **`composer.lock`** committed and the `composer audit` step in CI checks
  for known PHP advisories.
- **`package-lock.json`** committed under `tests/e2e/` and `npm audit`
  blocks `--audit-level=high`.
- **GHCR images** signed via the `cosign` action — optional but recommended;
  enable by uncommenting the `cosign sign` step in `.github/workflows/ci.yml`.

---

## 7. GDPR data handling

The fetch-dump pipeline (see [`docker/scripts/fetch-dump.sh`](../docker/scripts/fetch-dump.sh))
defaults to `shopware-cli project dump --anonymize`. Raw PII pulls require
`ALLOW_UNANONYMIZED=1` *and* an interactive `yes` confirmation *and*
landing in `.fetch-dump-audit.log` (gitignored, append-only, the GDPR
receipt for "who copied prod data when").

Full details in [`secrets.md`](./secrets.md#fetch-dump--pulling-db-dumps-from-remote-environments).

---

## Threat model (what we are NOT defending against)

- **Compromised CI runners** — GitHub Actions ephemeral runners are the
  trust boundary. If they're compromised, your image registry credential
  is too. Mitigation: use OIDC + short-lived tokens instead of long-lived
  PATs (next iteration).
- **Compromised laptop** — `.fetch-dump.local.env` contains DB creds. Treat
  the laptop with the same care as a prod host. Disk encryption is non-
  negotiable.
- **Stolen K8s kubeconfig** — anyone with `secrets.KUBECONFIG` can deploy
  arbitrary images. Mitigation: rotate quarterly, scope RBAC to the
  shopware-* namespaces only.

---

## Review cadence

| What | When |
| --- | --- |
| `.trivyignore` entries | quarterly |
| `secrets.md` rotation table | annually + on offboarding |
| NetworkPolicies | after every plugin addition that opens new egress |
| Rate-limit thresholds | after every load test (do they need raising?) |
| Pod-Security level | quarterly — push from baseline → restricted |
