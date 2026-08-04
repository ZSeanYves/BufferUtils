# Contributing

Use the pinned MoonBit toolchain recorded under `toolchains/`. Changes must
preserve short-progress, Interrupted, EOF, WriteZero, cancellation,
pending-data recovery, and idempotent-close contracts.

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
an entry in the migration guide. Keep the project pre-1.0 compatibility policy
explicit in release notes.
