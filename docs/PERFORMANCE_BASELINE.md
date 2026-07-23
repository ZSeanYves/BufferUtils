# Ubuntu x86_64 Baseline Procedure

The 0.37 Ubuntu baseline is generated on a fixed
produced on a pinned `ubuntu-x86_64` runner with the
same MoonBit toolchain as CI:

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
case. Store both baseline files in the repository. Subsequent CI uses
`scripts/check_performance_batches` and fails only after two of three batches
regress by more than 10%. Non-Ubuntu targets run structural, copy-count, and
correctness gates only.
