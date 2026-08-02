# Type reference with examples

Each type below shows when to use it and 2-3 realistic examples drawn from real codebases.

## `feat`

A new capability the user (caller, end-user, API consumer) can now do that they couldn't before. Drives a MINOR SemVer bump.

```
feat: add password reset via email
```

```
feat(cli): support reading config from stdin
```

```
feat(parser): allow trailing commas in object literals
```

## `fix`

Something was broken; now it works. Drives a PATCH SemVer bump.

```
fix: prevent crash when input is empty
```

```
fix(auth): expire session tokens after 24h instead of 24min
```

```
fix(parser): handle UTF-8 BOM in input files
```

## `docs`

Documentation only — README, docstrings, comments, code samples. No code behavior change.

```
docs: add examples of advanced query syntax
```

```
docs(api): document rate limit response headers
```

```
docs: fix broken link to changelog
```

## `style`

Formatting, whitespace, semicolons, import order. **No logic change.** If a linter or formatter could have produced the diff, it's `style`.

```
style: run prettier on entire codebase
```

```
style(parser): align switch case bodies
```

## `refactor`

Restructuring code without changing behavior. Renamed internals, extracted helpers, simplified branching — but the public interface and observable behavior are unchanged.

```
refactor: extract retry logic into separate function
```

```
refactor(auth): consolidate duplicate token-parsing code
```

```
refactor(parser): replace recursive descent with iterative loop
```

## `perf`

Same behavior, but faster or lighter. Drives a PATCH SemVer bump (it's an observable improvement, though not a bug fix).

```
perf: cache compiled regex patterns
```

```
perf(parser): avoid string allocation in hot path
```

## `test`

Adding new tests, fixing existing tests, or improving test infrastructure. **No production code change.** If you changed production code to make a test pass, that change is `feat`/`fix`/`refactor` — not `test`.

```
test: add coverage for edge cases in date parser
```

```
test(auth): cover session expiration paths
```

## `build`

Changes to the build system, package manager, or dependencies. `package.json`, `Cargo.toml`, `Dockerfile`, `Makefile`, dependency bumps.

```
build: upgrade typescript to 5.3
```

```
build(deps): bump axios from 1.4.0 to 1.6.2
```

```
build: switch from webpack to vite
```

## `ci`

CI configuration and scripts. `.github/workflows`, `.circleci/`, GitLab CI config.

```
ci: cache node_modules between runs
```

```
ci(github): run tests on Windows in addition to Linux
```

## `chore`

Routine maintenance that doesn't fit anywhere else. `.gitignore` updates, file moves with no other effect, version bumps in non-package files.

Avoid `chore` as a dumping ground — if a change has a more specific type, use that.

```
chore: add .DS_Store to .gitignore
```

```
chore: bump VERSION file to 2.1.0
```

## `revert`

Reverting an earlier commit. The body should reference the SHA(s) being reverted and explain why.

```
revert: feat(api): add experimental graph endpoint

The endpoint caused N+1 queries under load. Reverting until we have a
batched implementation.

Refs: 8a3f2c1
```

## Breaking-change variants

Any type can be breaking. Append `!` before the colon, and/or add a `BREAKING CHANGE:` footer.

```
feat!: drop support for Node 14

BREAKING CHANGE: Minimum supported Node version is now 16.
```

```
refactor(api)!: rename `getUser` to `fetchUser`

BREAKING CHANGE: `getUser` is removed. Use `fetchUser` instead — same
signature, same return type.
```

```
build!: bump major version of database driver

BREAKING CHANGE: The new driver no longer supports SSL3. Connections
configured with SSL3 will fail to connect.
```
