# BufferUtils 0.40 Engineering Maintenance Plan

## Objective

Bring the repository to a publishable, maintainable package organized around
shared immutable byte ranges, COW mutable buffers, and composable synchronous
and asynchronous streaming I/O.

This plan covers source, public API, package structure, tests, examples,
documentation, benchmarks, CI, contribution policy, security policy, and
release operations. It is intentionally staged as independent PRs. Every PR
must be reviewable and revertible without reverting unrelated test or CI work.

## Current state

- Source version is `0.40.0-rc.2`.
- `SharedBytes` is an immutable `#valtype`; `BytesCursor` owns consumption.
- `BytesMut::freeze` provides immutable snapshots and COW detachment.
- `io` and `async_io` implement short-progress, EOF, interruption, write-zero,
  cancellation, and recovery contracts.
- The PR-04 implementation CI run [31495616259](https://github.com/ZSeanYves/BufferUtils/actions/runs/31495616259)
  passed all validation, coverage, sanitizer, contract, and performance jobs.
- Coverage was 95.22% overall with each core package above 90%.
- Synchronous shared streaming has additive accumulation, write, buffered
  extraction, adapter, and memory-fixture paths. Asynchronous shared streaming
  now has additive accumulation and write paths while retaining the existing
  Core `Bytes` materialization APIs.
- PR-05 removes diagnostic counters from generated public interfaces and keeps
  call/copy evidence in benchmark or test fixtures. Exact allowlist, naming,
  ownership-boundary, generated-documentation, and test/example evidence gates
  now govern the compatibility surface.
- Documentation has been consolidated under `docs/`; historical changelog
  entries may mention superseded RC documents, but active instructions point
  to the consolidated guides and latest-toolchain policy.
- Each maintained package keeps one canonical `pkg.generated.mbti`; numbered
  and editor-style backups are ignored and rejected by the repository hygiene
  gate.
- Functional packages and executable examples are now under `src/`; the root
  `bench/` directory is reserved for the Rust reference project and benchmark
  data, while MoonBit benchmark entry points live under `src/bench` and
  `src/bench_async`.

## PR-00: Repository hygiene and policy

Scope:

- Keep one canonical generated `pkg.generated.mbti` per package.
- Remove duplicate generated backups and prevent them through `.gitignore`.
- Classify `buffer`, `io`, `async_io`, and `native` as the only compatibility
  packages; keep examples and benchmarks non-core.
- Make latest MoonBit the active CI policy and keep only the Rust reference
  toolchain pinned.
- Remove stale active references to the old pinned MoonBit installer.

Verification:

- Clean tracked worktree.
- `moon info --target all` followed by `scripts/normalize_interfaces`.
- `git diff --exit-code`.

Rollback: revert only repository-policy and generated-file changes; no source
behavior is involved.

## PR-01: Architecture and contract source of truth

Scope:

- Add the ownership, COW, streaming, native-safety, and copy-boundary contracts
  in [ARCHITECTURE.md](ARCHITECTURE.md).
- Build a public-symbol allowlist from generated interfaces.
- Record every borrowed view, explicit materialization point, and external
  resource lifetime.

Verification:

- Documentation review finds one canonical statement for each contract.
- No public API or generated interface changes.

Rollback: documentation-only revert.

## PR-02: Core ownership model

Scope:

- Refine `src/buffer/shared_bytes.mbt`, `src/buffer/bytes_mut.mbt`, and
  `src/buffer/bytes_cursor.mbt` around a single internal backing/COW operation.
- Keep `SharedBytes` immutable and `BytesCursor` consumptive.
- Move benchmark-only copied-byte accounting out of the release representation
  if latest MoonBit conditional compilation supports it without ambiguity.
- Do not expose backing identity, uniqueness, refcounts, or detach state.

Verification:

- Empty, full-range, nested-range, split, cursor, alias, and COW tests.
- Generated interface diff contains only intentional public changes.
- ASan/UBSan/TSan remain clean for shared backing and freeze mutation.

Rollback: revert the core representation PR as one commit group.

## PR-03: Synchronous shared streaming

Scope:

- Add an ownership-preserving accumulation path such as
  `read_to_shared_bytes` while retaining the existing materializing API.
- Add `write_shared`/`write_all_shared` only after measuring the safe
  `BytesView` or `SharedBytes` boundary.
- Update `BufReader`, `BufWriter`, adapters, and memory fixtures to preserve
  shared ranges where no copy is required.
- Keep `Read` and `Write` required methods stable unless a measured, documented
  contract improvement justifies a later breaking PR.

Verification:

- Copy-evidence tests prove the difference between shared and materialized
  paths.
- Short read/write, interruption, EOF, WriteZero, flush recovery, and seek
  tests remain green.
- Benchmark compares shared and materialized paths separately.

Rollback: additive APIs can be removed without changing existing trait users.

## PR-04: Asynchronous shared streaming

Scope:

- Add a shared-byte result path alongside async `read_to_end`.
- Determine whether `SharedBytes` can safely cross an async await boundary.
- Add shared async write only if the lifetime contract is expressible and
  tested; otherwise retain owned `Bytes` as an explicit async materialization
  boundary.
- Preserve one cancellation-protected read chunk, short-write recovery,
  shutdown failure, pending behavior, and progress accounting.

Verification:

- Ready, pending, cancellation-after-read, cancellation-during-short-write,
  shutdown failure, EOF, and data-loss tests.
- Separate microbenchmarks for buffer copy, await count, and scheduler cost.
- No borrowed `BytesView` survives across an await.

Rollback: keep existing async `Bytes` APIs and remove only the additive shared
path if the language lifetime gate fails.

## PR-05: Public surface and package governance

Scope:

- Convert `scripts/check_api_surface` into a strict allowlist plus intentional
  diff report.
- Keep `copied_bytes`, underlying-call, and syscall evidence in benchmark-only
  fixtures or generated diagnostics; none is part of the permanent public API.
- Require documentation and a test/example for every public symbol.
- Audit all names against the rules in [ARCHITECTURE.md](ARCHITECTURE.md).
- Keep native mmap and socket types visibly separate from shared byte values.

Verification:

- `moon info --target all` is the only generated-interface update source.
- `moon doc --frozen` generates documentation for every public symbol.
- Public API review records every intentional breaking or additive change.

Rollback: restore an individual public symbol only with a migration note and
an explicit decision record.

## PR-06: Tests and performance evidence

Scope:

- Organize tests by ownership, I/O contract, async control, native safety,
  examples, and model/state behavior.
- Keep benchmark-only instrumentation outside release paths.
- Preserve three calibrated batches, raw samples, MAD/CV/p95, copied bytes,
  underlying calls, syscalls, RSS, and profiler artifacts.
- Never rebuild all baselines to hide a regression; update only explicitly
  evidenced cases.

Verification:

- Overall coverage at least 95%; each core package at least 90%.
- ASan, UBSan, and TSan pass.
- Corrected MoonBit/Rust cases pass the structural and regression gates.
- Every remaining non-parity case has leaf-level profiler evidence.

Rollback: benchmark changes can be reverted without changing library APIs.

## PR-07: Documentation, examples, and changelog

Scope:

- Rewrite README and Chinese README around the core positioning.
- Keep [MIGRATION.md](MIGRATION.md) as the single migration document.
- Keep measured results and limitations in [PERFORMANCE.md](PERFORMANCE.md).
- Add one complete shared-buffer-to-stream example and keep each existing
  example focused on one capability.
- Update `CHANGELOG.md`, `CONTRIBUTING.md`, `SECURITY.md`, and release wording
  to the same version and latest-toolchain policy.

Verification:

- No stale rc.1, pinned-MoonBit, or contradictory performance claims remain.
- Every example compiles and runs on its declared target.
- All documentation links resolve.

Rollback: documentation can be reverted independently of source changes.

## PR-08: Release hardening

Scope:

- Split validation, contracts, sanitizers, coverage, performance, and consumer
  checks into clear CI responsibilities.
- Add concurrency cancellation, minimal permissions, artifact naming, and
  protected-branch required checks.
- Update the release script and document the exact current RC version.
- Run two complete all-green CI executions.
- Run clean consumer installation on Linux, macOS, and Windows for each RC.

The repository must not publish, create tags, or create Releases automatically.
Manual maintainer publication remains a separate action after review.

## Final release gate

The final candidate is publishable only when the following are all true:

- Worktree contains no untracked generated or temporary artifacts.
- Manifest, README files, changelog, migration, and release procedure agree on
  the same version.
- Formatting, generated interfaces, checks, tests, docs, contracts, coverage,
  sanitizer, performance, and platform jobs are green.
- Two consecutive full CI runs are green.
- No open P0/P1 issue exists.
- Consumer install and execution pass on all three operating systems.
- The maintainer has reviewed the remaining runtime/compiler performance limits
  and the explicit copy boundaries.
