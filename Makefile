.DEFAULT_GOAL := help

# ============================================================================
# Shopware Shop Deployment — single entry point for every workflow.
#
# Global config: deployment.config. Override any value on the command line
# (e.g. `make up SHOPWARE_VERSION=6.6.6.0`). Env-files in .env.local /
# deploy/bare-metal/env/*.env layer on top.
# ============================================================================

include deployment.config
export

# Local-dev defaults — overridden by .env.local for any real environment.
# Real secrets MUST come from .env.local (gitignored) for compose, GH Actions
# secrets for CI, K8s Secrets for prod. Never commit a real password here.
MYSQL_ROOT_PASSWORD ?= root
MYSQL_PASSWORD ?= shopware
REDIS_CACHE_PASSWORD ?= redis

FORCE_HTTP ?= 1
SHOPWARE_CONTAINER ?= $(PROJECT_NAME)-app
DB_CONTAINER ?= $(PROJECT_NAME)-mariadb
STOREFRONT_PORT ?= 8080
ENV ?= $(DEFAULT_ENV)

# Resolve the dockware image tag from SHOPWARE_VERSION unless explicitly overridden.
DOCKWARE_TAG ?= $(SHOPWARE_VERSION)

.PHONY: help config doctor setup setup-hooks scaffold-shop verify composer-json composer-json-check \
        composer-install dump-autoload install-shop \
        preflight up stop down restart logs shell reset \
        cache theme build-storefront build-admin watch-storefront watch-admin \
        fix-domain check-domain fetch-dump import-dump export-dump \
        reindex reindex-admin reindex-all messenger-consume messenger-stats \
        phpstan php-cs-fixer php-cs-fixer-check phpcs phpmd \
        test test-unit test-integration e2e e2e-install e2e-report \
        ci-bootstrap ci-phpunit ci-e2e ci-teardown \
        monitoring-up monitoring-down monitoring-logs \
        k3s-up k3s-down stresstest \
        k8s-staging k8s-production k8s-diff-staging k8s-diff-production \
        deploy rollback deploy-docker deploy-kubernetes deploy-bare-metal \
        deploy-managed-container \
        build-image push-image image-build image-push remote-console

help: ## Show available targets
	@printf "\n\033[1mShopware Shop Deployment — make targets\033[0m\n"
	@printf "\033[2mproject: %s | shopware: %s | php: %s | node: %s | mode: %s\033[0m\n" \
		"$(PROJECT_NAME)" "$(SHOPWARE_VERSION)" "$(PHP_VERSION)" "$(NODE_VERSION)" "$(DEPLOYMENT_MODE)"
	@awk 'BEGIN {FS = ":.*##"} \
		/^##@/ {printf "\n\033[1;36m%s\033[0m\n", substr($$0, 5); next} \
		/^[A-Za-z0-9_.-]+:.*##/ {printf "  \033[36m%-30s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)
	@printf "\n"

composer-json: ## Render composer.json from composer.json.example + deployment.config
	@./scripts/render-composer.sh

composer-json-check: ## Verify composer.json matches template + deployment.config (CI gate)
	@./scripts/render-composer.sh --check

verify: ## Tier-1 sanity — runs every static check the template owns. No side effects.
	@./scripts/verify.sh

config: ## Print the resolved global config (sanity check)
	@printf "PROJECT_NAME       = %s\n" "$(PROJECT_NAME)"
	@printf "PROJECT_DOMAIN     = %s\n" "$(PROJECT_DOMAIN)"
	@printf "SHOPWARE_VERSION   = %s\n" "$(SHOPWARE_VERSION)"
	@printf "PHP_VERSION        = %s\n" "$(PHP_VERSION)"
	@printf "NODE_VERSION       = %s\n" "$(NODE_VERSION)"
	@printf "DEPLOYMENT_MODE    = %s\n" "$(DEPLOYMENT_MODE)"
	@printf "DOCKWARE_IMAGE     = %s:%s\n" "$(DOCKWARE_IMAGE)" "$(DOCKWARE_TAG)"
	@printf "IMAGE_APP          = %s\n" "$(IMAGE_APP)"
	@printf "IMAGE_WORKER       = %s\n" "$(IMAGE_WORKER)"
	@printf "IMAGE_BACKUP       = %s\n" "$(IMAGE_BACKUP)"
	@printf "IMAGE_VARNISH      = %s\n" "$(IMAGE_VARNISH)"
	@printf "TIDEWAYS_ENABLE    = %s\n" "$(TIDEWAYS_ENABLE)"
	@printf "DEFAULT_ENV        = %s\n" "$(DEFAULT_ENV)"

