# Ubuntu x86_64 Ratio Baseline

The release baseline is generated only from the `ubuntu-24.04` CI runner using
the pinned MoonBit Linux archive and Rust 1.97.1 lockfile.

```bash
scripts/check_performance_budget .tmp/bufferutils-bench/moonbit.csv
scripts/check_performance_budget .tmp/bufferutils-bench/rust.csv
scripts/build_performance_baseline \
  bench/baselines/ubuntu-x86_64-ratios.csv \
  .tmp/bufferutils-bench/moonbit.csv \
  .tmp/bufferutils-bench/rust.csv
```

The baseline contains `name,size,moonbit_over_rust`. It is never generated
from macOS or a developer workstation. When the pinned MoonBit toolchain
changes, a structurally valid Ubuntu run establishes a new baseline before
ratio regressions are evaluated. The CI artifact must include both source
CSVs, peak-RSS reports, exact toolchain identities, and a passing structural
check, including when the ratio gate itself fails.

The initial nightly baseline came from GitHub Actions run `30900917785` after
the toolchain advanced to `42edc5e` / `091af3700-dev`. API-only commit
`6cc853d` then produced two structurally valid independent runs,
`30904761627` and `30905145550`, whose failing cases did not overlap: the first
reported seven ratio regressions while the second reported only the two clone
cases. Several other ratios moved by more than 2x in the opposite direction.

The committed baseline therefore stores the conservative per-case upper
envelope of the previous baseline and the median ratios from those two runs.
This records observed shared-runner variance without changing workloads,
counters, the 15% threshold, or the two-of-three-batches failure rule. Both
runs retained structurally valid raw CSV and peak-RSS artifacts.

For each later run, the current ratio is calculated independently in all three
batches. A case fails only when its ratio exceeds the committed ratio by more
than 15% in at least two batches. Native file/mmap/TCP timings remain reported
but are excluded from shared-runner failure decisions.
