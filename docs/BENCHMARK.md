# Benchmark Guide

Run:

~~~bash
mkdir -p .tmp/bufferutils-bench
moon run bench --target native --release > .tmp/bufferutils-bench/results.csv
scripts/check_performance_budget
~~~

The runner performs 5 warmups and 30 measured samples for 1KB, 64KB, and 1MB.
Each row contains:

~~~text
name,size,bytes,temp_file,median_us,p95_us,min_us,max_us,copied_bytes,median_mib_per_s
~~~

The groups are shared split/freeze, COW mutation, raw and buffered synchronous
read/write, native file write/flush, and mmap scan. `copied_bytes` is the
storage instrumentation value; split/freeze rows must be zero. At 1MB the
buffered bypass rows must remain within 10% of their raw counterparts. Results
are local regression evidence, not portable throughput claims.
