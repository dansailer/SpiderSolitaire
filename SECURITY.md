# Security policy

Please report security problems privately, not in a public issue.

Use GitHub's private vulnerability reporting: open the repository's **Security** tab and choose
**Report a vulnerability** (https://github.com/dansailer/SpiderSolitaire/security/advisories/new).
Include what you found, how to reproduce it, and the version (Spider Solitaire ▸ About).

Only the latest release is supported. The app runs offline except for the optional update check,
which reads GitHub's public "latest release" API without any account or token.

## CI

Workflows use `pull_request`, never `pull_request_target`, so pull request runs get a read-only token
and no secrets. The checks run for the maintainer's branches and for Dependabot's pull requests
(recognised by the pull request author, not the spoofable actor); fork pull requests are skipped and
need approval before any workflow runs. Release signing secrets live in the `release` environment,
which only `v*` tags can use.