##@ Stack lifecycle (local dev)

scaffold-shop: ## Re-extract Shopware project skeleton (public/index.php, src/Kernel.php, …) from the Dockware image
	@printf "\033[1m▶ Scaffolding Shopware project skeleton from %s:%s\033[0m\n" "$(DOCKWARE_IMAGE)" "$(DOCKWARE_TAG)"
	@# Spin up a throwaway Dockware container with NO bind-mounts so its
	@# pre-installed skeleton is visible, then docker-cp the files we need.
	@# Never overwrites — if the host already has a non-empty file, skip it.
	@cid=$$(docker create $(DOCKWARE_IMAGE):$(DOCKWARE_TAG) 2>/dev/null); \
	if [ -z "$$cid" ]; then \
		echo "  ✗ Could not create scratch container. Run 'docker pull $(DOCKWARE_IMAGE):$(DOCKWARE_TAG)' first."; \
		exit 1; \
	fi; \
	for f in public/index.php public/.htaccess src/Kernel.php config/bundles.php config/services.yaml config/preload.php; do \
		if [ -e "$$f" ] && [ -s "$$f" ]; then \
			printf "  · %s already present — skipping\n" "$$f"; \
			continue; \
		fi; \
		mkdir -p "$$(dirname "$$f")"; \
		if docker cp "$$cid:/var/www/html/$$f" "$$f" 2>/dev/null; then \
			printf "  ✓ extracted %s\n" "$$f"; \
		else \
			printf "  ⚠ %s not found in image — skipping\n" "$$f"; \
		fi; \
	done; \
	docker rm -f "$$cid" >/dev/null 2>&1; \
	printf "✓ skeleton ready — run 'make reset && make up' to re-bootstrap\n"

setup: ## One-shot initial bootstrap — idempotent, safe to re-run
	@printf "\n\033[1m▶ Step 1/5: Diagnose local environment\033[0m\n"
	@$(MAKE) -s --ignore-errors doctor 2>&1 | grep -v 'make\['; true
	@printf "\n\033[1m▶ Step 2/5: Local env files\033[0m\n"
	@todos=""; \
	if [ ! -f .env.local ]; then \
		cp .env.example .env.local; \
		printf "  \033[1;32m✓\033[0m .env.local created from .env.example\n"; \
	else \
		printf "  \033[1;32m✓\033[0m .env.local already exists\n"; \
	fi; \
	if [ ! -f auth.json ]; then \
		cp auth.json.example auth.json; \
		printf "  \033[1;33m⚠\033[0m auth.json created with PLACEHOLDER tokens — fill in before 'make up'\n"; \
		todos="$$todos\n    • Edit auth.json — fill in github-oauth + packages.shopware.com tokens"; \
	elif grep -q 'REPLACE_WITH_' auth.json 2>/dev/null; then \
		printf "  \033[1;33m⚠\033[0m auth.json still has REPLACE_WITH_* placeholders — composer will 401\n"; \
		todos="$$todos\n    • Edit auth.json — replace the REPLACE_WITH_* placeholders"; \
	else \
		printf "  \033[1;32m✓\033[0m auth.json present\n"; \
	fi; \
	if [ ! -f sales-channel-hosts.local.map ]; then \
		cp sales-channel-hosts.local.map.dist sales-channel-hosts.local.map; \
		printf "  \033[1;32m✓\033[0m sales-channel-hosts.local.map created\n"; \
	else \
		printf "  \033[1;32m✓\033[0m sales-channel-hosts.local.map already exists\n"; \
	fi; \
	if [ ! -f .fetch-dump.local.env ] && [ -f .fetch-dump.local.env.example ]; then \
		printf "  \033[2m·\033[0m .fetch-dump.local.env not created (optional — needed only for 'make fetch-dump PROFILE=...')\n"; \
	fi; \
	echo "$$todos" > .setup.todos; \
	\
	printf "\n\033[1m▶ Step 3/5: Render composer.json from deployment.config\033[0m\n"; \
	for f in composer.json composer.lock; do \
		if [ -d "$$f" ] && [ -z "$$(ls -A "$$f" 2>/dev/null)" ]; then \
			rmdir "$$f"; \
			printf "  \033[1;33m⚠\033[0m removed leftover empty %s/ directory from a failed compose up\n" "$$f"; \
		fi; \
	done; \
	$(MAKE) -s composer-json; \
	if [ ! -f composer.lock ]; then \
		echo '{}' > composer.lock; \
		printf "  \033[1;32m✓\033[0m composer.lock seeded (composer install in the container fills it)\n"; \
	fi; \
	\
	printf "\n\033[1m▶ Step 4/5: Wire git hooks\033[0m\n"; \
	$(MAKE) -s setup-hooks; \
	\
	printf "\n\033[1m▶ Step 5/5: Summary\033[0m\n"; \
	signed=$$(git config --get commit.gpgsign 2>/dev/null || echo false); \
	if [ "$$signed" != "true" ]; then \
		echo "    • Configure signed commits — required by CI"; \
		echo "        git config --global gpg.format ssh"; \
		echo "        git config --global commit.gpgsign true"; \
		echo "        git config --global user.signingkey ~/.ssh/id_ed25519.pub"; \
		echo "      (Full: docs/signed-commits.md)"; \
	fi; \
	if [ -s .setup.todos ]; then \
		printf "%b\n" "$$(cat .setup.todos)"; \
	fi; \
	rm -f .setup.todos; \
	printf "    • Run \033[1;36mmake up\033[0m to boot the stack\n"; \
	printf "    • Then open \033[1;36mhttp://%s\033[0m (admin / shopware)\n\n" "$(PROJECT_DOMAIN)"; \
	printf "\033[1;32m✅ setup complete — see TODOs above\033[0m\n"

