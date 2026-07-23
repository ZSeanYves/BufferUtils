# Ubuntu x86_64 Baseline Procedure

The 0.37 Ubuntu baseline is produced on the pinned `ubuntu-24.04` workflow
runner with the same MoonBit toolchain as CI:

```text
for batch in 1 2 3; do
  moon run bench --target native --release > .tmp/bufferutils-bench/results-${batch}.csv
  scripts/check_performance_budget .tmp/bufferutils-bench/results-${batch}.csv
done
moon version --all > .tmp/bufferutils-bench/toolchain.txt
scripts/build_performance_baseline bench/baselines/ubuntu-x86_64.csv \
  .tmp/bufferutils-bench/results-1.csv \
  .tmp/bufferutils-bench/results-2.csv \
  .tmp/bufferutils-bench/results-3.csv
cp .tmp/bufferutils-bench/toolchain.txt bench/baselines/ubuntu-x86_64.meta
```

Run three batches of 50 samples for each 1 KiB, 64 KiB, 1 MiB, and 64 MiB
case. Store both baseline files in the repository. Subsequent CI normalizes
each batch by the median ratio within each workload family to account for CPU,
allocator, and filesystem differences between shared GitHub runners. It fails
only after the same workload in two of three batches exceeds that normalized
family baseline by more than 10%. A uniform family slowdown is diagnostic
rather than an automatic failure; a dedicated runner is required for an
absolute-time gate. Native file and mmap timings are likewise diagnostic on
the shared runner, while their structural, copy-count, call-count, and syscall
budgets remain mandatory. Non-Ubuntu targets run structural, copy-count, and
correctness gates only.
