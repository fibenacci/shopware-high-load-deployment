#!/usr/bin/env bash
# Spin up a local single-node k3s cluster via k3d. Idempotent.
#
# Why k3d (not vanilla k3s on the host):
#   - macOS support out of the box (k3s on Mac requires a Linux VM anyway)
#   - cluster lives inside docker → `k3d cluster delete` is one command
#   - the k3d load-balancer maps ports onto the host, so the Ingress works
#     against localhost:80 / :443

set -euo pipefail

CLUSTER_NAME="${CLUSTER_NAME:-shopware}"
SERVERS="${SERVERS:-1}"
AGENTS="${AGENTS:-2}"

OS="$(uname -s)"

if ! command -v k3d >/dev/null 2>&1; then
    echo "▶ Installing k3d"
    if [ "${OS}" = "Darwin" ]; then
        brew install k3d
    else
        curl -fsSL https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash
    fi
fi

if ! command -v kubectl >/dev/null 2>&1; then
    echo "::error::kubectl missing — install kubectl first." >&2
    exit 1
fi

if k3d cluster list | awk 'NR>1 {print $1}' | grep -qx "${CLUSTER_NAME}"; then
    echo "✓ Cluster '${CLUSTER_NAME}' already exists — starting if stopped"
    k3d cluster start "${CLUSTER_NAME}" || true
else
    echo "▶ Creating cluster '${CLUSTER_NAME}'"
    k3d cluster create "${CLUSTER_NAME}" \
        --servers "${SERVERS}" \
        --agents  "${AGENTS}" \
        --port "80:80@loadbalancer" \
        --port "443:443@loadbalancer" \
        --k3s-arg "--disable=traefik@server:0" \
        --wait
fi

kubectl config use-context "k3d-${CLUSTER_NAME}"

echo "▶ Installing ingress-nginx"
kubectl create namespace ingress-nginx --dry-run=client -o yaml | kubectl apply -f -
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx >/dev/null 2>&1 || true
helm repo update >/dev/null
helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
    --namespace ingress-nginx \
    --set controller.service.type=LoadBalancer \
    --set controller.publishService.enabled=true \
    --set controller.metrics.enabled=true \
    --set controller.metrics.serviceMonitor.enabled=false \
    --wait

echo "▶ Installing cert-manager (used by overlays, but no real ACME in k3s)"
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/latest/download/cert-manager.yaml
kubectl -n cert-manager wait --for=condition=Available --timeout=5m \
    deploy/cert-manager deploy/cert-manager-webhook deploy/cert-manager-cainjector

echo
echo "✅ k3s cluster '${CLUSTER_NAME}' ready"
echo "   Context: $(kubectl config current-context)"
echo "   Apply your shop:  kubectl apply -k k8s/overlays/staging"
echo "   Run a stresstest: make stresstest"
