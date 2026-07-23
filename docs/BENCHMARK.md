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
`scripts/check_performance_batches` first calculates the median ratio within
each workload family (buffer, sync read/write, native read/write, and mmap) and
uses it to normalize shared-runner speed (never making a faster runner stricter
than the raw baseline). It fails only when the same case still exceeds its
family-normalized baseline median by 10% in at least two batches. The baseline
metadata must match `moon version --all`.

Native file and mmap timing remains in every batch and its structural,
copy-count, call-count, and syscall contracts are enforced. Absolute native
timing is diagnostic on GitHub's shared runners because filesystem latency and
throughput vary independently of CPU speed; it is not part of the failure
decision until a dedicated runner is available.

Cases whose committed median is below 50 microseconds are also diagnostic.
A 10% delta at that scale is smaller than shared-runner scheduling noise; these
cases must be lengthened before they can become hard timing gates.
