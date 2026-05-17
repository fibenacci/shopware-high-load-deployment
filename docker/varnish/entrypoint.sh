#!/bin/sh
# Render BACKEND_HOST/PORT into the VCL at runtime, then exec varnishd.
# Keeps the image generic — the same image deploys to staging and prod
# with different backends.
set -e

sed -i "s|__BACKEND_HOST__|${BACKEND_HOST}|g" /etc/varnish/default.vcl
sed -i "s|__BACKEND_PORT__|${BACKEND_PORT}|g" /etc/varnish/default.vcl

exec varnishd \
    -F \
    -a "${VARNISH_LISTEN}" \
    -f /etc/varnish/default.vcl \
    -s "malloc,${VARNISH_SIZE}" \
    -p default_grace=120 \
    -p default_keep=600
