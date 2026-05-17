# Tiny image used by the shopware-db-backup CronJob.
# Just mysqldump + openssl + aws-cli + bash, on Alpine.

FROM alpine:3.20

RUN apk add --no-cache \
        bash \
        ca-certificates \
        coreutils \
        gnupg \
        gzip \
        mariadb-client \
        openssl \
        py3-pip \
    && pip3 install --no-cache-dir --break-system-packages awscli \
    && rm -rf /var/cache/apk/*

# The actual command lives in the CronJob manifest — keep the image generic
# so the same image can run ad-hoc restores too:
#
#   kubectl run restore -it --rm --image=ghcr.io/EXAMPLE/shopware-backup:latest \
#       --env=AWS_ACCESS_KEY_ID=... --env=AWS_SECRET_ACCESS_KEY=... \
#       --command -- bash

CMD ["/bin/bash"]
