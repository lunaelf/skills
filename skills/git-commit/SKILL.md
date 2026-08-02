---
name: git-commit
description: Write git commit messages and run commits following the Conventional Commits v1.0.0 spec. Use whenever the user wants to commit changes, asks for a commit message, says "commit this", "make a commit", "write a commit message", or mentions amending, squashing, or splitting commits — even if they don't explicitly say "conventional commits". Also use when reviewing or rewriting an existing commit message for conformance.
---

# Conventional Git Commits

Produce commit messages that conform to [Conventional Commits v1.0.0](https://www.conventionalcommits.org/en/v1.0.0/) and drive the actual `git` operations to create, amend, split, or squash commits.

## Why this matters

A conventional commit message is a *machine-readable* statement of intent: the type drives SemVer bumps and changelogs, the scope tells reviewers which subsystem moved, and the description tells a future engineer what changed without reading the diff. The format isn't ceremony — each piece earns its keep. Skipping the type or stuffing two unrelated changes into one commit breaks downstream tooling silently.

## The format

```
<type>[(scope)][!]: <description>

[optional body]

[optional footer(s)]
```

- **type** — required. One of the [types](#types) below.
- **scope** — optional noun in parens identifying the affected area (`feat(parser):`, `fix(api):`).
- **`!`** — optional. Appended right before the colon to signal a breaking change (`feat!:`, `feat(api)!:`).
- **description** — required. Short summary, imperative mood, lowercase, no trailing period. Aim for ≤72 chars on the subject line.
- **body** — optional. One blank line after the description. Explains *why* and any context the diff doesn't make obvious. Wrap around 72 chars.
- **footers** — optional. One blank line after the body. Git-trailer format: `Token: value` or `Token #value`. Tokens use `-` for spaces (e.g., `Reviewed-by`, `Refs`), except `BREAKING CHANGE` which stays uppercase with a space.

## Types

Use these from the Angular convention (also see [references/types.md](references/types.md) for examples per type):

| Type       | Use for                                                                     | SemVer  |
|------------|-----------------------------------------------------------------------------|---------|
| `feat`     | A new user-visible feature                                                  | MINOR   |
| `fix`      | A bug fix                                                                   | PATCH   |
| `docs`     | Documentation only                                                          | —       |
| `style`    | Formatting, whitespace, semicolons — no logic change                        | —       |
| `refactor` | Code change that neither fixes a bug nor adds a feature                     | —       |
| `perf`     | Performance improvement                                                     | PATCH   |
| `test`     | Adding or correcting tests                                                  | —       |
| `build`    | Build system, package manager, or dependencies (`npm`, `pip`, `Makefile`)   | —       |
| `ci`       | CI configuration and scripts (`.github/workflows`, `circleci`)              | —       |
| `chore`    | Routine maintenance that doesn't fit anywhere else                          | —       |
| `revert`   | Reverting a previous commit (body should reference the SHA(s))              | —       |

Any of these become `MAJOR` if marked breaking.

When two types could fit, pick the one matching the **user-visible effect**: a refactor that ships a new capability is `feat`; a perf change that fixes a bug is `fix`.

## Workflow

### 1. Understand the change before writing anything

Run these in parallel and read the output before drafting:

```bash
git status
git diff --staged    # if anything is staged
git diff             # to see unstaged work
git log -5 --oneline # to confirm we're on a real branch with history
```

Three branches:

- **Something is staged** — work with that. Mention if there are also unstaged changes the user may want to include.
- **Nothing staged, but there are unstaged changes** — ask which files to stage, or confirm "stage everything". Don't `git add -A` silently; it can sweep in `.env`, build artifacts, or notes the user didn't mean to commit. Prefer explicit paths.
- **Nothing to commit** — say so and stop.

### 2. Check for multi-purpose changes

If the diff naturally splits into more than one type — e.g., a bug fix in `auth/` plus an unrelated docs update in `README.md` — surface that and offer to split. The spec recommends one logical change per commit because each conventional commit drives one SemVer decision.

Heuristic: if you find yourself writing a description with " and " joining two distinct subjects, it's two commits. See [references/advanced.md](references/advanced.md#splitting-multi-purpose-changes) for the splitting workflow.

Don't be pedantic. A `feat` plus the tests that exercise it is one commit, not two. The test is whether the changes share a purpose.

### 3. Pick the type

Walk the diff and ask: what's the user-visible effect?

- New capability the user can now invoke → `feat`
- Something that was broken now works → `fix`
- README, docstrings, comments only → `docs`
- Indentation, semicolons, import order, no behavior change → `style`
- Renamed internals, extracted helpers, same external behavior → `refactor`
- Same behavior but faster or lighter → `perf`
- Added/edited tests, no production code change → `test`
- `package.json`, `Cargo.toml`, `Dockerfile`, build scripts → `build`
- `.github/workflows`, CI config → `ci`
- Catch-all maintenance (bumping `.gitignore`, renaming a file with no other effect) → `chore`

If genuinely uncertain between two, prefer the one with the larger SemVer impact (`feat` over `refactor`, `fix` over `chore`) — it's more honest about what shipped.

### 4. Decide on a scope (optional)

A scope is a noun naming the affected subsystem: `feat(auth):`, `fix(parser):`, `docs(readme):`. Use one when:

- The repo has natural subsystems (packages, modules, services) and the change is clearly inside one.
- The same type appears often and scopes help readers skim history.

Skip the scope when:

- The change touches many subsystems with no clear primary.
- The repo is small enough that scopes are noise.

Don't invent a scope to look thorough. Empty parens or a vague scope like `(misc)` is worse than no scope.

### 5. Write the description

- **Imperative mood**: "add", "fix", "remove" — not "added" or "adds". Read it as completing the sentence *"If applied, this commit will ___"*.
- **Lowercase** the first word (style choice, but consistent with the Angular convention and most tooling).
- **No trailing period**.
- **Be specific**: `fix: handle empty input in date parser` beats `fix: bug fix`.
- **≤72 chars** on the whole subject line (type + scope + description) so it doesn't truncate in `git log --oneline` or PR titles.

### 6. Add a body if the *why* isn't obvious from the diff

Skip the body for self-evident changes (typo fixes, dependency bumps). Add one when:

- The motivation isn't obvious (a workaround for an external bug, a perf-driven rewrite).
- There's a subtle constraint or tradeoff a reviewer should know.
- You removed something — explain why, since the diff only shows the removal.

Wrap at ~72 chars. Use blank lines between paragraphs. Don't restate what the diff already shows.

### 7. Footers

Add footers (one blank line after the body) for:

- **Breaking changes** — see [breaking changes](#breaking-changes).
- **Issue refs** — `Refs: #123`, `Closes: #123`, `Fixes: #123`.
- **Co-authors** — `Co-Authored-By: Name <email>`. When committing as Claude Code, append `Co-Authored-By: Claude <noreply@anthropic.com>` per the harness convention.
- **Sign-offs** — `Signed-off-by: Name <email>` if the repo uses DCO.

Footer tokens use hyphens for spaces (`Reviewed-by`, `Acked-by`), except `BREAKING CHANGE` which is two uppercase words separated by a space.

### 8. Breaking changes

A commit is breaking if a user of the code (caller, consumer, downstream package) has to change *something* to keep working after the commit. Renamed public APIs, removed CLI flags, changed config schema, dropped support for a runtime — all breaking.

Signal it **either** by appending `!` before the colon, **or** with a `BREAKING CHANGE:` footer, **or both**:

```
feat(api)!: rename `getUser` to `fetchUser`

BREAKING CHANGE: `getUser` is removed. Call sites should switch to `fetchUser`,
which has the same signature.
```

The `!` alone is enough for the spec, but the footer is friendlier because it gives downstream readers the migration path. For non-trivial breaks, include both. The token can also be written `BREAKING-CHANGE:` — they're synonymous.

### 9. Confirm, then commit

Show the user the proposed message and which files will be staged before running anything. They may want to tweak wording, change scope, or stage different files.

Use a heredoc so multi-line bodies and footers come through intact:

```bash
git commit -m "$(cat <<'EOF'
feat(parser): support trailing commas in object literals

Trailing commas were previously rejected with a parse error. They're now
accepted to match the JavaScript spec.

Refs: #482
Co-Authored-By: Claude <noreply@anthropic.com>
EOF
)"
```

Single-quoted heredoc (`<<'EOF'`) so backticks and `$` in the message aren't interpreted by the shell.

After committing, run `git status` to confirm the working tree is in the expected state.

## Amending, splitting, squashing

For amending the last commit, splitting one diff into several commits, or squashing a series into one conventional commit, see [references/advanced.md](references/advanced.md).

Key rules:

- **Amend** only the most recent commit and only if it hasn't been pushed (or the user explicitly accepts the force-push). Default to a new commit instead.
- **Split** by un-staging everything, then staging and committing one logical group at a time.
- **Squash** messages should re-derive the type and description from the *net* change, not concatenate the per-commit messages.

## Common mistakes to avoid

- Type after description (`add login: feat`) — the type goes first.
- Capitalised description or trailing period — both are non-standard for Angular tooling.
- Past tense (`fix: fixed parsing bug`) — use imperative ("fix parsing bug").
- Vague description (`fix: bug`, `chore: stuff`) — name what changed.
- Mixing types in one commit (`feat: add login and fix logout`) — split it.
- Marking every change `feat` — most repo work is `fix`, `refactor`, `chore`. Reserve `feat` for actual new user-facing capability.
- `BREAKING CHANGE` in the body instead of a footer — the spec requires it as a footer (or `!` in the prefix).
- Editing a pushed commit with `--amend` and force-pushing without telling collaborators.

## Quick examples

```
fix: handle empty array in median calculation
```

```
feat(cli): add --json flag to output structured results
```

```
docs: clarify install steps for Windows
```

```
refactor(auth): extract token validation into separate module
```

```
feat(api)!: drop support for v1 endpoints

BREAKING CHANGE: All v1 endpoints (`/api/v1/*`) now return 410 Gone.
Clients must migrate to v2. See MIGRATION.md for the mapping.

Refs: #1042
```

```
revert: feat(api): add experimental graph endpoint

The endpoint caused N+1 queries under load. Reverting until we have a
batched implementation.

Refs: 8a3f2c1
```

More examples per type are in [references/types.md](references/types.md).
