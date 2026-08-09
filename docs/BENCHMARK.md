# Benchmark Guide

BufferUtils uses Rust 1.97.1, `bytes` 1.12.1, and Tokio 1.53.1 as the fixed
comparison toolchain. `Cargo.lock` is committed under `bench/rust-reference`.
MoonBit benchmarks use the latest nightly installed by CI.

Build both implementations once, then execute the generated binaries so build
processes cannot contaminate timing or RSS:

```bash
mkdir -p .tmp/bufferutils-bench
moon run bench --target native --release --build-only
moon run bench_async --target native --release --build-only
cargo build --release --locked --manifest-path bench/rust-reference/Cargo.toml

# Pilot each runtime independently without a shared iteration map.
_build/native/release/build/bench/bench.exe 1 \
  > .tmp/bufferutils-bench/pilot-moonbit.csv
_build/native/release/build/bench_async/bench_async.exe 1 \
  > .tmp/bufferutils-bench/pilot-moonbit-async.csv
bench/rust-reference/target/release/bufferutils-rust-reference 1 \
  > .tmp/bufferutils-bench/pilot-rust.csv

scripts/build_shared_iterations \
  .tmp/bufferutils-bench/shared-iterations.csv \
  .tmp/bufferutils-bench/pilot-moonbit.csv \
  .tmp/bufferutils-bench/pilot-moonbit-async.csv \
  .tmp/bufferutils-bench/pilot-rust.csv
for batch in 1 2 3; do
  # CI runs each selected MoonBit/Rust case as an adjacent pair, alternates
  # which implementation runs first, and aggregates timing/raw/evidence rows.
  # The workflow contains the complete executable loop.
  _build/native/release/build/bench/bench.exe "$batch" sync_raw_read
  bench/rust-reference/target/release/bufferutils-rust-reference \
    "$batch" sync_raw_read
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
inside the timer, and reads counters after timing stops. A pilot for each
runtime doubles iterations until its measured median is at least 10ms. CI then
takes the larger MoonBit/Rust pilot count for each comparable case, adds a 25%
margin, and writes `shared-iterations.csv`. All three final MoonBit and Rust
batches execute that exact count. Each comparable case is run as an adjacent
MoonBit/Rust process pair, and the first implementation alternates across cases
and batches to prevent runner phase from systematically favoring one side. The
regression gate rejects any count that differs across implementations or
batches. Each final invocation performs 10 warmups and 30 measured samples.
Case-class amplification remains part of pilot calibration for operations whose
sub-10ms signal would otherwise be too small; it does not permit the final
workloads to diverge.

Fake writers copy every accepted byte into a fixture allocated before timing,
account exact accepted bytes and calls, and sample the scratch buffer's first
and last byte plus the accepted length into an observed checksum. Rust also
passes the copied destination through `black_box`; otherwise LLVM can retain
the checksum while eliminating unobserved middle stores. Shared clone, slice,
and split workloads retain the produced handle instead of observing only its
constant length. The independent `*-copy-evidence.csv` sidecars contain
observed fixture bytes, COW bytes, underlying calls, and syscalls. An
unavailable counter is explicitly zero and marked `unavailable`; the runner
never multiplies payload size to claim an unobserved internal copy.

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