preflight: ## Verify local env files are in place (gate for `make up`)
	@# composer.json + composer.lock are NOT bind-mounted in the default
	@# compose.yaml — Dockware's pre-installed Shopware is served as-is.
	@# We render composer.json on the host as a "source of truth" for the
	@# project's intended dependency model; adopters who later enable
	@# compose.override.yaml.example mount it into the container.
	@if [ ! -f .env.local ]; then \
		echo "Creating .env.local from .env.example"; cp .env.example .env.local; \
	fi
	@if [ ! -f auth.json ]; then \
		echo "ERROR: Missing auth.json — copy from auth.json.example and fill in tokens."; exit 1; \
	fi
	@if [ ! -f sales-channel-hosts.local.map ]; then \
		cp sales-channel-hosts.local.map.dist sales-channel-hosts.local.map; \
	fi
	@if [ ! -f composer.json ]; then \
		echo "Rendering composer.json from composer.json.example"; \
		$(MAKE) -s composer-json; \
	fi

doctor: ## Diagnose local setup — required tools, env files, hooks, signing, networks
	@printf "\033[1mShopware Shop Deployment — doctor\033[0m\n"
	@printf "  project: %s · domain: %s · mode: %s\n\n" "$(PROJECT_NAME)" "$(PROJECT_DOMAIN)" "$(DEPLOYMENT_MODE)"
	@status=0; \
	check() { \
		if eval "$$2" >/dev/null 2>&1; then \
			printf "  \033[1;32m✓\033[0m %s\n" "$$1"; \
		else \
			printf "  \033[1;31m✗\033[0m %s\n    \033[2m%s\033[0m\n" "$$1" "$$3"; status=1; \
		fi; \
	}; \
	soft() { \
		if eval "$$2" >/dev/null 2>&1; then \
			printf "  \033[1;32m✓\033[0m %s\n" "$$1"; \
		else \
			printf "  \033[1;33m⚠\033[0m %s\n    \033[2m%s\033[0m\n" "$$1" "$$3"; \
		fi; \
	}; \
	echo "Required tools:"; \
	check "docker"             "docker --version"        "Install Docker Desktop or your distro's docker"; \
	check "docker compose v2"  "docker compose version"  "Update Docker — Compose v2 ships with recent Docker"; \
	check "make"               "make --version"          "Install make"; \
	check "git ≥ 2.40"         "git --version"           "Install git (needed for signed commits)"; \
	echo ""; \
	echo "Recommended tools:"; \
	soft  "gitleaks"           "command -v gitleaks"     "brew install gitleaks — pre-commit hook uses it"; \
	soft  "shopware-cli"       "command -v shopware-cli" "Install from https://sw-cli.fos.gg — needed for fetch-dump + extension validate"; \
	soft  "gh (GitHub CLI)"    "command -v gh"           "brew install gh — useful but not required"; \
	soft  "kubectl"            "command -v kubectl"      "Only needed for DEPLOYMENT_MODE=kubernetes"; \
	soft  "kustomize"          "command -v kustomize"    "Only needed for DEPLOYMENT_MODE=kubernetes"; \
	soft  "k6"                 "command -v k6"           "Only needed for ad-hoc stresstests outside CI"; \
	echo ""; \
	echo "Local files:"; \
	check ".env.local"                       "test -f .env.local"                       "cp .env.example .env.local"; \
	check "auth.json"                        "test -f auth.json"                        "cp auth.json.example auth.json — then fill in tokens"; \
	check "sales-channel-hosts.local.map"    "test -f sales-channel-hosts.local.map"    "cp sales-channel-hosts.local.map.dist sales-channel-hosts.local.map"; \
	echo ""; \
	echo "Git hooks + signing:"; \
	hp=$$(git config --get core.hooksPath 2>/dev/null); \
	if [ "$$hp" = ".githooks" ]; then \
		printf "  \033[1;32m✓\033[0m git core.hooksPath = .githooks\n"; \
	else \
		printf "  \033[1;31m✗\033[0m git core.hooksPath = %s\n    \033[2mmake setup-hooks\033[0m\n" "$${hp:-<unset>}"; status=1; \
	fi; \
	sign_on=$$(git config --get commit.gpgsign 2>/dev/null || echo false); \
	if [ "$$sign_on" = "true" ]; then \
		printf "  \033[1;32m✓\033[0m commit.gpgsign = true\n"; \
		fmt=$$(git config --get gpg.format 2>/dev/null || echo openpgp); \
		key=$$(git config --get user.signingkey 2>/dev/null); \
		if [ "$$fmt" = "ssh" ] && [ -z "$$key" ]; then \
			printf "  \033[1;31m✗\033[0m gpg.format=ssh but user.signingkey is unset\n    \033[2mgit config --global user.signingkey ~/.ssh/id_ed25519.pub\033[0m\n"; status=1; \
		fi; \
	else \
		printf "  \033[1;31m✗\033[0m commit.gpgsign disabled — CI rejects unsigned commits\n    \033[2mSee docs/signed-commits.md for the 4-line SSH-signing setup\033[0m\n"; status=1; \
	fi; \
	echo ""; \
	echo "Docker runtime:"; \
	check "docker daemon"            "docker info"                           "Start Docker Desktop / the docker daemon"; \
	check "proxy network"            "docker network inspect proxy"          "docker network create proxy"; \
	soft  "Dinghy http-proxy"        "docker inspect -f '{{.State.Status}}' http-proxy | grep -q running"  "Auto-started by 'make up'"; \
	echo ""; \
	if [ "$$(uname)" = "Darwin" ]; then \
		echo "macOS resolver:"; \
		if [ -f /etc/resolver/docker ]; then \
			printf "  \033[1;32m✓\033[0m /etc/resolver/docker exists\n"; \
		else \
			printf "  \033[1;33m⚠\033[0m /etc/resolver/docker missing — *.$(PROJECT_DOMAIN) won't resolve\n    \033[2mecho 'nameserver 127.0.0.1' | sudo tee /etc/resolver/docker\033[0m\n"; \
		fi; \
		echo ""; \
	fi; \
	if [ $$status -eq 0 ]; then \
		printf "\033[1;32m✅ all green — ready for 'make up'\033[0m\n"; \
	else \
		printf "\033[1;31m✗ blockers above — fix them, then re-run 'make doctor'\033[0m\n"; \
		exit 1; \
	fi

