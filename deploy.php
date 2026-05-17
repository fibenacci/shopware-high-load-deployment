<?php
// =============================================================================
// Deployer recipe for bare-metal Shopware deploys.
//
// Reference: https://developer.shopware.com/docs/guides/hosting/installation-updates/deployments/deployment-with-deployer.html
//
// Run:
//   vendor/bin/dep deploy env=staging
//   vendor/bin/dep deploy env=production -o branch=v1.4.2
//   vendor/bin/dep rollback env=production
//
// Hosts and per-env paths come from deploy/bare-metal/env/*.env, which is
// loaded by the recipe below so the same target list works for both Deployer
// and the simpler `deploy/bare-metal/deploy.sh` fallback.
// =============================================================================

namespace Deployer;

require 'recipe/common.php';

// -----------------------------------------------------------------------------
// Globals
// -----------------------------------------------------------------------------
set('application', 'shopware-shop');
set('repository',   getenv('REPOSITORY') ?: 'git@github.com:example/shopware-shop.git');
set('default_timeout', 3600);
set('keep_releases', 5);
set('writable_mode', 'chmod');

// Shared between releases — Shopware's canonical list.
set('shared_dirs', [
    'config/jwt',
    'files',
    'public/media',
    'public/thumbnail',
    'public/sitemap',
    'public/bundles',
    'public/theme',
    'var/log',
]);

set('shared_files', [
    '.env.local',
    'auth.json',
]);

// Writable paths the webserver user needs to own.
set('writable_dirs', [
    'var',
    'public/media',
    'public/thumbnail',
    'public/sitemap',
    'public/bundles',
    'public/theme',
    'files',
]);

// -----------------------------------------------------------------------------
// Hosts — fed from deploy/bare-metal/env/<env>.env so the same SSH target list
// is shared with the simpler deploy.sh script.
// -----------------------------------------------------------------------------
$env = getenv('env') ?: get('env') ?: 'staging';
$envFile = __DIR__ . "/deploy/bare-metal/env/{$env}.env";

if (! is_file($envFile)) {
    throw new \RuntimeException("Missing env file: {$envFile} — copy from deploy/bare-metal/env/example.env");
}

$cfg = parse_ini_file($envFile, false, INI_SCANNER_RAW);
if ($cfg === false) {
    throw new \RuntimeException("Cannot parse {$envFile}");
}

host($env)
    ->setHostname($cfg['REMOTE_HOST'])
    ->setPort((int)($cfg['REMOTE_PORT'] ?? 22))
    ->setRemoteUser($cfg['REMOTE_USER'])
    ->setIdentityFile($cfg['REMOTE_SSH_KEY'] ?? '~/.ssh/id_ed25519')
    ->set('deploy_path', $cfg['REMOTE_PATH'])
    ->set('http_user',   $cfg['REMOTE_USER'])
    ->set('php_bin',     $cfg['REMOTE_PHP_BIN'] ?? '/usr/bin/php')
    ->set('public_url',  $cfg['PUBLIC_URL'] ?? '');

// -----------------------------------------------------------------------------
// Tasks
// -----------------------------------------------------------------------------

// 1. Composer install — no-dev, optimised autoloader.
task('shopware:composer:install', function () {
    run('cd {{release_path}} && {{php_bin}} {{bin/composer}} install --no-dev --optimize-autoloader --no-interaction --prefer-dist --no-scripts');
});

// 2. install.lock — Shopware uses this as the "is installed" sentinel.
task('shopware:touch_install_lock', function () {
    run('touch {{release_path}}/install.lock');
});

// 3. Run the canonical Shopware deployment-helper — does plugins, migrations,
//    theme compile, asset install, one-time tasks, store login.
task('shopware:deployment-helper', function () {
    run('cd {{release_path}} && {{php_bin}} vendor/bin/shopware-deployment-helper run');
});

// 4. Smoke test once the symlink is swapped.
task('shopware:smoke-test', function () {
    $url = get('public_url');
    if (! $url) {
        writeln('  (no public_url set — skipping smoke test)');
        return;
    }
    for ($i = 1; $i <= 20; $i++) {
        $code = trim((string) shell_exec("curl -s -o /dev/null -w '%{http_code}' '{$url}' || echo 000"));
        if ($code === '200') {
            writeln("<info>  Smoke test OK (HTTP 200)</info>");
            return;
        }
        writeln(sprintf('  attempt %2d/20 → HTTP %s', $i, $code));
        sleep(3);
    }
    throw new \RuntimeException("Smoke test failed for {$url}");
});

// 5. PHP-FPM opcache flush — preStop hook equivalent for bare-metal.
task('shopware:fpm:reload', function () {
    // Pulled from the env file in case the host uses a different unit name.
    global $cfg;
    $reload = $cfg['REMOTE_FPM_RELOAD_CMD'] ?? 'sudo systemctl reload php-fpm';
    if (($cfg['NO_FPM_RELOAD'] ?? '0') === '1') {
        run('touch {{deploy_path}}/current/public/index.php');
        return;
    }
    run($reload);
});

// -----------------------------------------------------------------------------
// Pipeline
// -----------------------------------------------------------------------------
desc('Deploy the shop');
task('deploy', [
    'deploy:prepare',
    'deploy:vendors',                 // overridden below — Shopware uses --no-dev
    'shopware:composer:install',
    'deploy:shared',
    'deploy:writable',
    'shopware:touch_install_lock',
    'shopware:deployment-helper',     // migrations, plugin install, theme compile
    'deploy:symlink',
    'shopware:fpm:reload',
    'shopware:smoke-test',
    'deploy:unlock',
    'deploy:cleanup',
]);

// Run `deploy:unlock` on failure to avoid stale lockfiles wedging the next run.
after('deploy:failed', 'deploy:unlock');
