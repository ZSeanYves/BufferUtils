# BufferUtils Release Procedure

Publishing is maintainer-only. Repository workflows have read-only contents
permission and must never call `moon publish`, create tags, or create GitHub
Releases.

## Toolchains

- MoonBit: latest formal/nightly toolchain installed by the CI run; record
  `moon version --all` in every validation and performance artifact.
- Rust comparison: Rust 1.97.1 with locked `bytes` 1.12.1 and Tokio 1.53.1.

The published package must support the current `moon.mod` and pass `moon doc`
with the same toolchain policy used by the matching CI run.

## RC review

Start from a clean commit. Confirm that `moon.mod`, both README files,
`CHANGELOG.md`, [MIGRATION.md](MIGRATION.md), and this document use the same
candidate version.

Run:

```bash
scripts/prepublish_check 0.40.0-rc.2
```

The command covers formatting, generated interfaces, strict checks, tests,
docs, examples, API surface, and critical contracts. Sanitizer, coverage,
performance, and platform evidence must come from the matching GitHub Actions
commit rather than a local substitute.

The candidate must also have:

- Two consecutive complete CI runs with every required job green.
- No open P0/P1 issue.
- Complete benchmark artifacts and profiler evidence.
- Consumer installation and execution on Linux, macOS, and Windows.

## Manual publication

After human review, the maintainer may run `moon publish` interactively. Record
the registry response and immutable source commit in the release issue. Do not
change CI to automate this step.

## Consumer verification

Dispatch `.github/workflows/consumer-install.yml` with the exact published
version. Each operating-system job must create a clean external consumer,
install `ZSeanYves/bufferutils@<version>`, compile synchronous, asynchronous,
and native examples, run tests, and execute the native binary.

The same check can be run locally after publication:

```bash
scripts/verify_consumer_install 0.40.0
```

Any source change after consumer verification requires a new candidate and a
new complete evidence set.

## Final acceptance

The release remains pre-1.0 and does not promise 1.0 compatibility. Tagging,
GitHub Release creation, and final registry publication remain explicit manual
maintainer actions after this checklist passes.

