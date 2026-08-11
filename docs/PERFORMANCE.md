# Performance Evidence and Benchmark Method

## Scope

Performance evidence separates library behavior from benchmark fixtures, MoonBit
runtime/compiler cost, async scheduling, operating-system variance, and shared
runner noise. Passing a regression gate does not mean that BufferUtils equals
Rust.

The comparison uses Rust 1.97.1, `bytes` 1.12.1, and Tokio 1.53.1. MoonBit is
the latest nightly installed by the CI runner, whose complete identity is
uploaded with each artifact.

## Latest verified CI result

The complete final run was [31311385990](https://github.com/ZSeanYves/BufferUtils/actions/runs/31311385990).
All validation, sanitizer, coverage, contract, and performance jobs passed.
The following are MoonBit/Rust median ratios from its three calibrated batches;
below `1.0` means MoonBit was faster for that case.

| Case | Ratio | Interpretation |
| --- | ---: | --- |
| Shared clone, 1 KiB / 1 MiB | `0.047 / 0.047` | O(1) shared range operation |
| Shared slice, 1 KiB / 1 MiB | `0.043 / 0.043` | O(1) shared range operation |
| Shared split, 1 KiB / 1 MiB | `0.088 / 0.089` | O(1) split descriptor and ranges |
| Raw read, 1 KiB / 1 MiB | `1.18 / 0.75` | small-call cost vs bulk advantage |
| Buffered bypass | `0.76 / 0.84` | near or better than Rust in this workload |
| Buffered small read, 1 KiB / 1 MiB | `1.76 / 1.66` | trait and call-boundary cost remains |
| Buffered small write, 1 KiB / 1 MiB | `2.45 / 2.13` | repeated boundary and copy cost remains |
| Raw small write, 1 KiB / 1 MiB | `1.72 / 1.67` | call/result overhead dominates |
| Short write | `1.74` | repeated progress boundaries remain |
| Vectored fallback / bulk | `1.86 / 2.75` | descriptor and dispatch cost remains |
| Async copy, 1 KiB / 1 MiB | `8.90 / 1.99` | async frame and scheduler cost remains |

These ratios are evidence from one final CI run, not a universal performance
score. The committed Ubuntu baseline is a regression guard and is intentionally
not a claim of Rust parity.

## Measurement rules

Build MoonBit and Rust binaries once, outside timing and RSS collection. Execute
the generated binaries directly. Each case uses identical payload, chunk,
buffer size, operation order, warmups, samples, and shared iteration count.

Each final case performs 10 warmups and 30 measured samples. The setup is outside
the timer; counters are read after timing. A pilot calibrates each case to a
minimum signal, and the larger implementation count is shared by both sides.
MoonBit and Rust run as adjacent processes with alternating order.

The synchronous PR-03 diagnostics run `sync_read_to_shared` and
`sync_read_to_materialized` as separate MoonBit cases. Both construct the
final owned result inside the timer. The shared case records the bytes copied
by the reader into its adopted backing; the materialized case additionally
records the observed length copied from `read_to_end`'s scratch buffer into the
caller-owned `Array`. These are structural copy counters, not inferred
allocation counts or Rust parity cases.

The PR-04 async controls similarly run `async_shared_read` and
`async_materialized_read` as separate cases. Each records the reader's observed
copy count, the number of awaited reads including EOF, and scheduler-inclusive
timing. The materialized case additionally records the observed final Core
`Bytes` length copied at the explicit `read_to_end` boundary. These controls
are structural diagnostics, not MoonBit/Rust parity cases.

The timing CSV is:

```text
implementation,name,size,batch,iterations,median_us,p95_us,bytes,copied_bytes,underlying_calls,syscalls,median_mib_per_s
```

Independent sidecars contain raw samples, copy evidence, async control evidence,
peak RSS, environment identity, and profiler output. A missing counter is
reported as unavailable or zero with an explicit scope; the benchmark never
multiplies payload size to invent an internal copy.

## Regression policy

The gate fails only when a comparable case is more than 15% worse than its
committed Ubuntu ratio in at least two of three batches. A noisy batch is
rerun and then fails; thresholds are not widened. Baselines may be updated only
for an explicit `name,size` allowlist backed by three structurally valid batches.

Native file, mmap, TCP, and real-disk timings remain diagnostic when no
structurally identical Rust workload exists.

The PR-02 ownership refactor refreshed only the two `buffer_shared_clone`
entries listed in `bench/baselines/pr02-candidate-cases.csv`. Attempts 1 and 2
of CI run 31325227809 each produced three structurally valid batches at a
stable ratio of approximately `0.126`. A same-toolchain, same-iteration local
A/B between the pre-PR-02 and PR-02 implementations showed unchanged
per-clone cost, so the evidence identifies a runner/toolchain ratio shift
rather than a reproducible library regression. No threshold or unrelated
baseline entry was changed.

The PR-04 implementation itself passed the complete performance job in CI run
31495616259. A documentation-only follow-up then exposed a stale
`sync_short_write_16,1024` baseline twice: run 31498034406 attempts 1 and 2
each produced three structurally valid batches at stable ratios of
approximately `2.47`, while the committed center was `2.14326`. The source
diff from the passing implementation run contained only maintenance-plan text,
and async control/copy evidence remained valid. The candidate allowlist in
`bench/baselines/pr04-candidate-cases.csv` therefore refreshes only that one
unmodified synchronous case from attempt 2; the 15% threshold and every other
baseline remain unchanged.

## Confirmed causes and limits

- Bulk copy paths use Core blit primitives; the original per-byte library loops
  were removed.
- Shared range operations use a value descriptor and have no hot-path object
  allocation in the generated native code inspected for rc.2.
- Small synchronous I/O retains trait dispatch, result construction, range
  validation, and repeated call boundaries.
- Async copy retains coroutine suspension, cancellation protection, and
  scheduler work even after the short-write loop was fused.
- COW growth and detach capacity are tested separately from steady-state RSS.
- `perf` may be unavailable on hosted runners; Callgrind or the equivalent
  unprivileged profile is retained instead.

The library must not claim that remaining gaps are solved by changing the
baseline. Each non-parity case needs profiler evidence and a stated runtime,
compiler, adapter, or library cause.

## Verification commands

```bash
scripts/check_performance_budget .tmp/bufferutils-bench/moonbit.csv
scripts/check_performance_budget .tmp/bufferutils-bench/rust.csv
scripts/check_copy_evidence .tmp/bufferutils-bench/moonbit.csv .tmp/bufferutils-bench/moonbit-copy-evidence.csv
scripts/check_copy_evidence .tmp/bufferutils-bench/rust.csv .tmp/bufferutils-bench/rust-copy-evidence.csv
scripts/check_async_control_evidence .tmp/bufferutils-bench
scripts/check_performance_quality .tmp/bufferutils-bench/moonbit.csv .tmp/bufferutils-bench/moonbit-raw.csv
scripts/check_performance_batches bench/baselines/ubuntu-x86_64-ratios.csv .tmp/bufferutils-bench/moonbit.csv .tmp/bufferutils-bench/rust.csv
```
