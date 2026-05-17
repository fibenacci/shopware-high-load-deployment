<?php
declare(strict_types=1);

namespace App\Tests\Integration;

use PHPUnit\Framework\TestCase;
use Shopware\Core\Framework\Test\TestCaseBase\KernelTestBehaviour;

/**
 * Confirms the test kernel boots and the DI container is reachable.
 * Use this as a template for project-specific integration tests.
 */
final class KernelBootTest extends TestCase
{
    use KernelTestBehaviour;

    public function testCoreServicesAreReachable(): void
    {
        $container = static::getContainer();

        self::assertTrue($container->has('product.repository'),    'product.repository missing');
        self::assertTrue($container->has('sales_channel.repository'), 'sales_channel.repository missing');
        self::assertTrue($container->has('order.repository'),      'order.repository missing');
    }
}
