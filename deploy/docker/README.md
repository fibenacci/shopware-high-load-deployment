# Docker deployment (= local-only)

`DEPLOYMENT_MODE=docker` in [`deployment.config`](../../deployment.config)
means "the only place this shop runs is `docker compose up` on a developer
laptop". There is no remote target; `make deploy` is a no-op alias for
`docker compose up -d --build`.

The actual moving parts live one level up:

| What | Where |
| --- | --- |
| Local dev stack | [`../../compose.yaml`](../../compose.yaml) |
| Local dev entrypoint | [`../../docker/scripts/entrypoint-dev.sh`](../../docker/scripts/entrypoint-dev.sh) |
| Optional monitoring stack | [`../../monitoring/compose.monitoring.yaml`](../../monitoring/compose.monitoring.yaml) |
| Production image build context | [`../../docker/`](../../docker/) |

For deployment paths that *do* push to a remote, see:

- [`../kubernetes/`](../kubernetes/) — K8s manifests
- [`../managed-container/`](../managed-container/) — single Docker host (TimmeHosting etc.)
- [`../bare-metal/`](../bare-metal/) — SSH + Deployer
