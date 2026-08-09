# BufferUtils Documentation

BufferUtils is a pre-1.0 MoonBit library for shared immutable byte ranges,
copy-on-write mutable buffers, and composable synchronous and asynchronous
streaming I/O.

The current source version is `0.40.0-rc.2`. The repository does not publish
packages, create tags, or create GitHub Releases automatically.

## Reading order

1. [Architecture and contracts](ARCHITECTURE.md) explains package boundaries,
   ownership semantics, copy boundaries, I/O behavior, native safety, naming,
   and deliberate exclusions.
2. [Maintenance plan](MAINTENANCE_PLAN_0.40.md) records the current state and
   the staged PR plan for reaching final release quality.
3. [Performance evidence](PERFORMANCE.md) defines the benchmark method, the
   latest verified CI results, known causes, and the remaining limits.
4. [Migration guide](MIGRATION.md) combines the 0.37-to-0.40 and rc.1-to-rc.2
   source changes.
5. [Release procedure](RELEASE.md) is the maintainer-only checklist for RC,
   consumer verification, and manual publication.

## Sources of truth

- Generated `pkg.generated.mbti` files are the machine-checked public API.
- `moon.mod` is the module and version source of truth.
- CI uses the latest MoonBit toolchain available at run time and records its
  identity in every validation and performance artifact.
- The Rust comparison remains pinned to Rust 1.97.1, `bytes` 1.12.1, and
  Tokio 1.53.1.
- Executable tests, sanitizer jobs, coverage reports, and performance
  artifacts take precedence over prose claims.

## Repository layout

- `src/buffer`, `src/io`, `src/async_io`, and `src/native` are the four
  maintained functional packages.
- `src/examples` contains executable documentation and is not a compatibility
  package.
- `src/bench` and `src/bench_async` contain MoonBit benchmark entry points.
- `bench/` retains the Rust reference project and committed benchmark data.
- `docs/`, `scripts/`, and `toolchains/` contain documentation, verification
  tooling, and Rust comparison locks. There are no maintained functional
  packages at the repository root.

The `src` source root is an implementation-layout detail. It does not add
`src` to public package import paths.

Coverage reports may include zero-execution benchmark rows because benchmark
entry points share the source root. The coverage gate intentionally aggregates
only the four core package reports (`buffer`, `io`, `async_io`, and `native`).

## Documentation policy

Every public symbol needs a generated interface entry, API documentation, and
either a focused test or an executable example. A performance statement must
link to a reproducible CI artifact and must state whether it is a regression
gate, a parity result, or diagnostic evidence. Historical migration details
remain in `MIGRATION.md` and must not be copied into current API claims.
