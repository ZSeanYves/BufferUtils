# BufferUtils 0.40 Release Procedure

Publishing is intentionally a maintainer-only action. Repository workflows
have read-only contents permission and do not call `moon publish`, create tags,
or create GitHub releases.

## 1. Review a release candidate

Start from a clean commit whose normal CI run is fully green. Confirm that the
manifest, README files, changelog and migration guide all name the intended
version, then run:

```bash
scripts/prepublish_check 0.40.0-rc.1
```

The script runs formatting, generated-interface, strict check/test, docs, API
surface and critical-contract gates. Sanitizer, coverage and performance
evidence must come from the matching GitHub Actions commit, not a local
substitute.

With the pinned 2026-08-03 Moon CLI, `moon publish --dry-run` can report HTTP
202 and "No changes were made" and still exit non-zero after a successful
server-side dry run. Run it separately and inspect both the packaged archive
validation and the server response; do not weaken normal CI exit-code checks
to accommodate this CLI behavior.

## 2. Publish manually

After review, the maintainer may run `moon publish` interactively. This command
is deliberately absent from all scripts and workflows in this repository.
Record the package registry URL and immutable source commit in the release
issue.

## 3. Verify the published package

Manually dispatch `.github/workflows/consumer-install.yml` with the exact
published version. Each Linux, macOS and Windows job creates a clean external
consumer, installs `ZSeanYves/bufferutils@<version>`, compiles synchronous,
asynchronous and native usage, runs its tests and executes the native binary.

The same check can be run locally after publication:

```bash
scripts/verify_consumer_install 0.40.0-rc.1
```

Do not advance from rc.1 to rc.2, or from rc.2 to 0.40.0, if any consumer job
fails. Changes made after a consumer run require a new candidate version and a
new complete evidence set.

## 4. Final acceptance

The final source commit needs two consecutive all-green CI executions, two
installable RC versions without open P0/P1 issues, and a successful three-OS
consumer run for each candidate. Tagging, GitHub Release creation and final
registry publication remain manual maintainer actions. BufferUtils 0.40 stays
pre-1.0 and does not promise 1.0 compatibility.
