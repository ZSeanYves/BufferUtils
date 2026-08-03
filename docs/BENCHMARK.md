# Benchmark Guide

BufferUtils uses Rust 1.97.1, `bytes` 1.12.1, and Tokio 1.53.1 as the fixed
comparison toolchain. `Cargo.lock` is committed under `bench/rust-reference`.

Run both implementations:

```bash
mkdir -p .tmp/bufferutils-bench
moon run bench --target native --release > .tmp/bufferutils-bench/moonbit.csv
moon run bench_async --target native --release \
  > .tmp/bufferutils-bench/moonbit-async.csv
tail -n +2 .tmp/bufferutils-bench/moonbit-async.csv \
  >> .tmp/bufferutils-bench/moonbit.csv
cargo run --release --locked --manifest-path bench/rust-reference/Cargo.toml \
  > .tmp/bufferutils-bench/rust.csv
scripts/check_performance_budget .tmp/bufferutils-bench/moonbit.csv
scripts/check_performance_budget .tmp/bufferutils-bench/rust.csv
```

The exact CSV schema is:

```text
implementation,name,size,batch,iterations,median_us,p95_us,bytes,copied_bytes,underlying_calls,syscalls,median_mib_per_s
```

Each case constructs its fixture outside the timer, runs only the operation
inside the timer, and reads counters after timing stops. Iterations double
until the measured median is at least 10ms. Every invocation performs 10
warmups, 30 measured samples, and three batches.

The structural gate rejects fake or inconsistent counters. It verifies O(1)
clone/slice/split/freeze copy zero payload bytes, COW copies the detached
range, growth copies the retained prefix, buffered small I/O records both
copies, bypass records one underlying call, vectored fallback records two
calls, and MoonBit native file rows match real FFI syscall counters.
Async copy is compared against Tokio with explicit read/write-call counts. TCP
loopback reports zero for unavailable runtime syscall counters instead of
inventing a value, and is diagnostic rather than ratio-gated.

`scripts/build_performance_baseline` calculates the median per-case
MoonBit/Rust ratio across three batches using per-iteration time. Native file,
mmap, TCP, and real-disk rows are diagnostic on shared runners. The regression
gate fails only when a comparable case ratio is more than 15% worse than the
committed Ubuntu baseline in at least two of three batches. There is no
workload-family normalization and no absolute requirement to equal Rust.

Peak RSS is collected by a separate process wrapper and is not placed in the
CSV. Setup cost, filesystem timing, and RSS remain visible diagnostic evidence
rather than being mixed into the gated operation timing.
