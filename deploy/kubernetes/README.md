# Kubernetes deployment

`DEPLOYMENT_MODE=kubernetes` in [`deployment.config`](../../deployment.config)
makes `make deploy ENV=staging` run `kubectl apply -k k8s/overlays/staging`.

The manifests themselves live at the repo root under `k8s/`, not here —
keeping them at the top level matches the Kustomize convention and means
tools like `kubectl diff -k k8s/overlays/...` and `kustomize build k8s/...`
do the obvious thing.

| What | Where |
| --- | --- |
| Kustomize base (Deployments, StatefulSets, Ingress, NetworkPolicies, …) | [`../../k8s/base/`](../../k8s/base/) |
| Staging overlay | [`../../k8s/overlays/staging/`](../../k8s/overlays/staging/) |
| Production overlay | [`../../k8s/overlays/production/`](../../k8s/overlays/production/) |
| Deploy pipeline (GitHub Actions) | [`../../.github/workflows/deploy.yml`](../../.github/workflows/deploy.yml) `deploy-kubernetes` job |
| Local k3s for rehearsals | [`../../k3s/`](../../k3s/) |

For deeper details see [`../../docs/deployment.md`](../../docs/deployment.md) —
this file is intentionally a one-screen pointer.
