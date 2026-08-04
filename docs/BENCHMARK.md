# Benchmark Guide

BufferUtils uses Rust 1.97.1, `bytes` 1.12.1, and Tokio 1.53.1 as the fixed
comparison toolchain. `Cargo.lock` is committed under `bench/rust-reference`.

Build both implementations once, then execute the generated binaries so build
processes cannot contaminate timing or RSS:

```bash
mkdir -p .tmp/bufferutils-bench
moon run bench --target native --release --build-only
moon run bench_async --target native --release --build-only
cargo build --release --locked --manifest-path bench/rust-reference/Cargo.toml
for batch in 1 2 3; do
  _build/native/release/build/bench/bench.exe "$batch" \
    > ".tmp/bufferutils-bench/moonbit-batch-$batch.csv"
  _build/native/release/build/bench_async/bench_async.exe "$batch" \
    > ".tmp/bufferutils-bench/moonbit-async-batch-$batch.csv"
  bench/rust-reference/target/release/bufferutils-rust-reference "$batch" \
    > ".tmp/bufferutils-bench/rust-batch-$batch.csv"
done
scripts/merge_performance_batches .tmp/bufferutils-bench
scripts/check_performance_budget .tmp/bufferutils-bench/moonbit.csv
scripts/check_performance_budget .tmp/bufferutils-bench/rust.csv
scripts/check_copy_evidence \
  .tmp/bufferutils-bench/moonbit.csv \
  .tmp/bufferutils-bench/moonbit-copy-evidence.csv
scripts/check_copy_evidence \
  .tmp/bufferutils-bench/rust.csv \
  .tmp/bufferutils-bench/rust-copy-evidence.csv
scripts/check_performance_quality \
  .tmp/bufferutils-bench/moonbit.csv \
  .tmp/bufferutils-bench/moonbit-raw.csv
scripts/check_performance_quality \
  .tmp/bufferutils-bench/rust.csv \
  .tmp/bufferutils-bench/rust-raw.csv
scripts/check_async_control_evidence .tmp/bufferutils-bench
```

The exact CSV schema is:

```text
implementation,name,size,batch,iterations,median_us,p95_us,bytes,copied_bytes,underlying_calls,syscalls,median_mib_per_s
```

Each case constructs its fixture outside the timer, runs only the operation
inside the timer, and reads counters after timing stops. Iterations double
until the measured median is at least 10ms. Each invocation performs 10
warmups and 30 measured samples for one requested batch. The runner executes
three batches in interleaved MoonBit-sync, MoonBit-async, Rust order and then
merges the per-batch CSV files.

Fake writers copy every accepted byte into a fixture allocated before timing,
account exact accepted bytes and calls, and sample the scratch buffer's first
and last byte plus the accepted length into an observed checksum. This makes a
reported sink copy a real memory copy without adding a second full checksum
scan. MoonBit and Rust use the same rule; the checksum is consumed after timing
to prevent dead-code elimination. The independent `*-copy-evidence.csv`
sidecars contain observed fixture bytes, COW bytes, underlying calls, and
syscalls. An unavailable counter is explicitly zero and marked `unavailable`;
the runner never multiplies payload size to claim an unobserved internal copy.

ArrayView fallback and `IoSlice` bulk vectored writes are separate cases. Both
record the sink fixture's actual copied bytes. The `*-raw.csv` sidecars retain
all 30 sorted samples. The quality report records MAD, raw CV, CV through p95,
p95/median, and max/median. The gate uses the p95 CV and p95/median so one
retained scheduler outlier cannot invalidate an otherwise stable median and
p95; a second upper-tail outlier enters p95 and fails the batch. A noisy gated
batch is rerun up to three times and then fails rather than widening a baseline.

Async control and cursor diagnostics use a separate schema because cancellation
and shutdown failure are operations, not byte-throughput workloads:

```text
implementation,name,size,batch,iterations,median_us,p95_us,operations,bytes,copied_bytes,await_points,failures
```

`scripts/check_async_control_evidence` reconstructs median and p95 from all 30
raw samples and verifies ready, pending, typed u64 read/write, 16-byte short
progress, cancellation, shutdown failure, 64 KiB line, and 64 KiB
no-delimiter-plus-EOF structure. Its
`copied_bytes` field is limited to source bytes actually observed crossing the
fixture boundary. It does not claim to count uninstrumented runtime copies.

The 16-byte short-write contract uses a 1KiB payload. Repeating the same
contract with a 1MiB payload creates 65,536 dynamic calls per iteration and
dominated shared-runner time without adding a distinct behavioral case; large
payload behavior remains covered by the raw, buffered and bypass workloads.

The structural gate rejects fake or inconsistent counters. It verifies O(1)
clone/slice/split/freeze copy zero payload bytes, COW copies the detached
range, growth copies the retained prefix, fixture copies match accepted bytes,
bypass records one underlying call, ArrayView fallback records two calls, bulk
vectored records one call, and MoonBit native file rows match real FFI syscall
counters.
Async copy is compared against Tokio with explicit read/write-call counts. TCP
loopback reports zero for unavailable runtime syscall counters instead of
inventing a value, and is diagnostic rather than ratio-gated.

`scripts/build_performance_baseline` calculates the median per-case
MoonBit/Rust ratio across three batches using per-iteration time. Native file,
mmap, TCP, and real-disk rows are diagnostic on shared runners. The regression
gate fails only when a comparable case ratio is more than 15% worse than the
committed Ubuntu baseline in at least two of three batches. There is no
workload-family normalization and no absolute requirement to equal Rust.

The committed `bench/baselines/ubuntu-x86_64-ratios.csv` must be generated by
the corrected GitHub Actions runner after timing structure, copy evidence, and
raw quality checks pass. The downloadable artifact is the source of truth for
raw rows and per-batch peak RSS; the baseline contains only median per-case
ratios used by the regression gate.

The pre-correction upper-envelope baseline was discarded because it mixed
ArrayView byte loops, build-process RSS, and inferred copy multipliers with the
library measurements. It is not valid evidence for the corrected workloads.

Peak RSS is collected by a separate process wrapper and is not placed in the
CSV. The combined implementation process and each major synthetic case are
recorded separately; per-case runs use an isolated working directory so their
sidecars cannot overwrite the three gated batches. Setup cost, filesystem
timing, and RSS remain visible diagnostic evidence rather than being mixed into
the gated operation timing.

The Linux job attempts `perf` and always runs unprivileged Callgrind. It uploads
annotated call data for shared slice, raw and buffered reads, raw, buffered, and
short writes, bulk vectored write, and async copy. Profiler files are evidence,
not benchmark timing inputs.