setup-hooks: ## Point git at .githooks/ — gitleaks + php-cs-fixer + syntax + signed-commits gate
	@current="$$(git config --local core.hooksPath || true)"; \
	if [ "$$current" = ".githooks" ]; then \
		echo "✓ core.hooksPath already set to .githooks"; \
	else \
		git config core.hooksPath .githooks; \
		echo "✓ core.hooksPath set to .githooks"; \
	fi
	@sign_on=$$(git config --get commit.gpgsign || echo false); \
	if [ "$$sign_on" != "true" ]; then \
		echo ""; \
		echo "⚠ commit signing is NOT enabled — pre-commit will block."; \
		echo "  Quick path (SSH signing):"; \
		echo "    git config --global gpg.format ssh"; \
		echo "    git config --global commit.gpgsign true"; \
		echo "    git config --global user.signingkey ~/.ssh/id_ed25519.pub"; \
		echo "  Full setup: docs/signed-commits.md"; \
	else \
		echo "✓ commit signing enabled"; \
	fi

up: preflight ## Start the full local stack (boots Dinghy proxy on demand)
	@echo "▶ Ensuring Dinghy HTTP proxy is running"
	@docker network create proxy 2>/dev/null || true
	@docker start http-proxy 2>/dev/null || docker run -d --restart=always \
		--name http-proxy \
		--network proxy \
		-v /var/run/docker.sock:/tmp/docker.sock:ro \
		-v ~/.dinghy/certs:/etc/nginx/certs \
		-p 80:80 -p 443:443 \
		-e CONTAINER_NAME=http-proxy \
		codekitchen/dinghy-http-proxy
	@docker compose --env-file deployment.config --env-file .env.local up -d
	@echo "▶ Waiting for app container to settle"
	@sleep 8
	@docker exec $(SHOPWARE_CONTAINER) bash /setup-custom.sh || true
	@$(MAKE) _banner

