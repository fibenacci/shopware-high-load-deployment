# Architecture Decision Records (ADRs)

Lightweight records of choices that mattered. Lives forever (numbers are
immutable), even if the choice is later superseded — that's the whole
point. Future-you needs to understand why past-you made a call that
seems strange now.

## When to write one

> Choice between two or more credible options, expensive to reverse, OR
> breaking an established project convention.

If "do nothing" was a real option, that's the smell of an ADR-worthy
decision. If the answer was obvious, just commit it.

## How to write one

```bash
# Use the /adr slash command — it handles numbering + scaffolding.
# Or manually:
cp docs/decision-records/0000-template.md \
   docs/decision-records/000N-my-decision-slug.md
$EDITOR docs/decision-records/000N-my-decision-slug.md
```

## Conventions

- **4-digit prefix, monotonically increasing**. ADR-0007 is forever
  ADR-0007 even if it gets superseded.
- **Status** flips from `Proposed` → `Accepted` after team review (PR
  approval counts). `Superseded by ADR-NNNN` when replaced.
- **No retroactive edits** to `Decision`, `Context`, or `Decision
  drivers` once `Accepted`. Add a new ADR that supersedes it instead.
- **Consequences must include negatives**. If you can't think of any,
  the decision wasn't real.

## Index

- [ADR-0000: Template](./0000-template.md) — copy this for new ADRs
- [ADR-0001: Four deployment modes](./0001-deployment-modes.md) — Accepted
