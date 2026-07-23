# Ubuntu x86_64 Baseline Procedure

No absolute Ubuntu baseline is committed in 0.36. The release baseline must be
produced on a pinned `ubuntu-x86_64` runner with the
same MoonBit toolchain as CI:

```text
moon run bench --target native --release > .tmp/bufferutils-bench/results.csv
scripts/check_performance_budget .tmp/bufferutils-bench/results.csv
```

Run three batches of 50 samples for each 1 KiB, 64 KiB, 1 MiB, and 64 MiB
case. Store the median/p95 CSV as the CI artifact named
`bufferutils-ubuntu-x86_64-baseline.csv`; the optional second argument to
`scripts/check_performance_budget` compares a change against it and fails on a
median regression greater than 10%. Non-Ubuntu targets run structural,
copy-count, and correctness gates only.
