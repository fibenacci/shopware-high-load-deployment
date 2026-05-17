# User Story Template

Copy this when starting a new story. Use the `/new-story` slash command
to auto-fill from a one-liner.

---

# <Title — verb-driven, one line, e.g. "Apply staff discount automatically at checkout">

- **Story ID**: <YYYY-MM-DD-kebab-slug> (matches filename)
- **Status**: Draft   <!-- Draft | Ready | In-progress | Done | Dropped -->
- **Owner**: <person>
- **Linked tickets**: <Jira/Linear/issue#>

## Story

> As a **<actor>**
> I want **<capability>**
> so that **<business outcome>**.

Examples:
- *As a logged-in staff customer, I want my staff discount applied
  automatically at checkout so that I don't have to remember a code.*
- *As an admin, I want to bulk-export orders by date range to CSV so
  that I can reconcile with the warehouse system.*

Bad smell: "As a developer I want…" — that's a task, not a user story.

## Why now

What's the trigger? Incident, customer request, regulatory deadline,
strategic bet? One sentence; link to the source if external.

## In scope

What this story does cover. Bullets, not prose.

- <thing 1>
- <thing 2>

## Out of scope

What this story does NOT cover, but is adjacent enough to mention.
Drives out scope creep during review.

- <thing 1 — why deferred>
- <thing 2 — why never>

## Acceptance criteria

Each AC is a single Given/When/Then trio. Tests must be checkable from
the outside (UI, API, observable behaviour).

### AC-1: <one-line summary>

> **Given** <preconditions>
> **When** <action>
> **Then** <observable outcome>

### AC-2: <one-line summary>

> **Given** ...
> **When** ...
> **Then** ...

### Edge cases

- **Given** the discount rule has expired, **when** the customer
  reaches checkout, **then** the discount is NOT applied and a notice
  explains why.
- **Given** the customer is logged out, **when** they reach checkout,
  **then** the system behaves identically to current production.

## Non-functional requirements

If applicable. Skip the heading if nothing applies — don't write
"none" as filler.

- **Latency**: checkout-page TTFB must not regress by >50ms (load test
  baseline is the comparison).
- **Compliance**: discount calculation must be derivable from an audit
  log entry per order (GDPR Art. 30).
- **Backwards compat**: existing `applied_discount` integrations via
  store-api continue to work unchanged.

## Notes

Anything that helps the dev pick up the story but isn't part of the
contract:

- Suggested approach (the dev can override)
- Links to relevant existing code
- Open questions to resolve before "Ready"

## Test plan

How will we verify the AC? Cross-reference to `tests/` directory once
the test files exist.

- [ ] Integration test for AC-1: `tests/integration/Discount/StaffDiscountTest.php`
- [ ] Playwright test for the checkout flow: `tests/e2e/tests/checkout-staff-discount.spec.ts`
- [ ] Manual click-through on staging post-deploy

## Definition of done

- [ ] All AC verified by automated tests
- [ ] PR reviewed by <CODEOWNER for the touched paths>
- [ ] `make audit-shopware` clean
- [ ] CHANGELOG entry merged (via release-please, automatic if commits
      use `feat:` / `fix:` prefix)
- [ ] Story `Status` flipped to `Done` in this file
