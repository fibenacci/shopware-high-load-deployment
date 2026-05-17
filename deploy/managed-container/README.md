# Managed-container deployment

For hosters that give you a Docker host and let you `compose up` your own
image: **TimmeHosting Container Hosting**, Hetzner Cloud, DigitalOcean
Droplets with Docker, generic VPS, etc.

This sits between the heavy K8s path and the legacy bare-metal path:

| Path             | What you bring                      | What the hoster brings              |
| ---------------- | ----------------------------------- | ----------------------------------- |
| `kubernetes`     | image + Kustomize manifests         | the cluster                         |
| **`managed-container`** | image + `compose.production.yaml` | a Docker host + reverse proxy + (optionally) managed DB/Redis |
| `bare-metal`     | code via rsync                      | PHP runtime, webserver, DB          |

## How it works

1. **CI builds your image** and pushes to `ghcr.io/<vendor>/<project>/shopware:<sha>` (already in place).
2. **`make deploy` reads `deployment.config`**, sees `DEPLOYMENT_MODE=managed-container`, and runs `deploy/managed-container/deploy.sh`.
3. **The script SSHes to the host, pulls the new image, and `docker compose up -d`** with zero downtime via a rolling restart.
4. **A pre-flight migration container** runs `shopware-deployment-helper run` before the web container swaps in — same pattern as the K8s pre-deploy Job.

## TimmeHosting specifics

TimmeHosting provides:
- Docker + `docker compose` pre-installed
- Reverse proxy with automatic TLS (their edge handles certs)
- Optional **managed MariaDB / Redis** — if you book them, point `DATABASE_URL` and `REDIS_DSN` at their internal hostnames and **delete the `db` / `redis` services** from `compose.production.yaml`
- Persistent storage at `/srv` or `/data` (per their docs)

What this template assumes by default:
- TLS terminates at the hoster's edge → the app container exposes plain HTTP on port 8000
- The hoster reverse-proxies `your-domain.tld` to that port (per their control panel)
- You either book their managed DB or run `db` + `redis` in the compose stack below
- Media / theme / sitemap directories are local Docker volumes — swap for an
  S3-backed mount or NFS if you scale beyond one host

Override these assumptions via `deploy/managed-container/env/<env>.env`.

## Quickstart

```bash
# 1. Per-host config (gitignored)
cp deploy/managed-container/env/example.env deploy/managed-container/env/production.env
$EDITOR deploy/managed-container/env/production.env   # fill SSH + image tag + domain

# 2. Switch the global config
sed -i 's/^DEPLOYMENT_MODE=.*/DEPLOYMENT_MODE=managed-container/' deployment.config

# 3. Deploy
make deploy ENV=production
```

## Rollback

```bash
make rollback ENV=production
```

This re-runs `deploy.sh` with `IMAGE_TAG=$(previous_tag)` — the previous tag
is stored in `~/.shopware-deploy/<env>/last-good-tag` on the remote host.

## File layout

```
deploy/managed-container/
├── compose.production.yaml    # the prod stack — web + worker + cron + optional db/redis
├── deploy.sh                  # SSH + pull + compose up with rolling restart
├── rollback.sh                # revert to the previous known-good image tag
├── env/
│   ├── example.env            # template
│   ├── staging.env            # gitignored
│   └── production.env         # gitignored
└── README.md
```
