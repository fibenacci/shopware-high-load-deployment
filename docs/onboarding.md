# Onboarding — first day

Welcome. **Seven steps**, top-to-bottom, ~30 minutes. After this you
should have a working local shop, a clear picture of where things live,
and tools wired up to keep your future PRs clean.

If anything fails, jump to [Troubleshooting](#troubleshooting).

## 1. Required tools (~5 min)

```bash
docker --version              # ≥ 24
docker compose version        # ≥ 2.20
make --version                # any
git --version                 # ≥ 2.40 (for signed commits)
gh --version                  # optional but useful

# Mac:
brew install gitleaks gpg shopware-cli
# Linux: equivalent packages from your distro
```

## 2. Clone + bootstrap (~3 min)

```bash
git clone <repo>
cd shopware-shop
make setup                    # one-shot — diagnose + copy env files +
                              # render composer.json + wire git hooks
```

`make setup` is idempotent — safe to re-run any time. It does NOT touch
secrets and refuses nothing; it prints a TODO list at the end of what
still needs human input (typically: fill in `auth.json` + configure
signed commits).

## 3. Fill in `auth.json` (~3 min)

`make setup` copied `auth.json.example` to `auth.json` with placeholder
tokens. Replace them with real ones:

- `github-oauth.github.com` — a GitHub PAT with `read:packages` scope.
  Used for private composer repos. Ask the team lead for the
  team-shared token if your org uses one.
- `bearer.packages.shopware.com` — your Shopware Store account token.
  Self-serve at `https://account.shopware.com` → Integrations.

## 4. Sign your commits (~10 min, one-time forever)

CI rejects unsigned commits. SSH signing is the fastest path if you
already have a GitHub SSH key:

```bash
git config --global gpg.format ssh
git config --global commit.gpgsign true
git config --global user.signingkey ~/.ssh/id_ed25519.pub
```

Then register the SAME key as a *signing key* on GitHub:
**Settings → SSH and GPG keys → New SSH key → Key type: Signing Key**.

Verify:
```bash
git commit --allow-empty -m "test: signing"
git log --show-signature -1
```

Full GPG alternative + troubleshooting: [`signed-commits.md`](./signed-commits.md).

## 5. Start the local stack (~10 min — first run)

```bash
make up
```

What happens:

1. Boots the Dinghy reverse proxy on `:80` / `:443`.
2. Brings up MariaDB, OpenSearch, Redis, RabbitMQ, Mailpit, Shopware
   app + worker container, Nginx ingress.
3. Runs `entrypoint-dev.sh` inside the app container — composer install,
   DB setup, admin user.

When done you see a banner with every URL:

| Service | URL |
| --- | --- |
| Storefront | http://shop.docker |
| Admin | http://shop.docker/admin (`admin` / `shopware`) |
| Mailpit | http://mail.shop.docker |
| Adminer | http://adminer.shop.docker |
| Redis Commander | http://redis.shop.docker |
| RabbitMQ | http://rabbitmq.shop.docker |

If you see "host not found" for `*.shop.docker` — your DNS resolver
isn't set up. See [Troubleshooting](#troubleshooting).

## 6. Run the tests (~5 min)

```bash
make test-unit                # fast: pure logic, no kernel
make test-integration         # slower: kernel + DB
make e2e-install              # one-time: Playwright + Chromium download
make e2e                      # browser tests against http://shop.docker
```

Green on all four? You're up. If anything red, see Troubleshooting.

## 7. Read the conventions, save them somewhere (~5 min)

Two files contain everything that's enforced:

- [`CONTRIBUTING.md`](../CONTRIBUTING.md) — PR process, what CI checks, where docs live
- [`CLAUDE.md`](../CLAUDE.md) — what Claude Code knows about this project (which is what *you* should also know)

Open both, skim, bookmark.

For deeper dives: [`docs/README.md`](./README.md) is the categorised
index of every doc.

---

## What you have now

- A working local Shopware shop on `http://shop.docker`
- Pre-commit hooks gating secrets + style + syntax
- Signed commits ready to go
- All four test suites passing locally
- The team's conventions in your head (or at least bookmarked)

You're ready to pick up a story.

## Where to start

```bash
ls docs/stories/              # if your team uses /new-story
# or check the team's project board
```

If you're scaffolding something new:

```bash
# new plugin
/new-plugin MyShopFeature     # in Claude Code

# new test for existing code
/new-test integration App\\Service\\PriceCalculator
```

## Troubleshooting

### `*.shop.docker` doesn't resolve

You skipped the macOS DNS-resolver setup. Run:
```bash
sudo mkdir -p /etc/resolver
echo "nameserver 127.0.0.1" | sudo tee /etc/resolver/docker
sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder
```

On Linux, see the [Dinghy proxy docs](https://github.com/codekitchen/dinghy-http-proxy)
for the iptables-based path.

### `make up` says network "proxy" doesn't exist

```bash
docker network create proxy
make up
```

### `composer install` errors with 401 / 403

`auth.json` tokens are wrong or missing. Re-check step 3.

### `http://shop.docker/` returns 403, `/admin` returns 404

Your `public/`, `src/`, or `config/` got bind-mounted as empty
directories over Dockware's pre-installed Shopware. Symptom: ingress
container running, app container "healthy", but no `index.php` to serve.

```bash
make scaffold-shop          # extracts the missing skeleton from Dockware
make reset && make up        # re-runs the in-container bootstrap
```

`make scaffold-shop` spins up a throwaway Dockware container, copies
out `public/index.php`, `src/Kernel.php`, `config/bundles.php`, etc.
into the bind-mounted host paths. Existing files are never overwritten.

### `ClassNotFoundError: App\Kernel` from `public/index.php`

The `vendor/` directory in the named volume `app_vendor` was built
before `composer.json` had the `autoload` section pointing `App\` at
`src/`. Composer install ran fine; the autoloader just doesn't know
the namespace yet. Fix:

```bash
make dump-autoload          # fast — regenerates only autoload_psr4.php
# if that doesn't help:
make composer-install       # full vendor refresh
# nuclear option:
docker compose down && docker volume rm shopware-shop_app_vendor && make up
```

### `Table 'shopware.sales_channel' doesn't exist` / `shopware.plugin doesn't exist`

The `shopware` database exists but has no schema. Happens on fresh
volumes or when `entrypoint-dev.sh` skipped the install step (e.g.
because `.db_imported` was already set from an earlier failed run).

```bash
make install-shop            # bin/console system:install --basic-setup
                             # admin: admin / shopware, sample sales channel created
```

`entrypoint-dev.sh` runs this automatically on first boot when no
`dump.sql.gz` is present, but if you got into this state via a partial
deploy or volume reset, `make install-shop` is the same operation as
a one-shot.

### Pre-commit hook rejects every commit with "signing not enabled"

You missed step 4. `git config --get commit.gpgsign` should print `true`.

### `make test-integration` fails with "Connection refused"

The test DB isn't reachable. Make sure `make up` is running:
```bash
docker compose ps             # mariadb should be "healthy"
```

### `gh pr create` says you need to push first

```bash
git push -u origin HEAD
```

### Everything looks weird and you want to start over

```bash
make down
docker compose down -v        # nuclear option — wipes volumes
make up                       # rebuilds from scratch
```

### Still stuck

```bash
make doctor                   # re-run the diagnostic
make logs                     # tail the app container
```

Then post in `#shopware-deployment` (or whatever your team's channel
is). Attach `make doctor` output.
