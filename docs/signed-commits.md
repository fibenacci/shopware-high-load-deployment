# Signed commits

This template enforces **signed commits** on every PR. The enforcement
sits at three layers, each catching a different failure mode:

| Layer | Where | What it catches |
| --- | --- | --- |
| **Local pre-commit hook** | `.githooks/pre-commit` | Devs forgetting `commit.gpgsign=true` before they write a single commit |
| **CI signature verification** | `.github/workflows/verify-signatures.yml` | Anyone who bypasses the local hook (`--no-verify`) or pushes from an unconfigured machine |
| **Branch protection** | GitHub UI (one-time setup) | Force-push / direct push to `main` |

You need all three. The local hook is the fastest feedback; CI is the
unbypassable gate; branch protection makes it stick on main.

## What signed commits actually prove

A signed commit cryptographically binds the author identity to the
content. Without it:

- "did Alice really write this?" → no, an attacker who stole Alice's
  laptop could have pushed under her email
- "did this `chore: bump dependency` commit really come from the dev?" →
  no, a compromised CI runner could have inserted it during a PR

Signing turns commits from "best-effort attribution" into **non-repudiable
authorship**. Combined with branch protection on `main`, it means the
production-deployable history is provably author-attested.

## One-time developer setup

Two options. **SSH signing is easier** if you already have an SSH key
registered with GitHub for auth.

### Option A: SSH signing (recommended)

```bash
# 1. Tell git you want SSH signatures.
git config --global gpg.format ssh
git config --global commit.gpgsign true
git config --global user.signingkey ~/.ssh/id_ed25519.pub

# 2. Verify it works.
git commit --allow-empty -m "test: verify signing"
git log --show-signature -1
# → "Good "git" signature for ... with ED25519 key ..."

# 3. Register the SAME key for signing on GitHub:
#    Settings → SSH and GPG keys → New SSH key
#      Title:    laptop signing key
#      Key type: Signing Key      ← NOT "Authentication Key"
#      Key:     <paste contents of ~/.ssh/id_ed25519.pub>
```

GitHub will then display a `Verified` badge next to your commits.

### Option B: GPG signing

```bash
# 1. Generate a key (skip if you already have one).
gpg --full-generate-key
# → choose: (1) RSA and RSA, 4096 bits, expire after 2y

# 2. Find your key ID + export the public key.
gpg --list-secret-keys --keyid-format=long
# → look for "sec   rsa4096/<KEYID>"
gpg --armor --export <KEYID>

# 3. Configure git.
git config --global user.signingkey <KEYID>
git config --global commit.gpgsign true
git config --global gpg.format openpgp

# 4. Register the public key on GitHub:
#    Settings → SSH and GPG keys → New GPG key → paste the armored export.
```

macOS: `gpg-agent` works out of the box if you install via `brew install gnupg`.
Add to your shell rc:

```bash
export GPG_TTY=$(tty)
```

## Verifying it works

```bash
# Make a test commit.
git commit --allow-empty -m "test: verify signing"

# Inspect locally.
git log --show-signature -1

# Push and check on GitHub — the commit should show a "Verified" badge.
git push
```

If anything goes sideways, the pre-commit hook gives diagnostic output:

```
✗ commit signing is not enabled.
  Quick fix:
    git config --global commit.gpgsign true
  See docs/signed-commits.md for full GPG / SSH setup.
```

## Branch protection (one-time admin setup)

GitHub-side, can't be configured from this repo:

```
Settings → Branches → Add rule
   Branch name pattern:   main
   ☑ Require a pull request before merging
   ☑ Require signed commits
   ☑ Require status checks to pass:
        - Verify commit signatures
        - CI (the aggregate gate)
   ☑ Require linear history          (recommended — no merge commits)
   ☑ Restrict who can push to matching branches
   ☑ Do not allow bypassing the above settings (incl. for admins)
```

`Require signed commits` is GitHub-native and runs *in addition* to our
verify-signatures workflow. The workflow gives better error messages;
the GitHub-native setting is the belt-and-suspenders fallback.

## Skipping in legitimate cases

Three commits you DO want unsigned:

- **Bot commits** (Renovate, Dependabot, release-please): GitHub
  auto-signs these with the GitHub Actions / app key. Already verified.
- **GitHub web edits**: GitHub signs these server-side. Already verified.
- **`git revert`** of an already-merged commit: signs cleanly if the
  reverter is configured.

If you legitimately need to push an unsigned commit (e.g. emergency
hotfix from a machine without your signing key), the only path is to
temporarily disable branch protection — which leaves an audit log entry
that future-you can answer for.

## Rotating signing keys

| Trigger | Action |
| --- | --- |
| Laptop replaced | Generate new key, register on GitHub, update `user.signingkey`. Old commits stay valid (key is preserved). |
| Suspected compromise | Revoke the key on GitHub (`Settings → SSH and GPG keys`), generate new, update config. Commits made with the compromised key remain in history but lose their `Verified` badge — that's the signal. |
| Key expiry (GPG only) | Renew before expiry (`gpg --edit-key <ID>` → `expire`). Push the renewed pubkey to GitHub. |

## Related

- [`docs/secrets.md`](./secrets.md) — rotation cadence including signing keys
- [`docs/security.md`](./security.md) — full security model
- [`.githooks/pre-commit`](../.githooks/pre-commit) — local gate
- [`.github/workflows/verify-signatures.yml`](../.github/workflows/verify-signatures.yml) — CI gate
