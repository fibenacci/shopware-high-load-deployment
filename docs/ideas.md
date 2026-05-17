# Ideas / backlog

Ideas that came up during template development but didn't get built yet.
Each entry: the pain it solves, sketch of the solution, what's already
in the ecosystem to reuse, what is hard to automate.

Status legend: `proposed` (just an idea) · `accepted` (we want this) ·
`in-flight` (someone is working on it) · `done` (link to PR) · `dropped`
(decided against).

---

## Shopware upgrade helper

**Status**: proposed
**Pain**: Shopware major/minor updates ship breaking changes. Today every
upgrade starts with "find every deprecated API in our code, every Twig
block that's been removed, every plugin that won't load against the new
core". Manual, error-prone, easy to miss something until it explodes in
prod.

**Sketch**:

Two new make targets, phased so the scan is non-destructive and the apply
step has explicit checkpoints.

### `make upgrade-scan TARGET=6.7.0`

Produces `var/upgrade-report-<from>-to-<to>.md` with severity-bucketed
findings:

1. **Composer dependency delta** — `composer outdated --direct --format=json`,
   filtered to `shopware/*` and direct deps.
2. **Deprecated PHP-API calls** — PHPStan run with Shopware deprecation
   rules enabled (`shopware/phpstan-config` extension if available, or
   a custom rule level).
3. **Rector auto-fixable items** — `rector process --dry-run --output-format=json`
   against the `shopware/rector` ruleset for the target version. Counts +
   file list, severity = `auto-fixable`.
4. **CHANGELOG breaking changes** — scrape the `___NEXT-MAJOR___` and
   `# Removed` sections from every Shopware CHANGELOG entry between the
   current and target version (the format is structured since 6.5).
5. **Plugin compatibility status** — `shopware-cli extension validate`
   per plugin against the target `compatibility_date`. Lists which
   plugins need updates / will block.
6. **Twig / theme overrides at risk** — grep storefront-templates for
   `{% sw_extends %}` paths that the target version removes (needs a
   pre-fetched index of removed blocks per version).
7. **Migration preview** — `composer require shopware/core:~6.7.0 --dry-run`
   to see if the constraints even resolve.

Severity buckets: `BLOCKER` (compile/parse error), `WARNING` (deprecated,
runs but rotting), `INFO` (doc-only change).

### `make upgrade-apply` (only after the scan)

Each phase is git-checkpointed and the worker stops between phases for
confirmation unless `--auto` is passed (CI mode for staging upgrades).

```
0. git tag pre-upgrade-<sha>           always-revertable checkpoint
1. rector process                       commit per rule-set
2. composer require --update            lock the new versions
3. bin/console database:migrate --dry-run
4. bin/console database:migrate          actual migration
5. bin/console plugin:refresh + update   per plugin, interactive stop
6. make test-unit && test-integration    gate
7. make e2e                              full storefront smoke
8. shopware-deployment-helper run        canonical post-upload
```

On any failure: `git reset --hard pre-upgrade-<sha>` + restore the pre-
upgrade DB backup snapshot.

**What's already in the ecosystem to reuse**:

