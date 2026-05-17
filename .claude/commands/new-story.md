---
description: Scaffold a user story with INVEST criteria + Given/When/Then acceptance criteria.
argument-hint: "<one-line problem statement>"
---

# /new-story

Create a new user-story file following the project template at
[`docs/user-story-template.md`](../../docs/user-story-template.md).

## Process

1. **Confirm the one-liner** — restate what the user typed so they can
   correct if you misread.
2. **Probe for the missing bits** — the template has 6 sections. Ask up
   to 3 *targeted* questions (not 6) to fill the gaps. Examples:
   - "Who's the actor — anonymous shopper, logged-in customer, admin
     user, integrator?"
   - "What's the trigger — UI click, scheduled job, API call?"
   - "Any non-functional constraints — latency, compliance, audit?"
3. **Apply INVEST**:
   - Independent: Can it ship without other tickets? If no, name the
     dependency.
   - Negotiable: Story is what+why, not how. Move implementation
     details to a "Notes" section.
   - Valuable: Phrase the "Why" as a user/business outcome, not "we
     need a button".
   - Estimable: If you can't sketch the change in 3 bullets, it's too
     big — propose a split.
   - Small: Target 1-3 days of dev. Flag stories > 5 days.
   - Testable: Acceptance criteria must be checkable from the outside.
4. **Write Given/When/Then** for each acceptance criterion, not bullet
   prose. Each AC is one G/W/T trio.
5. **Save to `docs/stories/<YYYY-MM-DD>-<kebab-slug>.md`**.
6. **Echo a one-line summary** + the file path so the user can open it.

Argument: `$ARGUMENTS` — treat as the initial problem statement.
