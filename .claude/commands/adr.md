---
description: Create an Architecture Decision Record for a non-trivial design choice.
argument-hint: "<short decision title>"
---

# /adr

Create a new ADR following the project template at
[`docs/decision-records/0000-template.md`](../../docs/decision-records/0000-template.md).

## When to write an ADR

- Choice between two or more credible options (NOT obvious decisions)
- Choice that will be expensive to reverse (DB schema, API contract,
  deployment topology, dependency lock-in)
- Choice that breaks an established project convention — even with good
  reason, write it down

Don't write an ADR for:
- "Renamed a variable" — that's a commit
- "Added a button" — that's a story
- "Picked the obvious library" — write it only if you ALSO had a credible
  alternative

## Process

1. **Find the next ADR number** — scan `docs/decision-records/` for the
   highest 4-digit prefix, add 1. ADR numbers are immutable once
   accepted.
2. **Probe for the missing context** — ask up to 3 targeted questions:
   - "What problem does this solve that 'do nothing' wouldn't?"
   - "What alternatives did you actually consider?"
   - "What will be expensive to change if we're wrong?"
3. **Status defaults to `Proposed`** — only the team can flip to
   `Accepted` after review. NEVER write `Accepted` on first save.
4. **Consequences section is mandatory** — both positive AND negative.
   "It will be faster" is not a consequence; "it locks us into vendor X
   for caching" is.
5. **Cross-reference** — if the ADR replaces an earlier one, add a
   `Supersedes` line to the new ADR AND update the old one with a
   `Superseded by ADR-NNNN` line.
6. **Save to `docs/decision-records/<NNNN>-<kebab-slug>.md`**.

Argument: `$ARGUMENTS` — treat as the decision title.
