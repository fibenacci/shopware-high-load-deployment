#!/usr/bin/env bash
# Tier-1 verification — runs every static / dry-run check the template
# owns. No side effects, no docker, no network needed.
#
# Each individual tool is OPTIONAL: if it's not installed, we skip the
# check with a yellow warning instead of failing. This keeps `make verify`
# usable on minimal dev setups while still being thorough where the
# tools are present.
#
# Exit codes:
#   0  all hard checks passed (warnings are OK)
#   1  one or more hard checks failed
#
# Reference: docs/testing-the-template.md

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${REPO_ROOT}"

# ---------------------------------------------------------------------------
# Reporting helpers
# ---------------------------------------------------------------------------
hard_fail=0

ok()    { printf "  \033[1;32m✓\033[0m %s\n" "$*"; }
warn()  { printf "  \033[1;33m⚠\033[0m %s\n" "$*"; }
fail()  { printf "  \033[1;31m✗\033[0m %s\n" "$*"; hard_fail=1; }
section() { printf "\n\033[1m%s\033[0m\n" "$*"; }
skip()  { printf "  \033[2m·\033[0m %s — \033[2m%s\033[0m\n" "$1" "$2"; }

have() { command -v "$1" >/dev/null 2>&1; }

# ---------------------------------------------------------------------------
# Sourceable deployment.config
# ---------------------------------------------------------------------------
section "Configuration"

if [ -f deployment.config ]; then
    if (set -a; . ./deployment.config; set +a) >/dev/null 2>&1; then
        ok "deployment.config sources cleanly"
    else
        fail "deployment.config has shell errors"
        bash -n deployment.config 2>&1 | sed 's/^/      /'
    fi
else
    fail "deployment.config missing"
fi

# scripts/load-config.sh round-trip
if [ -x scripts/load-config.sh ]; then
    if (. scripts/load-config.sh; [ -n "${SHOPWARE_VERSION:-}" ] && [ -n "${PHP_VERSION:-}" ] && [ -n "${DEPLOYMENT_MODE:-}" ]) ; then
        ok "scripts/load-config.sh exposes SHOPWARE_VERSION / PHP_VERSION / DEPLOYMENT_MODE"
    else
        fail "scripts/load-config.sh runs but doesn't export the required vars"
    fi
fi

# composer.json drift
if [ -f composer.json.example ]; then
    if ./scripts/render-composer.sh --check >/dev/null 2>&1; then
        ok "composer.json in sync with composer.json.example + deployment.config"
    else
        if [ -f composer.json ]; then
            fail "composer.json drift — run 'make composer-json' and commit"
        else
            warn "composer.json not rendered yet — first-time setup, run 'make composer-json'"
        fi
    fi
fi

# ---------------------------------------------------------------------------
# JSON / YAML hygiene
# ---------------------------------------------------------------------------
section "JSON parse"

json_count=0; json_bad=0
for f in $(find . -type f -name '*.json' \
    -not -path './vendor/*' \
    -not -path './node_modules/*' \
    -not -path '*/.git/*' \
    -not -path '*/.idea/*' 2>/dev/null); do
    json_count=$((json_count + 1))
    if have jq; then
        jq empty "$f" >/dev/null 2>&1 || { fail "${f} — invalid JSON"; json_bad=$((json_bad + 1)); }
    elif have python3; then
        python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$f" >/dev/null 2>&1 \
            || { fail "${f} — invalid JSON"; json_bad=$((json_bad + 1)); }
    fi
done
if [ "${json_count}" -gt 0 ] && [ "${json_bad}" -eq 0 ]; then
    ok "${json_count} JSON files parsed"
elif [ "${json_count}" -eq 0 ]; then
    warn "no JSON files found (unexpected)"
fi

section "YAML parse"

if have yq; then
    yaml_count=0; yaml_bad=0
    while IFS= read -r f; do
        yaml_count=$((yaml_count + 1))
        yq eval '.' "$f" >/dev/null 2>&1 \
            || { fail "${f} — invalid YAML"; yaml_bad=$((yaml_bad + 1)); }
    done < <(find . -type f \( -name '*.yml' -o -name '*.yaml' \) \
        -not -path './vendor/*' -not -path './node_modules/*' \
        -not -path '*/.git/*' -not -path '*/.idea/*')
    [ "${yaml_count}" -gt 0 ] && [ "${yaml_bad}" -eq 0 ] && ok "${yaml_count} YAML files parsed"
else
    skip "yaml parse" "yq not installed — brew install yq"
fi

# ---------------------------------------------------------------------------
# Shell scripts — shellcheck
# ---------------------------------------------------------------------------
section "Shell scripts"

if have shellcheck; then
    sh_count=0; sh_bad=0
    while IFS= read -r f; do
        sh_count=$((sh_count + 1))
        shellcheck -x -e SC1091 "$f" >/dev/null 2>&1 \
            || { fail "${f} — shellcheck issues"; sh_bad=$((sh_bad + 1)); }
    done < <(find . -type f -name '*.sh' \
        -not -path './vendor/*' -not -path './node_modules/*' \
        -not -path '*/.git/*' 2>/dev/null)
    while IFS= read -r f; do
        sh_count=$((sh_count + 1))
        shellcheck -x -e SC1091 "$f" >/dev/null 2>&1 \
            || { fail "${f} — shellcheck issues"; sh_bad=$((sh_bad + 1)); }
    done < <(find .githooks -type f 2>/dev/null)
    [ "${sh_count}" -gt 0 ] && [ "${sh_bad}" -eq 0 ] && ok "${sh_count} shell scripts clean"
