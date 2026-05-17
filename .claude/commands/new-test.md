---
description: Generate a test (unit / integration / e2e) using the project's fixture pattern.
argument-hint: "<type> <subject-class-or-file>"
---

# /new-test

Generate a test for an existing piece of production code. Delegates to
`shopware-test-writer`.

## Process

1. **Parse `$ARGUMENTS`** — expected format `<type> <subject>`:
   - Type: `unit`, `integration`, or `e2e`. Reject anything else.
   - Subject: a class FQCN (e.g. `App\Service\PriceCalculator`) OR a
     file path (e.g. `src/Service/PriceCalculator.php`).
2. **Read the subject** — Claude must see the code before writing tests
   for it. Refuse if the file doesn't exist; suggest scaffolding the
   production code first.
3. **Hand to `shopware-test-writer`** with this brief:

   ```
   Write a <type> test for <subject>.

   File location:
   - unit:        tests/unit/<RelativePath>/<ClassName>Test.php
   - integration: tests/integration/<RelativePath>/<ClassName>Test.php
   - e2e:         tests/e2e/tests/<feature>.spec.ts

   Coverage target:
   - 1-3 happy-path tests
   - 1-2 edge cases (empty / boundary / error path)

   Conventions:
   - Integration tests: IntegrationTestBehaviour + IdsCollection
   - Fixture builders from tests/Fixtures/ (or extend if missing)
   - assertSame on concrete values, never assertNotEmpty as the only
     assertion
   - No sleep / waitForTimeout in Playwright — auto-wait expects
   ```

4. **After the agent finishes**: run the new test in isolation to make
   sure it passes:
   ```bash
   vendor/bin/phpunit <path-to-new-test>
   # or
   cd tests/e2e && npx playwright test <new-spec>
   ```
5. **Report** — pass/fail + suggested next step (often: run the full
   suite, or add the next test case).

Argument: `$ARGUMENTS` — `<type> <subject>` as described above.
