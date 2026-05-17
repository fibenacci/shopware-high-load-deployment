# ADR-0000: Template — do not edit, copy as 000N-<slug>.md

- **Status**: Proposed   <!-- Proposed | Accepted | Superseded by ADR-NNNN | Deprecated -->
- **Date**: YYYY-MM-DD
- **Decision-makers**: <name(s)>
- **Consulted**: <name(s)>
- **Informed**: <name(s) or @teams>

## Context

What is the problem we're trying to solve? What are the forces at play?
Keep this section honest — if "do nothing" is a real option, say so and
explain why we're considering anything else.

State the problem in business terms, not technical ones. Technical
detail belongs in the **Decision** section.

## Decision drivers

Numbered list of the things that mattered when picking. The order matters
— first item is the most important. Keep to 3-7 drivers; if you have
more, you're describing a project, not a decision.

1. <driver 1>
2. <driver 2>
3. ...

## Considered options

List the options you genuinely considered. **Including "do nothing".**
If you didn't seriously consider an alternative, this isn't an ADR —
it's a how-to.

- **Option A**: <one-line summary>
- **Option B**: <one-line summary>
- **Option C** (do nothing): <one-line summary>

## Decision

Picked: **Option <X>** because <one-sentence reason tying back to driver 1>.

Explain the choice in 2-4 paragraphs. Cover:
- What we're going to do
- What stops being possible (lock-in, dependency, contract)
- What we're explicitly NOT doing (drives out scope creep)

## Consequences

### Positive
- <good thing 1>
- <good thing 2>

### Negative
- <cost 1>
- <cost 2>
- <new risk we're now exposed to>

### Neutral
- <thing that changes but isn't strictly good or bad>

If you can't list any negatives, you haven't thought hard enough.
Every decision costs something.

## Validation

How will we know if this was the right call? When should we revisit?

- **Success signal**: <observable metric or event>
- **Reconsider when**: <trigger condition>
- **Review date**: <YYYY-MM-DD, if applicable>

## Links

- Story / ticket: <link>
- Prior ADR(s) this builds on: <ADR-NNNN: title>
- Supersedes / superseded-by: <ADR-NNNN>
- External references: <link>
