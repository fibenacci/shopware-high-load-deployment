# Tests

Three suites, three speeds.

> 📖 Shopware test conventions: [Plugin tests](https://developer.shopware.com/docs/guides/plugins/plugins/testing/testing-with-phpunit.html)
> · [`TestBootstrapper`](https://github.com/shopware/shopware/blob/trunk/src/Core/TestBootstrapper.php) ·
> see also our [`/.build/phpunit-bootstrap.php`](../.build/phpunit-bootstrap.php).

| Suite         | Boots                             | Where                 | Runtime  | When it runs                  |
| ------------- | --------------------------------- | --------------------- | -------- | ----------------------------- |
| `unit`        | autoload only (no kernel, no DB)  | `tests/unit/`         | ms       | every push, every save        |
| `integration` | full Shopware kernel + test DB    | `tests/integration/`  | seconds  | every push                    |
| `e2e`         | Playwright against a real storefront | `tests/e2e/`       | minutes  | post-merge to main + pre-release |

Plugin-local tests live under `custom/static-plugins/*/tests/{Unit,Integration}`
and are auto-discovered by `phpunit.xml.dist`.

## Run locally

```bash
make test-unit           # PHPUnit unit suite
make test-integration    # PHPUnit integration suite — needs DB
make e2e                 # Playwright against http://$PROJECT_DOMAIN
make e2e-install         # one-time: npm install + browser download
```

## Run in CI

The CI workflow uses the pre-baked image — `make ci-bootstrap` boots it,
`make ci-phpunit` runs PHPUnit inside, `make ci-e2e` runs Playwright against
the in-container storefront. Reports are uploaded as artefacts and rendered
in the PR via `dorny/test-reporter`.

## Integration test DB

The bootstrap (`/.build/phpunit-bootstrap.php`) calls Shopware's
`TestBootstrapper`. It expects a database matching `DATABASE_URL` (set in
`phpunit.xml.dist`). To provision locally:

```bash
docker exec -it $PROJECT_NAME-mariadb mysql -uroot -proot -e \
    "CREATE DATABASE IF NOT EXISTS shopware_test CHARACTER SET utf8mb4;"
FORCE_INSTALL=1 make test-integration   # first run: installs Shopware into the test DB
make test-integration                    # subsequent runs: re-use the schema
```

## Coverage

```bash
make test           # writes build/clover.xml + build/coverage-html/
open build/coverage-html/index.html
```

## Adding a new test

```php
// tests/unit/ExampleTest.php
namespace App\Tests\Unit;

use PHPUnit\Framework\TestCase;

final class ExampleTest extends TestCase
{
    public function testSomethingTrue(): void
    {
        self::assertTrue(true);
    }
}
```

Integration tests get a `KernelTestBehaviour` trait for DB access:

```php
// tests/integration/Catalog/ProductRepositoryTest.php
namespace App\Tests\Integration\Catalog;

use PHPUnit\Framework\TestCase;
use Shopware\Core\Framework\Test\TestCaseBase\KernelTestBehaviour;

final class ProductRepositoryTest extends TestCase
{
    use KernelTestBehaviour;

    public function testRepositoryIsReachable(): void
    {
        $container = static::getContainer();
        self::assertTrue($container->has('product.repository'));
    }
}
```
