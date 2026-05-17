# Local k3s + stresstest

Small, single-node k3s cluster on your laptop. Used to rehearse the
Kubernetes deploy and run **k6** stresstests against the cluster-internal
storefront URL — without burning cloud quota.

## Prerequisites

- macOS / Linux host with at least 8 GB free RAM
- Docker running (k3d wraps k3s in a container)
- `kubectl`, `kustomize`, `helm`, `k3d` on PATH

`./install-k3s.sh` installs `k3d` (homebrew on macOS, install script on
Linux), creates a cluster called `shopware`, and configures kubectl
context.

## Quickstart

```bash
./k3s/install-k3s.sh                  # ~2 min on a warm machine
kubectl apply -k k8s/overlays/staging # deploy the shop
kubectl -n shopware-staging rollout status deploy/shopware-web --timeout=10m
make stresstest                       # k6 Job, prints summary on completion
```

## Useful commands

```bash
k3d cluster list
k3d cluster stop  shopware
k3d cluster start shopware
k3d cluster delete shopware
```

## Stresstest profiles

`stresstest/k6/loadtest.js` defines four scenarios that you can mix and
match through the `K6_PROFILE` env var on the Job:

| Profile        | Shape                            | Use for                                  |
| -------------- | -------------------------------- | ---------------------------------------- |
| `smoke`        | 1 VU, 30 s                       | sanity check after rollout                |
| `baseline`     | 50 VU, 5 min ramp + 10 min hold  | day-to-day baseline numbers               |
| `peak`         | ramp to 500 VU over 15 min       | sales-event readiness                     |
| `endurance`    | 100 VU, 60 min                   | catch leaks, GC, slow query growth        |

Pass via:

```bash
kubectl -n shopware-staging set env job/shopware-stresstest K6_PROFILE=peak
```
