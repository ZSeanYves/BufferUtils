# Contributing

Use the latest MoonBit toolchain available in the current CI run. Record its
identity when reporting a failure. The Rust comparison toolchain remains fixed
by `bench/rust-reference/rust-toolchain.toml`. Changes must preserve
short-progress, Interrupted, EOF, WriteZero, cancellation, pending-data
recovery, and idempotent-close contracts.

Functional packages are under `src/`; keep the repository root limited to
benchmark reference data, documentation, scripts, and toolchain metadata.

Before submitting a change, run:

```bash
moon fmt --check
moon info --target all
scripts/normalize_interfaces
git diff --exit-code
moon check --target all --deny-warn
moon test --target all --deny-warn
moon doc --frozen
scripts/check_api_surface
scripts/check_critical_contracts
```

Native changes also require ASan/UBSan and TSan. Performance changes require
both calibrated CSVs and must not update a baseline without matching cloud
runner evidence. Do not add estimated allocation, copy, call, or syscall
counters.

Public API changes need generated interface updates, documentation, tests, and
an entry in [`docs/MIGRATION.md`](docs/MIGRATION.md). Keep the project pre-1.0
compatibility policy explicit in release notes. Read
[`docs/README.md`](docs/README.md) for the complete maintenance and release
policy.
