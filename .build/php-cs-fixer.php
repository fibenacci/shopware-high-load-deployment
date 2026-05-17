<?php
declare(strict_types=1);

$finder = (new PhpCsFixer\Finder())
    ->in([
        __DIR__ . '/../custom/static-plugins',
        __DIR__ . '/../custom/plugins',
        __DIR__ . '/../src',
        __DIR__ . '/../tests',
    ])
    ->exclude(['Resources', 'node_modules', 'vendor', 'var'])
    ->notPath('Migration')
    ->name('*.php');

return (new PhpCsFixer\Config())
    ->setRiskyAllowed(true)
    ->setUsingCache(true)
    ->setFinder($finder)
    ->setRules([
        '@PSR12'                                     => true,
        '@PSR12:risky'                               => true,
        '@PhpCsFixer'                                => true,
        '@PhpCsFixer:risky'                          => true,
        '@PHP83Migration'                            => true,
        '@PHP80Migration:risky'                      => true,
        'declare_strict_types'                       => true,
        'concat_space'                               => ['spacing' => 'one'],
        'global_namespace_import'                    => ['import_classes' => true, 'import_constants' => true, 'import_functions' => true],
        'native_function_invocation'                 => false,
        'ordered_imports'                            => ['sort_algorithm' => 'alpha', 'imports_order' => ['class', 'function', 'const']],
        'phpdoc_align'                               => ['align' => 'left'],
        'php_unit_test_class_requires_covers'        => false,
        'php_unit_internal_class'                    => false,
        'single_line_throw'                          => false,
        // Shopware uses ::class everywhere; the rule below sometimes fights it.
        'fully_qualified_strict_types'               => true,
    ]);
