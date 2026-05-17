# Documentation conventions

How we keep `docs/` from rotting into a junk drawer. Read this once,
then `/new-story` and `/adr` make it automatic.

## Where things live

```
docs/
├── README.md                  ← THE index. Every new doc gets a row here.
├── conventions.md             ← This file.
├── <topic>.md                 ← Operational + reference docs. Flat by design.
├── decision-records/
│   ├── README.md
│   ├── 0000-template.md       ← Copy this for new ADRs (use /adr)
│   └── NNNN-slug.md           ← One ADR per architectural choice
└── stories/
    └── YYYY-MM-DD-slug.md     ← One user story per file (use /new-story)
```

The flat layout in `docs/` is deliberate. We tried mental-grouping in
subdirectories and the cross-reference churn (50+ links to rewrite per
move) wasn't worth it. The README index groups them logically; the
filesystem stays a clean alphabetical list.

## Three categories, three lifecycles

| Category | Examples | When to add | When to remove |
| --- | --- | --- | --- |
| **Reference** | `architecture.md`, `caching.md`, `database.md`, `secrets.md`, `signed-commits.md` | New stable capability lands in the template | The capability is removed |
| **Decision records** | `decision-records/0001-deployment-modes.md` | Choice with multiple credible options, expensive to reverse | Never — supersede instead |
| **Stories** | `stories/2026-05-16-staff-discount.md` | A piece of work is starting | When the work ships (status → `Done`); don't delete |

`ideas.md` is the **non-committed-to** backlog — entries can be deleted
when dropped, or moved out as decision records when accepted.

## Filename conventions

- **kebab-case**, lowercase: `caching.md`, not `Caching.md` or
  `http_caching.md`
- **Topic-first**, not adjective-first: `monitoring.md` not
  `complete-monitoring-guide.md`
- **No version numbers** in reference docs — they rot. Use semantic
  names that survive a rewrite (`deployment.md`, not `deployment-v2.md`)
- **ADRs use `NNNN-` prefix** — 4 digits, immutable once accepted
- **Stories use `YYYY-MM-DD-` prefix** — so chronological sort works

## Linking conventions

Use **relative paths with the `.md` extension** so links work both in
the GitHub source view AND in the rendered wiki (the wiki-sync workflow
rewrites `.md` → wiki URLs at publish time):

```markdown
✓ See [`docs/secrets.md`](./docs/secrets.md)        ← from repo root
✓ See [`caching.md`](./caching.md)                  ← from within docs/
✓ See [`../README.md`](../README.md)                ← from a subdir
✗ See [secrets](secrets)                            ← wiki-style — breaks in source view
✗ See [secrets](/docs/secrets.md)                   ← absolute — breaks on the wiki
✗ See [link](http://github.com/.../docs/...)        ← never — moves with the repo
```

## Headers + structure

- **One `# H1` per file** — matches the filename topic
- **`##` for top-level sections**, `###` for sub-sections, `####`
  rarely. If you reach `#####`, refactor.
- **Sentence case in headers**, not Title Case: `## What you have now`,
  not `## What You Have Now`
- **TOC**: don't write one manually. The wiki sidebar provides
  navigation; GitHub renders headings as anchors automatically.

## Cross-references

Every reference doc that names a concrete file should link it. Examples
of what we do well today:

```markdown
✓ Implementation: [`Makefile`](../../Makefile) (`deploy:` target)
✓ See [`k8s/base/configmap.yaml`](../k8s/base/configmap.yaml) for the schema.
✓ > 📖 [Shopware reverse HTTP cache](https://developer.shopware.com/.../reverse-http-cache.html)
```

The `> 📖` block-quote is our convention for **upstream Shopware
references**. Use it consistently — readers learn to scan for it.

## Adding a new doc

1. Pick a name following the conventions above.
2. Write the file under `docs/`.
3. **Add a row to [`docs/README.md`](./README.md)** — the index. If you
   skip this, the doc effectively doesn't exist (the wiki sync ignores
   anything not in the index? No, it syncs all of them — but humans
   navigating won't find it).
4. **If the doc replaces an existing one**: add a note at the top of
   the old doc pointing at the new one, and supersede via ADR if the
   change was architectural.
5. **Cross-reference from related docs** — at least one inbound link.
   Orphan docs rot the fastest.

## How docs surface to the team

Two views, same source:

| View | Audience | Best for |
| --- | --- | --- |
| **GitHub source** (`docs/` in the repo) | Devs working in the codebase | Editing, PR review, IDE navigation |
| **GitHub Wiki** | Anyone in the org with repo access | Reading, searching, sharing links |

The wiki is **auto-published** from `docs/` on every push to `main` via
[`.github/workflows/wiki-sync.yml`](../.github/workflows/wiki-sync.yml).
**Never edit the wiki directly** — the next push overwrites it. Edit
`docs/` and let CI publish.

### How the sync handles structure

| In `docs/` | On the wiki |
| --- | --- |
| `README.md` | `Home` page |
| `caching.md` | `caching` page |
| `decision-records/0001-deployment-modes.md` | `decision-records-0001-deployment-modes` page |
| `stories/YYYY-MM-DD-slug.md` | (not synced — stories stay in the source tree) |

The sidebar is generated from `docs/README.md`'s structure
automatically — you don't write `_Sidebar.md` by hand.

## Tone

- **Write for the next-engineer-on-call at 3am**, not for an audit
  trail. "Here's what to do" beats "It must be noted that…".
- **Concrete over abstract.** "Set `commit.gpgsign=true`" not "Enable
  commit signing as appropriate to your environment".
- **Honest about what's NOT done.** If something is theoretical or
  not-yet-implemented, say so explicitly. We have `docs/ideas.md` for
  that and section headers like "What is NOT solved by this".
- **No marketing voice.** Avoid "seamless", "robust", "enterprise-grade".
  Describe behaviour instead.

## When to refactor docs

Refactor (split, merge, rewrite) a doc when:

- More than 3 PRs in a quarter have to touch the same doc to update
  contradictory facts → it's covering too many topics, split.
- The doc is < 30 lines and the topic is fully covered by a section in
  another doc → merge.
- A new architectural decision invalidates an entire section → write an
  ADR superseding the old one, then update the doc to reference the ADR.

Don't refactor for style. The bar is "the doc is misleading future
readers", not "I would have organised this differently".

## Tools

- **`/new-story`** in Claude Code — scaffolds a story file with the
  template applied
- **`/adr`** in Claude Code — scaffolds an ADR with auto-incrementing
  number
- **VS Code "Markdown All in One"** extension — table-of-contents
  generation, list autoformatting

## When in doubt

The [`README.md`](./README.md) is the index, this file
([`conventions.md`](./conventions.md)) is the process.
[`onboarding.md`](./onboarding.md) is the human-first-day path.
Everything else is reference.