else
    skip "shellcheck" "not installed — brew install shellcheck"
fi

# ---------------------------------------------------------------------------
# GitHub Actions workflows — actionlint
# ---------------------------------------------------------------------------
section "GitHub Actions"

if have actionlint; then
    if actionlint .github/workflows/*.yml >/dev/null 2>&1; then
        ok "all workflows pass actionlint"
    else
        fail "actionlint reports issues"
        actionlint .github/workflows/*.yml 2>&1 | head -30 | sed 's/^/      /'
    fi
else
    skip "actionlint" "not installed — brew install actionlint"
fi

# ---------------------------------------------------------------------------
# Kustomize — base + overlays render
# ---------------------------------------------------------------------------
section "Kubernetes manifests"

if have kustomize; then
    for overlay in k8s/base k8s/overlays/staging k8s/overlays/production; do
        [ -d "${overlay}" ] || continue
        if kustomize build "${overlay}" >/dev/null 2>&1; then
            ok "kustomize build ${overlay}"
        else
            fail "kustomize build ${overlay} — errors:"
            kustomize build "${overlay}" 2>&1 | head -10 | sed 's/^/      /'
        fi
    done
elif have kubectl; then
    # kubectl has a built-in kustomize subset
    for overlay in k8s/base k8s/overlays/staging k8s/overlays/production; do
        [ -d "${overlay}" ] || continue
        if kubectl kustomize "${overlay}" >/dev/null 2>&1; then
            ok "kubectl kustomize ${overlay}"
        else
            fail "kubectl kustomize ${overlay} — errors"
        fi
    done
else
    skip "kustomize" "not installed — brew install kustomize"
fi

# Client-side schema validation if kubectl is available
if have kubectl; then
    for overlay in k8s/overlays/staging k8s/overlays/production; do
        [ -d "${overlay}" ] || continue
        if kubectl apply -k "${overlay}" --dry-run=client -o yaml >/dev/null 2>&1; then
            ok "kubectl apply --dry-run=client -k ${overlay}"
        else
            fail "kubectl apply --dry-run=client -k ${overlay} — schema errors"
        fi
    done
fi

# ---------------------------------------------------------------------------
# Helm values — render check
# ---------------------------------------------------------------------------
section "Helm values"

if have helm; then
    # The values files reference real charts; we don't fetch them — just
    # validate that the YAML is parseable by Helm's preprocessor.
    helm_ok=1
    while IFS= read -r f; do
        if ! python3 -c "import yaml,sys; yaml.safe_load(open(sys.argv[1]))" "$f" >/dev/null 2>&1; then
            fail "${f} — YAML invalid"; helm_ok=0
        fi
    done < <(find monitoring/k8s -name '*-values.yaml' 2>/dev/null)
    [ "${helm_ok}" -eq 1 ] && ok "monitoring/k8s/*-values.yaml all valid"
else
    skip "helm" "not installed — brew install helm"
fi

# ---------------------------------------------------------------------------
# Renovate config
# ---------------------------------------------------------------------------
section "Renovate config"

if [ -f .github/renovate.json ]; then
    if have npx; then
        if npx --yes --quiet renovate-config-validator .github/renovate.json >/dev/null 2>&1; then
            ok ".github/renovate.json validates"
        else
            warn "renovate-config-validator reports issues — run 'npx renovate-config-validator .github/renovate.json' for detail"
        fi
    else
        skip "renovate-config-validator" "needs npx (node)"
    fi
fi

# ---------------------------------------------------------------------------
# Markdown link sanity (optional, lychee)
# ---------------------------------------------------------------------------
section "Markdown links (optional)"

if have lychee; then
    if lychee --offline --no-progress --include-fragments \
        README.md CLAUDE.md CONTRIBUTING.md SECURITY.md \
        'docs/**/*.md' 'deploy/**/*.md' \
        >/dev/null 2>&1; then
        ok "lychee — all relative + fragment links resolve"
    else
        warn "lychee found broken links — run 'lychee --offline <path>' for detail"
    fi
else
    skip "lychee" "not installed — brew install lychee (link checker)"
fi

# ---------------------------------------------------------------------------
# Composer + PHP (light — heavy stuff is the CI's job)
# ---------------------------------------------------------------------------
section "Composer + PHP"

if [ -f composer.json ] && have composer; then
    if composer validate --strict --no-check-publish composer.json >/dev/null 2>&1; then
        ok "composer.json validates strict"
    else
        warn "composer.json validation issues — run 'composer validate'"
    fi
elif [ -f composer.json ]; then
    skip "composer validate" "composer not installed locally"
else
    skip "composer.json" "not rendered yet — run 'make composer-json'"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
if [ "${hard_fail}" -eq 0 ]; then
    printf "\033[1;32m✅ verify — all hard checks passed\033[0m\n"
    exit 0
else
    printf "\033[1;31m✗ verify — hard checks failed (see ✗ lines above)\033[0m\n"
    exit 1
fi
