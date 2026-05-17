# Kubernetes monitoring — Helm values

The cluster-side LGTM stack is installed via the standard upstream charts.
This directory holds the values files we apply on top.

```bash
# 1. Namespace
kubectl create namespace observability

# 2. Repositories
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add grafana              https://grafana.github.io/helm-charts
helm repo update

# 3. Install
helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
    --namespace observability \
    --values kube-prometheus-stack-values.yaml

helm upgrade --install loki grafana/loki \
    --namespace observability \
    --values loki-values.yaml

helm upgrade --install promtail grafana/promtail \
    --namespace observability \
    --values promtail-values.yaml

helm upgrade --install tempo grafana/tempo \
    --namespace observability \
    --values tempo-values.yaml

helm upgrade --install pyroscope grafana/pyroscope \
    --namespace observability \
    --values pyroscope-values.yaml

# External-perspective probes (TLS expiry, CDN failures, DNS).
helm upgrade --install blackbox-exporter prometheus-community/prometheus-blackbox-exporter \
    --namespace observability \
    --values blackbox-exporter-values.yaml
```

Once deployed, the `ServiceMonitor` in `k8s/base/servicemonitor.yaml` is
picked up automatically (selector matches `release: kube-prometheus-stack`).
