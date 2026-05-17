# CI image — extends dockware/dev with the codebase pre-installed and the
# storefront pre-built. Bootstrap then has nothing to do at container start
# beyond `compose up`, which keeps reruns fast.
#
# Build context: repo root (compose.ci.yml passes `context: ../..`).
# Build args:
#   COMPOSER_AUTH    JSON with github-oauth + bearer entries.
#
# Layer order is tuned for cache reuse:
#   1. base                                       rebuilds: never
#   2. composer.json/.lock + custom/ → composer install
#                                                 rebuilds: lock OR custom change
#   3. config/ + src/ + CI drop-in                rebuilds: src/ or config/ change
#   4. in-image setup (MariaDB up → plugin:install + theme compile → MariaDB down)
FROM dockware/dev:6.6.5.1

USER root
WORKDIR /var/www/html

ENV COMPOSER_ALLOW_SUPERUSER=1 \
    SHOPWARE_ES_ENABLED=0 \
    SHOPWARE_ES_INDEXING_ENABLED=0 \
    SHOPWARE_ADMIN_ES_ENABLED=0 \
    SHOPWARE_ES_THROW_EXCEPTION=0 \
    REDIS_CACHE_HOST=127.0.0.1 \
    REDIS_CACHE_PORT=6379 \
    REDIS_CACHE_PASSWORD="" \
    REDIS_CACHE_DATABASE=0 \
    REDIS_SESSION_HOST=127.0.0.1 \
    REDIS_SESSION_PORT=6379 \
    REDIS_SESSION_PASSWORD="" \
    REDIS_SESSION_DATABASE=1

COPY composer.json composer.lock ./
COPY custom ./custom
ARG COMPOSER_AUTH=""
RUN COMPOSER_AUTH="$COMPOSER_AUTH" composer install \
        --no-interaction --prefer-dist --no-progress --no-scripts \
    && rm -rf /root/.composer/cache

COPY config ./config
COPY src    ./src
RUN rm -f config/packages/dev/elasticsearch.yaml

# CI drop-in: filesystem cache + sync messenger transports → no Redis /
# RabbitMQ sidecars needed to boot the storefront. The `zz-` prefix
# guarantees Symfony loads this file last.
COPY .github/ci/symfony-ci-overrides.yaml ./config/packages/zz-ci-overrides.yaml

# Boot MariaDB once during the build so plugin:install can write rows; stop
# it cleanly so the data files survive in the image layer. Docker's
# anonymous-volume init then seeds the fresh volume on every `compose up`.
RUN set -eux; \
    service mysql start; \
    for _ in $(seq 1 30); do \
        mysqladmin ping -h 127.0.0.1 --silent && break || sleep 1; \
    done; \
    bin/console plugin:refresh --no-interaction; \
    for dir in custom/static-plugins/*/ custom/plugins/*/; do \
        plugin=$(basename "${dir%/}"); \
        bin/console plugin:install --activate --no-interaction "$plugin" 2>/dev/null || true; \
    done; \
    ./bin/build-storefront.sh; \
    service mysql stop; \
    chown -R www-data:www-data /var/www/html
