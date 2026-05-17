# Varnish edge cache for Shopware 6.
#
# ⚠️  PREFERRED PATH: use Shopware's official image instead of this Dockerfile.
#     https://github.com/shopware/varnish-shopware
#     ghcr.io/shopware/varnish-shopware:latest
#
# The official image ships the canonical Shopware VCL with the `xkey` module
# pre-installed — Shopware uses xkey-based surrogate-key invalidation in
# current versions, which is more efficient than the BAN approach this
# self-contained VCL falls back to. Point the K8s Deployment at it:
#
#     image: ghcr.io/shopware/varnish-shopware:latest
#
# Keep this Dockerfile only when you need a vendored build (air-gapped
# clusters, custom plugin VCL, regulatory image-provenance requirements).
#
# Reference:
#   https://developer.shopware.com/docs/guides/hosting/infrastructure/reverse-http-cache.html
#
# Run (self-contained build):
#   docker build -t shop-varnish docker/varnish/
#   docker run -p 80:80 -e BACKEND_HOST=shopware-web -e BACKEND_PORT=8000 shop-varnish

FROM varnish:7.6

USER root

# Cache size — overridden by VARNISH_SIZE env. Default 256m suits a small
# pod; raise via the K8s Deployment env for prod.
ENV VARNISH_SIZE=256m \
    VARNISH_LISTEN=:80 \
    BACKEND_HOST=shopware-web \
    BACKEND_PORT=8000

COPY default.vcl /etc/varnish/default.vcl
COPY entrypoint.sh /usr/local/bin/varnish-entrypoint
RUN chmod +x /usr/local/bin/varnish-entrypoint

USER varnish

EXPOSE 80

HEALTHCHECK --interval=10s --timeout=3s --start-period=10s --retries=3 \
    CMD varnishadm ping || exit 1

ENTRYPOINT ["varnish-entrypoint"]
