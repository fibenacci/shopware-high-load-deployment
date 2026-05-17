#!/usr/bin/env bash
# Run every maintained-plugin PHPUnit suite inside the CI container and copy
# the JUnit XML back to the host so actions/upload-artifact can pick it up.
# The CI compose stack runs without bind mounts (the image IS the project
# state), so files written by `docker exec` live only inside the container.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "${REPO_ROOT}" || exit 1

# Discover every plugin that ships a phpunit config. No hardcoded list —
# adding a plugin is a `git add` away from CI coverage.
mapfile -t PLUGIN_PATHS < <(
    find custom/static-plugins custom/plugins -mindepth 2 -maxdepth 2 \
         -name 'phpunit.xml*' -printf '%h\n' 2>/dev/null | sort -u
)

if [ "${#PLUGIN_PATHS[@]}" -eq 0 ]; then
    echo "::warning::No phpunit.xml found under custom/ — nothing to run."
    exit 0
fi

overall_rc=0
for plugin_path in "${PLUGIN_PATHS[@]}"; do
    junit="${plugin_path}/build/junit-phpunit.xml"
    mkdir -p "${plugin_path}/build"
    docker exec -w /var/www/html shopware-ci mkdir -p "${plugin_path}/build"

    echo "▶ PHPUnit: ${plugin_path}"
    docker exec -w /var/www/html shopware-ci vendor/bin/phpunit \
        --configuration "${plugin_path}/phpunit.xml.dist" \
        --log-junit "${junit}"
    rc=$?

    docker cp "shopware-ci:/var/www/html/${junit}" "${junit}" 2>/dev/null \
        || echo "::warning::Could not retrieve ${junit} from container"
    [ "${rc}" -ne 0 ] && overall_rc=1
done

exit "${overall_rc}"