_banner:
	@printf "\n\033[1mShopware shop is ready\033[0m\n"
	@printf "  Frontend:        http://$(PROJECT_DOMAIN)\n"
	@printf "  Admin:           http://$(PROJECT_DOMAIN)/admin   (admin / shopware)\n"
	@printf "  Mailpit:         http://mail.$(PROJECT_DOMAIN)\n"
	@printf "  OpenSearch:      http://opensearch.$(PROJECT_DOMAIN)\n"
	@printf "  OS Dashboards:   http://opensearch-dashboards.$(PROJECT_DOMAIN)\n"
	@printf "  RabbitMQ:        http://rabbitmq.$(PROJECT_DOMAIN)\n"
	@printf "  Redis Commander: http://redis.$(PROJECT_DOMAIN)\n"
	@printf "  Adminer:         http://adminer.$(PROJECT_DOMAIN)\n\n"

stop: ## Stop containers
	@docker compose stop

down: ## Remove containers (keeps volumes)
	@docker compose down

restart: ## Restart the app container
	@docker compose restart app

logs: ## Follow app logs
	@docker compose logs -f app

shell: ## Open a shell inside the app container
	@docker exec -it $(SHOPWARE_CONTAINER) bash

reset: ## Remove setup flags so the next `make up` reinstalls
	@docker exec $(SHOPWARE_CONTAINER) rm -f /var/www/html/.setup_complete /var/www/html/.db_imported || true

##@ Cache & assets

cache: ## bin/console cache:clear inside the container
	@docker exec $(SHOPWARE_CONTAINER) bin/console cache:clear

install-shop: ## Install Shopware schema into an empty DB (basic-setup: admin user + sample sales channel)
	@docker exec -w /var/www/html $(SHOPWARE_CONTAINER) bin/console system:install \
		--create-database --basic-setup --force \
		--shop-locale="$(INSTALL_LOCALE)" \
		--shop-currency="$(INSTALL_CURRENCY)"
	@docker exec $(SHOPWARE_CONTAINER) bin/console cache:clear
	@printf "\033[1;32m✓\033[0m Shopware installed — admin: %s / %s\n" \
		"$(INSTALL_ADMIN_USERNAME)" "$${INSTALL_ADMIN_PASSWORD:-shopware}"
	@printf "  Open: http://%s/admin\n" "$(PROJECT_DOMAIN)"

composer-install: ## Re-run composer install in the container (regenerates vendor/ + autoloader)
	@docker exec -w /var/www/html $(SHOPWARE_CONTAINER) composer install --no-interaction --optimize-autoloader

dump-autoload: ## Regenerate the Composer autoloader inside the running container (fast)
	@docker exec -w /var/www/html $(SHOPWARE_CONTAINER) composer dump-autoload --optimize
	@docker exec $(SHOPWARE_CONTAINER) bin/console cache:clear --no-interaction || true

theme: ## Compile the storefront theme
	@docker exec $(SHOPWARE_CONTAINER) bin/console theme:compile

build-storefront: ## Rebuild storefront assets
	@docker exec -it $(SHOPWARE_CONTAINER) bash -c 'bin/build-storefront.sh'

build-admin: ## Rebuild administration assets
	@docker exec -it $(SHOPWARE_CONTAINER) bash -c 'bin/build-administration.sh'

