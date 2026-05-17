# syntax=docker/dockerfile:1.7
# =============================================================================
# Production image — built on Shopware's official base images.
#
# Reference: https://developer.shopware.com/docs/guides/hosting/installation-updates/docker.html
#
# Stages:
#   build   shopware-cli compiles the project (composer + assets + theme)
#   app     Shopware's runtime base (FrankenPHP or php-fpm) — default web image
#   worker  same as app, CMD = "worker" (messenger consumer)
#
# The cron CronJob in K8s uses the `app` image with `args: ["cron"]` —
# no separate stage needed.
# Image variants are selected via build args from deployment.config:
#
#   PHP_VERSION       8.3
#   PHP_RUNTIME       frankenphp | fpm           (default: frankenphp)
#   SHOPWARE_BASE     ghcr.io/shopware/docker-base
#   APP_VERSION       short SHA, baked into /app/VERSION
#   TIDEWAYS_ENABLE   0|1, opt-in Tideways
# =============================================================================

ARG PHP_VERSION=8.3
ARG PHP_RUNTIME=frankenphp
ARG SHOPWARE_BASE=ghcr.io/shopware/docker-base
ARG SHOPWARE_CLI=ghcr.io/shopware/shopware-cli:latest-php-${PHP_VERSION}
ARG APP_VERSION=0.0.0
ARG TIDEWAYS_ENABLE=0
ARG TIDEWAYS_VERSION=2024.1.2

# ---------------------------------------------------------------------------
# Stage 1: build — shopware-cli does composer + storefront + admin + theme.
#                  https://sw-cli.fos.gg/commands/project/#shopware-cli-project-ci
# ---------------------------------------------------------------------------
FROM ${SHOPWARE_CLI} AS build

WORKDIR /src

# Composer auth gets baked in only at build time; it never lands in the
# final image (multi-stage drops everything in /src after the COPY below).
ARG COMPOSER_AUTH=""
ENV COMPOSER_AUTH=${COMPOSER_AUTH}

# Copy the bare minimum first so composer.lock changes invalidate fewer layers.
COPY composer.json composer.lock symfony.lock* auth.json* ./
COPY custom ./custom
COPY config ./config
COPY src    ./src
COPY public ./public
COPY bin    ./bin
COPY .shopware-project.yml ./

# `shopware-cli project ci` runs the canonical build pipeline:
#   composer install --no-dev → admin build → storefront build → theme compile
# It also strips dev dependencies and source maps from the final tree.
RUN shopware-cli project ci .

# ---------------------------------------------------------------------------
# Stage 2: final runtime — Shopware's official base.
# ---------------------------------------------------------------------------
FROM ${SHOPWARE_BASE}:${PHP_VERSION}-${PHP_RUNTIME} AS app

ARG APP_VERSION
RUN mkdir -p /app && echo "${APP_VERSION}" > /app/VERSION

# Shopware base already sets sane defaults — we override only what's
# project-specific (PHP tuning + the deployment-helper integration).
COPY docker/php/php.ini /usr/local/etc/php/conf.d/zz-shopware.ini

# Optional: Tideways. Default OFF; flip TIDEWAYS_ENABLE=1 at build time.
ARG TIDEWAYS_ENABLE
ARG TIDEWAYS_VERSION
RUN if [ "${TIDEWAYS_ENABLE}" = "1" ]; then \
        apt-get update && apt-get install -y --no-install-recommends curl \
        && curl -fsSL "https://tideways.com/packages/tideways-php-${TIDEWAYS_VERSION}-amd64.deb" -o /tmp/tw.deb \
        && dpkg -i /tmp/tw.deb || apt-get install -y -f \
        && rm -f /tmp/tw.deb \
        && rm -rf /var/lib/apt/lists/* ; \
    fi

WORKDIR /var/www/html
COPY --from=build --chown=www-data:www-data /src /var/www/html

# The Shopware base mounts these paths as the volumes you bind from S3 / EFS
# in production. We declare them so a `docker run` without explicit mounts
# still works for ad-hoc tasks.
VOLUME ["/var/www/html/files", "/var/www/html/public/theme", "/var/www/html/public/media", "/var/www/html/public/thumbnail", "/var/www/html/public/sitemap"]

COPY docker/scripts/entrypoint.sh /usr/local/bin/shopware-entrypoint
COPY docker/scripts/healthcheck.sh /usr/local/bin/shopware-healthcheck
RUN chmod +x /usr/local/bin/shopware-entrypoint /usr/local/bin/shopware-healthcheck

# FrankenPHP listens on 8000 by default; FPM variant exposes 9000.
EXPOSE 8000 8443

HEALTHCHECK --interval=10s --timeout=3s --start-period=30s --retries=6 \
    CMD shopware-healthcheck || exit 1

ENTRYPOINT ["shopware-entrypoint"]
CMD ["web"]

# ---------------------------------------------------------------------------
# Stage 3: worker — same image, different default CMD.
#
# The cron CronJob doesn't get its own stage — it runs the `app` image with
# `args: ["cron"]` (see k8s/base/cronjob.yaml). One image, three roles.
# ---------------------------------------------------------------------------
FROM app AS worker
CMD ["worker"]
