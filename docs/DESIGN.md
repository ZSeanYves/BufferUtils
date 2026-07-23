# Design

BufferUtils 0.37 has four ownership and capability boundaries:

1. `buffer` owns pure MoonBit shared storage and copy-on-write mutation.
2. `io` owns fallible synchronous progress, buffering, seeking, and adapters.
3. `async_io` owns async contracts while delegating scheduling to
   `moonbitlang/async`.
4. `native` owns operating-system resources through independent external
   objects, locks, and idempotent close.

## Zero-copy boundary

`SharedBytes` stores a fixed backing allocation plus logical start/end ranges.
Clone, slice, split, freeze, and buffered pending tails move handles and ranges;
they do not copy payload bytes. A write through an aliased range detaches the
smallest necessary mutable range (COW). `as_bytes_view()` borrows the same
storage. `to_array`, `to_bytes`, `read_array`, `write_array`, and mmap
`copy_range` are explicit materialization points.

The API does not claim zero-copy where MoonBit cannot express the required
lifetime or layout. In particular, mmap remains `MappedBytes` and is not
pretended to be a Core `BytesView`.

## I/O contracts

The primary synchronous and asynchronous range APIs share validation and error
classification. Short progress is normal; `read_exact` and `write_all` make
progress explicit and handle interruption, EOF, and `WriteZero`. `flush`
drains user-space buffers only; native durability is opt-in through
`sync_all`/`sync_data`.

Native vectored methods report capability and fall back to scalar operations
when a platform backend cannot provide a real `readv`/`writev` path. This keeps
the contract portable while leaving the platform optimization visible in the
parity matrix.

TLS, compression, UDP, full codec frameworks, io_uring, and Rust's ownership
type-system equivalence are intentionally outside the 0.37 scope.
