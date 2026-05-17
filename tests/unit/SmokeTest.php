<?php
declare(strict_types=1);

namespace App\Tests\Unit;

use PHPUnit\Framework\TestCase;

/**
 * Sanity check — confirms PHPUnit + autoload are wired up.
 * Delete once you have real unit tests in place.
 */
final class SmokeTest extends TestCase
{
    public function testPhpUnitIsReachable(): void
    {
        self::assertTrue(true);
    }

    public function testProjectAutoloadResolves(): void
    {
        self::assertTrue(class_exists(\Composer\Autoload\ClassLoader::class));
    }
}
