---
description: Shopware-flavoured security + performance audit of the current branch.
---

# /audit-shopware

Run a focused audit against Shopware-specific anti-patterns. Goes beyond
the generic security review by knowing what Shopware-specific code
"should" look like.

## What it checks

### Security
- **Twig**: `{{ ... }}` instead of `{{ ...|raw }}` where untrusted data
  enters. Flag any `|raw` filter on storefront templates.
- **DAL**: Raw SQL queries (`$connection->executeStatement(...)`)
  outside `Migration/`. If found, expect an ADR explaining why.
- **Routes**: storefront/store-api routes annotated with
  `_loginRequired=true` where customer data is read; admin-api routes
  with proper ACL annotations (`_acl: ['some_acl_key']`).
- **Migrations**: `updateDestructive()` empty (data loss prevention).
- **Snippets in errors**: production code that builds error messages
  from user input → XSS in admin notifications.

### Performance
- **N+1 queries**: `Criteria` without `addAssociation()` followed by
  iteration accessing the missing association.
- **DAL iterate** for > 1000 rows: should use `IterableQuery` / batch
  reads.
- **Subscribers without `getSubscribedEvents`** static return — slow
  reflection paths.
- **Twig**: `{% set ... = query(...) %}` patterns that hit the DB in
  the storefront — should be in the controller.

### Shopware version drift
- `compatibility_date` in `.shopware-project.yml` vs `SHOPWARE_VERSION`
  in `deployment.config` — diverging dates means plugin compat is
  checked against a different bar than what's actually running.
- Plugins pinning to old Shopware versions in their composer.json that
  block the next core bump.

### Hygiene
- DI services that have `public: true` without a documented reason
  (Symfony 5+ convention is private services).
- Plugin `composer.json` missing the `extra.shopware-plugin-class`
  pointer.
- Migrations without timestamps in their class name (Shopware ignores
  them silently).

## Process

1. **Decide scope** — single plugin, the whole `custom/` tree, or
   include `src/` too. Ask if ambiguous.
2. **Run static scans** in parallel:
   ```bash
   make phpstan
   git diff main...HEAD --name-only | grep '\.php$' | xargs grep -nE 'executeStatement|executeQuery|->raw\('
   git diff main...HEAD --name-only | grep '\.twig$' | xargs grep -nE '\|raw\b'
   ```
3. **Hand the structured findings to the user** as a Markdown report
   with severity + file:line + recommended fix.
4. **NEVER auto-fix** — this command surfaces issues; humans decide.

## Output

```markdown
# Shopware audit — <branch-name>

Generated: <UTC timestamp>

## BLOCKER (must fix before merge)
- [ ] [security] custom/static-plugins/Foo/Resources/views/storefront/page/x.html.twig:42
      `{{ user.note|raw }}` — XSS risk

## WARN
- [ ] [perf] custom/static-plugins/Foo/src/Subscriber/X.php:18
      Loop over order line items with no preloaded association

## INFO
- compatibility_date 2026-07-01 is older than SHOPWARE_VERSION 6.6.5.1's
  release date — verify plugin compat against current version
```

Save the report to `var/audit-<branch>-<UTC>.md` so it's reviewable in PRs.