watch-storefront: ## Storefront watcher (HMR)
	@docker exec -it $(SHOPWARE_CONTAINER) bash -lc 'bin/watch-storefront.sh'

watch-admin: ## Admin watcher (HMR)
	@docker exec -it $(SHOPWARE_CONTAINER) bash -lc 'bin/watch-administration.sh'

##@ Database & domain

fix-domain: ## Apply sales-channel-hosts.local.map
	@status=0; \
	docker exec -e FORCE_HTTP=$(FORCE_HTTP) $(SHOPWARE_CONTAINER) bash /apply-sales-channel-domains.sh /var/www/html/sales-channel-hosts.local.map || status=$$?; \
	if [ "$$status" -eq 10 ]; then \
		echo "No mapping found, falling back to http://$(PROJECT_DOMAIN)"; \
		docker exec $(SHOPWARE_CONTAINER) bin/console sales-channel:update:domain "$(PROJECT_DOMAIN)" --no-interaction; \
	elif [ "$$status" -ne 0 ]; then exit $$status; fi
	@docker exec $(SHOPWARE_CONTAINER) bin/console cache:clear

check-domain: ## Show current sales channel domains
	@docker exec $(DB_CONTAINER) mysql -uroot -p$$MYSQL_ROOT_PASSWORD shopware -e "SELECT id, url, sales_channel_id FROM sales_channel_domain;"

fetch-dump: ## Fetch anonymized dump from a remote — PROFILE=<name> or interactive wizard
	@PROFILE="$(PROFILE)" \
	 ALLOW_UNANONYMIZED="$(ALLOW_UNANONYMIZED)" \
	 FORCE_OVERWRITE="$(FORCE_OVERWRITE)" \
	 ./docker/scripts/fetch-dump.sh

import-dump: ## Drop/recreate DB and import dump.sql.gz
	@docker exec $(DB_CONTAINER) mysql -uroot -p$(MYSQL_ROOT_PASSWORD) -e "DROP DATABASE IF EXISTS shopware; CREATE DATABASE shopware CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
	@docker exec $(SHOPWARE_CONTAINER) bash -c 'gunzip < /dump.sql.gz | mysql -hmariadb -uroot -p$(MYSQL_ROOT_PASSWORD) shopware'
	@$(MAKE) fix-domain
	@docker exec $(SHOPWARE_CONTAINER) bin/console cache:clear

export-dump: ## Export container DB to dump.sql.gz
	@docker exec $(DB_CONTAINER) mysqldump -uroot -p$(MYSQL_ROOT_PASSWORD) shopware | gzip > dump.sql.gz

##@ Search & messenger

reindex: ## OpenSearch reindex (storefront)
	@docker exec $(SHOPWARE_CONTAINER) bin/console es:index

reindex-admin: ## Index admin search into OpenSearch
	@docker exec $(SHOPWARE_CONTAINER) bin/console es:admin:index

reindex-all: reindex reindex-admin messenger-consume ## Storefront + admin + queue drain

messenger-consume: ## Drain Messenger queues
	@docker exec $(SHOPWARE_CONTAINER) bin/console messenger:consume async low_priority failed --time-limit=300 --memory-limit=256M -v

messenger-stats: ## Show queue depth per transport
	@docker exec $(SHOPWARE_CONTAINER) bin/console messenger:stats async low_priority failed

##@ Code quality

phpstan: ## PHPStan
	@docker exec -w /var/www/html $(SHOPWARE_CONTAINER) vendor/bin/phpstan analyse -c .build/phpstan.neon --no-progress

php-cs-fixer: ## Auto-fix style
	@docker exec -w /var/www/html $(SHOPWARE_CONTAINER) vendor/bin/php-cs-fixer fix --config=.build/php-cs-fixer.php --allow-risky=yes --using-cache=no --no-interaction custom/static-plugins

php-cs-fixer-check: ## Dry-run style check (same scope as CI)
	@docker exec -w /var/www/html $(SHOPWARE_CONTAINER) vendor/bin/php-cs-fixer fix --config=.build/php-cs-fixer.php --allow-risky=yes --dry-run --diff --using-cache=no --no-interaction custom/static-plugins

phpcs: ## PHPCS
	@docker exec -w /var/www/html $(SHOPWARE_CONTAINER) vendor/bin/phpcs --extensions=php --standard=.build/phpcs.xml custom/static-plugins

