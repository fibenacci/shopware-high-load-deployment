# Bare-metal deployment

Classic SSH + rsync deployment for hosts where Docker isn't an option
(shared hosting, managed PHP, legacy infrastructure). Layout follows the
**Capistrano release model** so deploys are atomic and rollbacks are O(1).

## Directory layout on the remote host

```
/var/www/shopware/                  ← $REMOTE_PATH
├── releases/
│   ├── 20260512-141055/             ← previous release
│   ├── 20260516-092130/             ← current release (target of `current`)
│   └── ...
├── shared/
│   ├── .env.local                   ← persisted between deploys
│   ├── auth.json
│   ├── config/jwt/                  ← Shopware JWT keys (one-time generated)
│   ├── public/media/                ← user-uploaded media
│   ├── public/thumbnail/
│   ├── public/sitemap/
│   ├── public/bundles/              ← plugin assets (auto-installed)
│   ├── public/theme/                ← compiled theme
│   ├── var/log/
│   └── files/
└── current → releases/20260516-092130/   ← symlink swapped atomically
```

`current` is the document root your webserver should be configured to serve
from. The symlink swap is the only "live" step — everything else happens in
a fresh release directory and only becomes user-visible when the symlink
flips.

## Per-environment config

Copy and adapt one file per environment:

```bash
cp deploy/bare-metal/env/example.env deploy/bare-metal/env/staging.env
cp deploy/bare-metal/env/example.env deploy/bare-metal/env/production.env
```

These files are **not** committed (they're listed in `.gitignore`).

## Run a deploy

```bash
# from your laptop or from CI
make deploy ENV=staging                          # uses the active git revision
make deploy ENV=production REVISION=v1.4.2       # deploy a tag

# emergency rollback (atomic — flips `current` to the previous release)
make rollback ENV=production
```

## Pipeline (`deploy.sh`)

1. **Pre-flight** — SSH connectivity, PHP version match, MariaDB reachable,
   `shared/` populated, disk space.
2. **Composer build on the runner** — `composer install --no-dev` + asset
   build, packaged into a tarball.
3. **rsync to a fresh release dir** — `$REMOTE_PATH/releases/$STAMP/`.
4. **Symlink shared dirs/files** into the release.
5. **Migrate + warm cache** on the remote (one-shot ssh).
6. **Theme compile** + media thumbnails.
7. **Atomic symlink swap** — `ln -nfs $STAMP current`.
8. **Reload PHP-FPM** so opcache flushes.
9. **Smoke test** the public URL.
10. **Prune** old releases (keep last 5).

If any step fails before the swap, the live site is untouched. Failures
after the swap fall back to `make rollback`.

## CI integration

`.github/workflows/deploy.yml` already speaks both modes — it reads
`DEPLOYMENT_MODE` from `deployment.config` and dispatches to either
`kubectl apply` or `make deploy ENV=...`.
