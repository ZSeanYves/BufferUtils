# Ubuntu x86_64 Ratio Baseline

The release baseline is generated only from the `ubuntu-24.04` CI runner using
the latest MoonBit nightly available on the CI runner and Rust 1.97.1 lockfile.

```bash
scripts/check_performance_budget .tmp/bufferutils-bench/moonbit.csv
scripts/check_performance_budget .tmp/bufferutils-bench/rust.csv
scripts/build_performance_baseline \
  bench/baselines/ubuntu-x86_64-ratios.csv \
  .tmp/bufferutils-bench/moonbit.csv \
  .tmp/bufferutils-bench/rust.csv
```

The baseline contains `name,size,moonbit_over_rust`. It is never generated from
macOS or a developer workstation. The pre-correction baseline was discarded
when fixture copy semantics and process isolation changed. A structurally valid
corrected Ubuntu run establishes the replacement before ratio regressions are
evaluated. Its artifact must include timing CSVs, raw samples, copy evidence,
peak-RSS reports, exact toolchain identities, and passing structural and noise
checks.

The sequential implementation-wide baseline was retired when consecutive
structurally valid runs still changed stable per-case ratios by 20%-50%. Final
timings now execute as adjacent MoonBit/Rust case pairs with alternating order.
The replacement baseline was generated from the structurally valid paired
artifact of GitHub Actions run
[`31303880886`](https://github.com/ZSeanYves/BufferUtils/actions/runs/31303880886)
at commit `14a1183`. The run passed all platform, sanitizer, coverage, contract,
timing, raw-sample, copy-evidence, async-control, and profiler checks. The
committed ratios detect later regressions; they do not assert Rust parity.

The superseded nightly runs `30900917785`, `30904761627`, and `30905145550`
remain historical diagnostics only. Their non-overlapping regressions exposed
shared-runner variance, but their ratios cannot seed the corrected baseline.

For each later run, the current ratio is calculated independently in all three
batches. A case fails only when its ratio exceeds the committed ratio by more
than 15% in at least two batches. Native file/mmap/TCP timings remain reported
but are excluded from shared-runner failure decisions.