phpmd: ## PHPMD
	@docker exec -w /var/www/html $(SHOPWARE_CONTAINER) vendor/bin/phpmd custom/static-plugins text .build/phpmd.xml --strict

##@ Testsx

test: ## Run all PHPUnit tests
	@docker exec -w /var/www/html $(SHOPWARE_CONTAINER) vendor/bin/phpunit

test-unit: ## Unit suite
	@docker exec -w /var/www/html $(SHOPWARE_CONTAINER) vendor/bin/phpunit --testsuite unit

test-integration: ## Integration suite (boots kernel + DB)
	@docker exec -w /var/www/html $(SHOPWARE_CONTAINER) vendor/bin/phpunit --testsuite integration

e2e-install: ## Install Playwright (once per machine)
	@cd tests/e2e && npm install && npx playwright install chromium

e2e: ## Run Playwright suite against local storefront
	@cd tests/e2e && BASE_URL=http://$(PROJECT_DOMAIN) npx playwright test

e2e-report: ## Open latest Playwright HTML report
	@cd tests/e2e && npx playwright show-report

##@ CI (consumed by .github/workflows/ci.yml)

ci-bootstrap: ## Build + boot the pre-baked CI image
	@.github/ci/scripts/bootstrap.sh

ci-phpunit: ## Run PHPUnit inside the CI image, copy JUnit back to host
	@.github/ci/scripts/phpunit.sh

ci-e2e: ## Run Playwright suite against the CI storefront
	@.github/ci/scripts/playwright.sh tests/e2e

ci-teardown: ## Tear down CI stack (WITH_LOGS=1 dumps recent logs first)
	@if [ "$(WITH_LOGS)" = "1" ]; then .github/ci/scripts/teardown.sh --with-logs; else .github/ci/scripts/teardown.sh; fi

##@ Monitoring (LGTM stack)

monitoring-up: ## Boot Prometheus + Grafana + Loki + Pyroscope locally
	@docker compose -f monitoring/compose.monitoring.yaml up -d

monitoring-down: ## Stop monitoring stack
	@docker compose -f monitoring/compose.monitoring.yaml down

monitoring-logs: ## Tail monitoring stack logs
	@docker compose -f monitoring/compose.monitoring.yaml logs -f

##@ Kubernetes / k3s

k8s-staging: ## kubectl apply -k k8s/overlays/staging
	@kubectl apply -k k8s/overlays/staging

k8s-production: ## kubectl apply -k k8s/overlays/production (confirms first)
	@printf "Apply k8s/overlays/production? [y/N] "; read ans; [ "$$ans" = "y" ] || exit 1
	@kubectl apply -k k8s/overlays/production

k8s-diff-staging: ## Diff staging overlay against the live cluster
	@kubectl diff -k k8s/overlays/staging || true

k8s-diff-production: ## Diff production overlay against the live cluster
	@kubectl diff -k k8s/overlays/production || true

k3s-up: ## Install k3s + load images locally
	@./k3s/install-k3s.sh

k3s-down: ## Uninstall k3s
	@/usr/local/bin/k3s-uninstall.sh 2>/dev/null || sudo k3s-uninstall.sh

stresstest: ## Run k6 stresstest against the cluster
	@kubectl apply -f k3s/stresstest/k6-job.yaml
	@kubectl wait --for=condition=complete --timeout=15m job/shopware-stresstest
	@kubectl logs -l job-name=shopware-stresstest --tail=-1

##@ Images (production)

image-build: ## Build prod images — app, worker, backup
	@sha=$$(git rev-parse --short HEAD); \
	echo "▶ Building $(IMAGE_APP):$$sha"; \
	docker buildx build \
		--target app \
		--build-arg PHP_VERSION=$(PHP_VERSION) \
		--build-arg NODE_VERSION=$(NODE_VERSION) \
		--build-arg APP_VERSION=$$sha \
		--build-arg TIDEWAYS_ENABLE=$(TIDEWAYS_ENABLE) \
		--build-arg TIDEWAYS_VERSION=$(TIDEWAYS_VERSION) \
		-t $(IMAGE_APP):$$sha \
		-t $(IMAGE_APP):latest \
		-f docker/Dockerfile . ; \
	echo "▶ Building $(IMAGE_WORKER):$$sha"; \
	docker buildx build --target worker \
		--build-arg PHP_VERSION=$(PHP_VERSION) \
		-t $(IMAGE_WORKER):$$sha \
		-f docker/Dockerfile . ; \
	echo "▶ Building $(IMAGE_BACKUP):$$sha"; \
	docker buildx build \
		-t $(IMAGE_BACKUP):$$sha \
		-t $(IMAGE_BACKUP):latest \
		-f docker/backup/Dockerfile docker/backup

