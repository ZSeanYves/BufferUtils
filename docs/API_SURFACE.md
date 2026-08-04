# API Surface

This document defines what BufferUtils intends to expose in 0.40. The generated
interfaces are the machine-checked source of truth; this page explains why a
symbol is public and how it should be named.

## Public layers

| Layer | Packages | Intended use |
| --- | --- | --- |
| Core | `buffer`, portable `io` traits and adapters | application byte processing and custom backends |
| Async | `async_io` | cancellation-aware native-target streaming |
| Native | `native` | files, TCP, mmap, OS error boundaries |
| Evidence | counter accessors and `Memory*` fixtures | tests, benchmarks, and contract diagnostics |
| Examples | `examples` | executable documentation outside the core compatibility promise |

The evidence layer remains visible because CI must assert real copy, underlying
call, and syscall counts. Those values are diagnostics, not synchronization
state, durability guarantees, or a promise about throughput.

## Naming rules

- Types and error variants use PascalCase.
- Methods and fields use lower snake case.
- Constructors use `new`, `from_*`, `open_*`, `connect`, `bind`, or `duplex`.
- `Async*` is reserved for asynchronous wrappers and endpoints.
- `Native*` is reserved for operating-system resources.
- `get_ref` and `get_mut` borrow the wrapped resource; `into_inner` consumes it.
- `*_ms` values are milliseconds; `*_calls` and `*_syscalls` are diagnostic counters.
- `*_view` and `buffer()` return borrowed views. A view is valid only until the
  next operation on its owner.

## Ownership boundaries

`SharedBytes` is immutable and shareable. `BytesMut` is mutable and detaches
with copy-on-write when its storage is aliased. `from_fixed_array` copies;
`unsafe_adopt_fixed_array` is the only public adoption boundary and carries an
explicit no-mutation safety contract. `into_parts` returns pending bytes only
after the wrapper has stopped using its backing storage.

`native` values own independent external resources. `close` is explicit and
idempotent; finalizers are only leak-prevention fallback. `MappedBytes` slices
retain their mmap owner, while `copy_range` is the explicit materialization API.

## Deliberate exclusions

The public surface does not emulate Rust ownership types, uninitialized spare
capacity, `u128`/`i128`, TLS, compression, UDP, codec frameworks, or io_uring.
These exclusions are recorded as `excluded-language` or `excluded-scope` in
[`RUST_PARITY_MATRIX.md`](RUST_PARITY_MATRIX.md), rather than hidden behind
misleading aliases.
