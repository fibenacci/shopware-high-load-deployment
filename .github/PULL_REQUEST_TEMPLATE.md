<!--
Reviewers need three things to merge confidently. Help them get there fast.
If a section doesn't apply, write "n/a" — don't delete it. The structure is
the structure.
-->

## What

<!-- One sentence. What does this PR change? -->

## Why

<!-- Why now? What's the trigger — ticket link, incident, user request? -->

## How

<!-- Approach in 3-5 bullets. The tradeoff you picked. What you rejected. -->

-

## Test plan

<!--
What did you actually run? Don't just say "ran tests" — list the commands.
For storefront / admin changes, paste a screenshot or describe the manual
click-through. CI runs unit + integration + Playwright automatically.
-->

- [ ] `make test-unit`
- [ ] `make test-integration`
- [ ] `make e2e` (or rely on CI Playwright)
- [ ] Manual: <describe what you clicked>

## Deployment notes

<!--
Anything operational that can't be derived from the diff:
  - DB migration that needs a maintenance window
  - new ConfigMap / Secret key required
  - cache that must be cleared post-deploy
  - feature-flag toggle order
Leave "n/a" if it's a pure code change.
-->

n/a

## Rollback plan

<!--
If this PR causes prod to misbehave, what's the fastest way back?
  - `make rollback ENV=production` (default)
  - revert + redeploy
  - feature-flag off
  - DB rollback steps if migrations were destructive
-->

`make rollback ENV=production`

## Linked tickets / discussions

<!-- Jira/Linear/issue numbers. Slack threads if relevant. -->

-

<!-- test-results:start -->
<!-- CI fills this block automatically — leave it alone -->
<!-- test-results:end -->