image-push: ## Push all prod images to the registry
	@sha=$$(git rev-parse --short HEAD); \
	docker push $(IMAGE_APP):$$sha; \
	docker push $(IMAGE_APP):latest; \
	docker push $(IMAGE_WORKER):$$sha; \
	docker push $(IMAGE_BACKUP):$$sha; \
	docker push $(IMAGE_BACKUP):latest

##@ Deployment (dispatches by DEPLOYMENT_MODE)

deploy: ## Deploy to ENV — dispatches based on DEPLOYMENT_MODE in deployment.config
	@case "$(DEPLOYMENT_MODE)" in \
		docker)             $(MAKE) deploy-docker ;; \
		kubernetes)         $(MAKE) deploy-kubernetes ENV=$(ENV) ;; \
		bare-metal)         $(MAKE) deploy-bare-metal ENV=$(ENV) ;; \
		managed-container)  $(MAKE) deploy-managed-container ENV=$(ENV) ;; \
		*)                  echo "Unknown DEPLOYMENT_MODE: $(DEPLOYMENT_MODE)" >&2; exit 1 ;; \
	esac

rollback: ## Roll back the active deployment for ENV
	@case "$(DEPLOYMENT_MODE)" in \
		kubernetes)         kubectl -n shopware-$(ENV) rollout undo deploy/shopware-web; \
		                    kubectl -n shopware-$(ENV) rollout undo deploy/shopware-worker ;; \
		bare-metal)         ENV=$(ENV) deploy/bare-metal/rollback.sh ;; \
		managed-container)  ENV=$(ENV) deploy/managed-container/rollback.sh ;; \
		docker)             echo "No remote deploy to roll back for DEPLOYMENT_MODE=docker"; exit 1 ;; \
		*)                  echo "Unknown DEPLOYMENT_MODE: $(DEPLOYMENT_MODE)" >&2; exit 1 ;; \
	esac

deploy-docker: ## Restart the local compose stack with the current code
	@docker compose up -d --build

deploy-kubernetes: ## kubectl apply -k k8s/overlays/$(ENV)
	@kubectl apply -k k8s/overlays/$(ENV)
	@kubectl -n shopware-$(ENV) rollout status deploy/shopware-web --timeout=10m
	@kubectl -n shopware-$(ENV) rollout status deploy/shopware-worker --timeout=10m

deploy-bare-metal: ## Deployer (deploy.php) → atomic release swap to ENV
	@if [ -x vendor/bin/dep ]; then \
		vendor/bin/dep deploy env=$(ENV) ; \
	else \
		echo "▶ Deployer not installed — using shell fallback"; \
		ENV=$(ENV) REVISION=$(REVISION) deploy/bare-metal/deploy.sh ; \
	fi

deploy-managed-container: ## SSH + docker compose pull/up against ENV (TimmeHosting, generic VPS)
	@ENV=$(ENV) IMAGE_TAG=$(IMAGE_TAG) deploy/managed-container/deploy.sh

remote-console: ## Run bin/console on the remote — usage: make remote-console ARGS="cache:clear"
	@case "$(DEPLOYMENT_MODE)" in \
		bare-metal)        ENV=$(ENV) deploy/bare-metal/console.sh $(ARGS) ;; \
		managed-container) ssh -i $$(grep ^REMOTE_SSH_KEY deploy/managed-container/env/$(ENV).env | cut -d= -f2) \
		                       $$(grep ^REMOTE_USER deploy/managed-container/env/$(ENV).env | cut -d= -f2)@$$(grep ^REMOTE_HOST deploy/managed-container/env/$(ENV).env | cut -d= -f2) \
		                       "cd $$(grep ^REMOTE_PATH deploy/managed-container/env/$(ENV).env | cut -d= -f2) && docker compose exec web bin/console $(ARGS)" ;; \
		kubernetes)        kubectl -n shopware-$(ENV) exec -it deploy/shopware-web -- bin/console $(ARGS) ;; \
		*)                 echo "remote-console not available for DEPLOYMENT_MODE=$(DEPLOYMENT_MODE)" >&2; exit 1 ;; \
	esac
