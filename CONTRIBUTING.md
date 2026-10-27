# Contributing

Thanks for your interest. This is a personal project, and outside contributions (pull requests,
patches) are not accepted. Pull requests from forks will be closed without review, and workflows do
not run for them.

You are welcome to fork it under the terms of the MIT licence. Bug reports are welcome as issues;
security problems go through SECURITY.md instead.

## Development and release cycle (maintainer)

`main` is protected by the `protect-main` ruleset: it cannot be pushed to, force-pushed or deleted,
and changes only arrive through pull requests whose required checks passed on a branch that is up to
date with `main`. No review approval is required (there is one maintainer).

1. **Branch** from an up to date `main`: `feature/<topic>`, `fix/<topic>`, `ci/<topic>` or
   `docs/<topic>`.
2. **Check locally** before pushing: `swift test` and `scripts/lint.sh` (`scripts/lint.sh --fix`
   formats the code and applies SwiftLint's automatic fixes).
3. **Open a pull request** into `main` (`gh pr create`). These checks must pass:
   - `Linux tests`: `swift build` and `swift test` in a pinned Swift container
   - `macOS build and tests`: `swift test` and `scripts/package.sh`
   - `SwiftLint`: `scripts/lint.sh swiftlint` (`.swiftlint.yml`)
   - `swift-format`: `scripts/lint.sh swift-format` (`.swift-format`)
   - `jactionlint`: the workflows and `dependabot.yml`, pedantic profile
4. **Merge** once they are green (`gh pr merge --squash`, or a merge commit or rebase). If `main`
   moved on, update the branch first (`gh pr update-branch`) so the checks run against it.
5. **Release** from `main`: the tag is the version, there is no version file to bump.
   ```bash
   git switch main && git pull --ff-only
   git tag -a v1.2.0 -m "Spider Solitaire 1.2.0"
   git push origin v1.2.0
   ```
   The Release workflow checks that the tag is on `main` (or a `release/x.y` branch), runs the
   tests, builds the universal app and publishes the GitHub release. Tags are never moved or reused;
   a broken release gets a new patch version.

Use semantic versions: a patch (`v1.2.1`) for fixes, a minor version for features, a major version
for breaking changes such as an incompatible save format.

### Patch releases from a release branch (optional)

When `main` already holds unreleased work that should not ship yet, fix an older release on a
`release/x.y` branch instead:

```bash
git switch -c release/1.2 v1.2.0      # once per minor version
git push origin release/1.2
git switch -c fix/<topic> release/1.2 # the fix, as a pull request into release/1.2
```

Tag the patch (`v1.2.1`) on `release/1.2` after the fix is merged there, and bring the fix to `main`
with its own pull request (or a cherry-pick on a branch). The CI workflows check pull requests into
`main`; to require the same checks on release branches, add `refs/heads/release/*` to the
`protect-main` ruleset's conditions and `release/*` to the `pull_request` branches of `ci.yml` and
`jactionlint.yml`.