- [`shopware/rector`](https://github.com/shopware/rector) — auto-fix rules
  per major version
- `shopware-cli extension validate` — plugin compatibility check
- PHPStan — deprecated API detection
- `shopware/CHANGELOG.md` — structured breaking-change markers since 6.5
- `composer outdated --format=json` — version drift

**What is NOT automatable (humans needed)**:

- Custom Twig templates referencing removed blocks — Rector knows PHP,
  not Twig. Needs a separate grep heuristic + manual review.
- Plugin semantic drift — e.g. an Event subscriber that now receives a
  different Event object shape. Tests catch this; Rector doesn't.
- Data migrations with business logic (custom entity → core entity
  merger). Manual review unavoidable.

**Risks**:

- Composer resolution loop — if a third-party plugin pins to an old
  Shopware version, `composer require` will refuse to upgrade. The scan
  has to surface this clearly so the operator knows it's a plugin-vendor
  problem, not a code problem.
- Rector aggressiveness — some auto-fixes change semantics in edge cases
  (e.g. property visibility changes that affect plugin overrides). Always
  keep the `pre-upgrade-<sha>` tag around for a week before pruning.

**Estimated effort**: Phase 1 (`upgrade-scan`) ≈ 1-2 days. Phase 2
(`upgrade-apply`) ≈ 3-5 days. Phase 1 alone solves ~80% of the "where
do I even start" pain.

**Priority**: medium — should land before the first major-version bump
this template's users hit. Until then, the scan output also makes for
useful release-note material.

---

## Fixture exporter plugin (with scenarios)

**Status**: proposed
**Pain**: writing fixture builders for complex Shopware entities by hand
is tedious — a single product with variants + price rules + visibility +
custom fields is dozens of lines of DAL chaining. Devs would much rather
click it together in admin once, then "freeze" it as a reusable fixture.

### Idea v1 — the obvious version

A plugin (`SwagFixtureExporter` or similar) plus a CLI:

```
bin/console fixture:export product 01a3f8... --output=tests/Fixtures/Generated/demo-shoe.php
```

Produces a PHP file that calls our existing fixture builders:

```php
// Generated from shop @ 2026-05-18T09:22:00Z, Shopware 6.6.5.1
// Source UUID: 01a3f8... (ignored on import — looked up by name)
ProductFixture::create($ids, 'demo-shoe')
    ->name(['en-GB' => 'Demo Shoe', 'de-DE' => 'Demo-Schuh'])
    ->price(99.95, taxRate: 19.0)
    ->stock(50)
    ->category('Footwear')   // resolved by name at import
    ->visibility('Storefront');
```

Scope: Product, Customer, Order, Category, Rule, SalesChannel (the 6
entities behind ~80% of fixture work). Plugin entities later via a hook.

**Design constraints** (each one a foot-gun if ignored):

| Concern | Approach |
| --- | --- |
| Entity-graph boundary (a Product → Category → Parent → SC → Rules…) | Explicit "include vs lookup-by-name" list per entity. No unbounded walks. |
| UUID portability (source IDs don't exist in target DB) | Resolve all refs by stable identifier (`name`, `productNumber`, `customerNumber`). UUIDs only for in-test `IdsCollection`. |
| Translations | Always export every `_translation` row for every locale present. |
| PII (customers, orders) | Anonymize-default like `shopware-cli project dump --anonymize`. `--keep-pii` requires confirmation + audit log. |
| Schema drift across Shopware versions | Version header in output + roundtrip CI check (export → import → re-export must be byte-identical). |
| Output format | **PHP builder calls, not YAML/JSON**. IDE-completable, refactor-safe, comments survive. YAML reads beautifully for 3 fields and atrociously for 30. |

### Idea v2 — scenarios as the actual unit of reuse

The bigger win isn't "export this entity" — it's "export this **situation**":

> "give me the scenario `b2b-customer-with-net-pricing-and-staff-discount`"
> "give me `guest-checkout-with-free-shipping-promotion`"
> "give me `order-stuck-in-pending-payment-state`"

A **scenario** is a named, composable set of fixtures that encodes intent.
Tests use scenarios, not raw entities:

```php
final class CheckoutDiscountTest extends TestCase
{
    use IntegrationTestBehaviour;

    public function testStaffDiscountApplies(): void
    {
        $scenario = $this->loadScenario('b2b-customer-with-staff-discount');
        // $scenario gives back an IdsCollection with everything wired up.

        $cart = $this->cartService->createNew($scenario->id('customer'));
        $this->cartService->add($cart, $scenario->id('product-a'));

        $this->assertEquals(85.00, $cart->getPrice()->getTotalPrice());
    }
}
```

Why this beats "just export an entity":

| Raw-entity export | Scenario export |
| --- | --- |
| Reusable per-entity | Reusable per-situation — the actual unit tests care about |
| Test reads: "create product X, create customer Y, attach rule Z" — *what for?* | Test reads: "load scenario 'b2b with staff discount'" — intent visible at call site |
| Every test rebuilds the world from primitives | Tests share the dozen scenarios that matter; fewer to maintain |
| Schema drift hurts proportionally to number of fixtures (many) | Schema drift hurts proportionally to number of scenarios (few) |
| No documentation value | Scenario files become a living catalogue of "ways this shop can be in" |

Scenarios fit cleanly on top of the v1 exporter:

```
1. Dev clicks together the situation in admin (or API-replays it)
2. bin/console fixture:export-scenario <name>
   → walks the recent DAL writes, groups them as a named scenario
   → writes tests/Fixtures/Scenarios/<name>.php
3. Tests call loadScenario('<name>')
```

Combined with **scenario coverage**: a CI check that fails if a scenario
file isn't referenced by at least one test (orphan detection — keeps the
catalogue honest).

### Reference: how other ecosystems do it

- **Laravel** — Model Factories with named states (`Customer::factory()->b2b()->withDiscount()`)
- **Rails** — `fixtures/*.yml` files + scenarios via traits
- **Django** — `fixtures/*.json` + `factory_boy` for parametrised factories
- **Symfony** — `DoctrineFixturesBundle` (declarative but verbose for nested DAL)

Shopware doesn't ship a scenario pattern out of the box, which is why
this is a real gap.

### What's NOT solved by this

- **Plugin entities** — generic Exporter won't know about plugin-specific
  DAL tables without per-plugin contributions. v1 ignores them; plugin
  authors can add their entities via a hook later.
- **Multi-tenant test isolation** — a scenario named `b2b-customer-with-...`
  in one project might collide with the same name in another. Scenarios
  are project-scoped, not portable across shops without renaming.
- **Generated-data realism** — scenarios are deterministic, which is
  exactly what tests need but the opposite of what stresstests need.
  Stresstests still want `framework:demodata`-style randomness.

### Estimated effort

- **v1 (raw entity exporter)** ≈ 2 weeks for 6 entities + reference
  resolver + roundtrip tests + CLI. Skip admin UI initially.
- **v2 (scenarios layer on top)** ≈ 1 additional week — mostly the
  `loadScenario()` helper, the orphan-detection check, and writing the
  first 10 scenarios for the team's most common test setups.

### Priority

Medium — only earns out once the team has written ~5 fixture builders by
hand. Until then, hand-rolling is cheaper than maintaining a plugin.
After that point the slope flips fast.

### Concrete dependencies on the rest of this template

- Requires the `tests/Fixtures/` builder layer to exist first (see the
  earlier "test fixtures with PHP builders" plan). The exporter writes
  *into* that builder API; it doesn't replace it.
- Requires `IntegrationTestBehaviour` for the rollback-based test
  isolation that makes scenarios safe to load per test.

---

<!-- Add new ideas above this line. One ## heading per idea. -->
