---
description: Preview the CHANGELOG block release-please will create on the next bump.
---

# /changelog

Show what the next release-please run will write to `CHANGELOG.md`,
without actually opening the release PR. Useful for:

- Knowing what version the next merge to main will trigger
- Sanity-checking that conventional-commit prefixes are landing in the
  right CHANGELOG section
- Catching missing security/breaking-change markers before they ship

## Process

1. **Find the last release tag**:
   ```bash
   git describe --tags --abbrev=0 --match='v*' 2>/dev/null || echo 'v0.0.0'
   ```
2. **Collect commits since that tag**:
   ```bash
   git log <last-tag>..HEAD --pretty=format:'%s ⏎ %b ⏎ %h'
   ```
3. **Bucket by conventional-commit type** following the config in
   `.github/release-please-config.json`:
   - `feat:` → Features (minor bump)
   - `fix:` → Bug Fixes (patch bump)
   - `perf:` → Performance (patch bump)
   - `security:` → Security (patch bump)
   - `deps:` → Dependencies (patch bump)
   - `<type>!:` OR `BREAKING CHANGE:` in body → major bump
   - other types → hidden from CHANGELOG
4. **Compute the next version** from the current version in
   `deployment.config` (`PROJECT_VERSION=`) using the highest bump
   level found.
5. **Render** a markdown preview that mirrors the format release-please
   actually produces, so the user can spot drift.

## Output format

```markdown
# Next release preview

Current version:  0.1.0
Next version:     0.2.0   (minor — found `feat:` commits)
Commits since v0.1.0: 17

## Features
- feat(checkout): apply staff discount automatically (#42, abc1234)
- feat(api): add /store-api/discount endpoint (#43, def5678)

## Bug Fixes
- fix(cart): preserve discount on quantity change (#44, 7890abc)

## Security
- security(login): rate-limit `/account/login` to 5/min (#45, ...)

## Hidden (won't appear in CHANGELOG.md)
- 4 × chore:, 2 × docs:, 1 × ci:

## Commits without conventional prefix (release-please will skip)
- abc1234: WIP fix
- def5678: revert: doh
  → flag these for the author to rewrite or revert
```

## Refuse to do

- **Actually open the release PR** — that's release-please's job on
  push to main. This command is preview-only.
- **Cut a tag manually** — same reason; we don't want competing tag
  sources.
