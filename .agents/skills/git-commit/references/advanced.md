# Advanced flows: amend, split, squash

## Amending the last commit

Use `git commit --amend` only when:

1. The commit is the most recent one (`HEAD`), AND
2. It hasn't been pushed, OR the user has explicitly accepted that the next push will need `--force-with-lease` and they're the only one with the branch.

If both hold, the workflow is:

```bash
# Stage the additional changes (if any)
git add <paths>

# Amend. To keep the same message:
git commit --amend --no-edit

# Or to rewrite the message:
git commit --amend -m "$(cat <<'EOF'
feat(parser): support trailing commas in object literals

Now also handles trailing commas in array literals.

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
)"
```

If the commit is already pushed and shared, **don't amend** — make a new commit instead. The clean history isn't worth the merge headache for collaborators.

When rewriting the message during an amend, re-derive type/scope/description from the *current* diff (which may now include the new staged changes), not from the old message.

## Splitting multi-purpose changes

Symptom: the staged diff covers more than one logical change and you'd need "and" to describe it (`feat: add login and fix unrelated typo`). Each piece deserves its own commit.

Workflow when nothing is committed yet:

```bash
# Step 1 — un-stage everything so you can stage piecemeal
git reset

# Step 2 — stage the first logical group
git add path/to/auth/changes
git diff --staged   # confirm only that group is included

# Step 3 — commit with a conventional message for that group
git commit -m "feat(auth): add login endpoint"

# Step 4 — repeat for each remaining group
git add path/to/docs/changes
git commit -m "docs: fix typo in setup guide"
```

If two changes are in the *same file* and can't be staged independently by path, use `git add -p` (interactive hunk staging) to pick individual hunks.

When asked to split, propose the split (which files/hunks go into which commit, with the proposed message for each) and confirm with the user before running anything destructive.

## Squashing into one conventional commit

Squashing N commits into one: the resulting message should describe the **net change**, not concatenate per-commit messages.

Workflow:

```bash
# See what you're squashing
git log --oneline -N origin/main..HEAD

# Squash via interactive rebase or reset+recommit
git reset --soft origin/main
git diff --staged   # this is the net change you're committing

# Now derive type/scope/description from this net diff, ignoring the
# intermediate commits' types. A series of `fix` commits during PR
# review that together add a new feature should squash to `feat`.
git commit -m "$(cat <<'EOF'
feat(auth): add password reset via email

Includes the endpoint, email template, rate-limiting middleware,
and integration tests.

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
)"
```

For squash-merges done via the GitHub/GitLab UI, write the same kind of message in the PR's squash dialog — type derived from net effect, body covering what was done, footers for issue refs.

## Choosing type when squashing mixed commits

If the squashed commits include both `feat` and `fix` work in service of one feature, use `feat` — the net change is a new capability.

If they include both `feat` and `refactor`, use `feat` for the same reason.

If they're all `fix` commits for one underlying bug, use `fix`.

If the squashed series genuinely contains independent changes that shouldn't share a commit, push back: suggest cherry-picking or splitting before merge instead of squashing them together. A single commit with type `chore: misc changes` defeats the purpose of conventional commits.

## Reverting

`git revert <sha>` creates a new commit that undoes the target. The auto-generated message starts with `Revert "..."`. Rewrite it to follow conventional commits:

```
revert: feat(api): add experimental graph endpoint

The endpoint caused N+1 queries under load. Reverting until we have a
batched implementation.

Refs: 8a3f2c1
```

Body should say *why* the revert is necessary and reference the reverted SHA(s) in a `Refs:` footer.
