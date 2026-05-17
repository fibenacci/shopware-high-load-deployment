<?php
declare(strict_types=1);

// PHPUnit bootstrap. Mirrors what Shopware's own test suites use:
//   1. Composer autoloader
//   2. Symfony dotenv (.env + .env.test)
//   3. KernelLifecycleManager registers a clean kernel per test
//
// Test database: KERNEL_CLASS=Shopware\Core\Kernel + APP_ENV=test selects the
// configuration under config/packages/test/*.yaml. The DATABASE_URL in
// phpunit.xml.dist points at a `shopware_test` database; integration tests
// expect it to exist (CI provisions it, locally `make test-integration`
// uses the dev DB with a fresh schema).

use Shopware\Core\TestBootstrapper;

$projectRoot = dirname(__DIR__);
require_once $projectRoot . '/vendor/autoload.php';

if (! class_exists(TestBootstrapper::class)) {
    fwrite(STDERR, "shopware/core is missing — run `composer install` first.\n");
    exit(1);
}

(new TestBootstrapper())
    ->setProjectDir($projectRoot)
    ->setLoadEnvFile(true)
    ->setForceInstall((bool) ($_ENV['FORCE_INSTALL'] ?? false))
    ->setEnvFile($projectRoot . '/.env.test')
    ->bootstrap();
