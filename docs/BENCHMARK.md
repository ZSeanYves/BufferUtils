# Benchmark Guide

Run:

~~~bash
mkdir -p .tmp/bufferutils-bench
moon run bench --target native --release > .tmp/bufferutils-bench/results.csv
scripts/check_performance_budget
~~~

The runner performs 5 warmups and 50 measured samples for 1KB, 64KB, 1MB, and
64MB. Small writes, short writes, vectored writes, native reads, and mmap are
reported as separate fixed-size workloads so a 1-byte short-write test cannot
turn a 64 MiB sample into billions of calls.
Each row contains:

~~~text
name,size,bytes,temp_file,median_us,p95_us,min_us,max_us,copied_bytes,allocations,underlying_calls,syscalls,median_mib_per_s
~~~

The groups include shared split/freeze, COW mutation, raw and buffered
synchronous read/write, small and short writes, vectored writes, native file
read/write, and mmap scan. `copied_bytes` is the storage instrumentation value;
split/freeze rows must be zero. Results are local regression evidence, not
portable throughput claims.

CI runs three batches on `ubuntu-24.04`. For each batch,
`scripts/check_performance_batches` first calculates the median ratio across
all matching workloads and uses it to normalize shared-runner speed (never
making a faster runner stricter than the raw baseline). It fails only when the
same case still exceeds its normalized baseline median by 10% in at least two
batches. The baseline metadata must match `moon version --all`.
