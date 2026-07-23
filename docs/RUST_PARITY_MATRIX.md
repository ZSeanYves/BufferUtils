# BufferUtils 0.36 Rust Parity Matrix

This matrix compares BufferUtils with the bounded core surface of Rust
`std::io`, `bytes`, and Tokio I/O. TLS, compression, UDP, codec frameworks,
io_uring, and ownership/type-system equivalence are outside the denominator.
A release at the stated 90% maturity level requires at least 90 points, all
correctness and resource-safety blockers resolved, and a measured performance
baseline without unexplained regression.

## Current score

| Area | Weight | Score | Evidence and remaining gap |
| --- | ---: | ---: | --- |
| Buffer and zero-copy | 20 | 18 | FixedArray ranges, geometric growth, COW, typed access, spare capacity; public fixed-array adoption relies on a caller immutability contract and does not validate its range |
| Synchronous I/O | 25 | 23 | borrowed ranges, progress/error contracts, buffering, seek and adapters; native implementations use only the scalar vectored fallback and text helpers are eager collections rather than iterators |
| Asynchronous I/O | 20 | 13 | fixed ranges, reusable copy buffer, buffered views and cancellation protection; runtime errors are not uniformly mapped to `IoError`, and the default shutdown hook is a no-op for current TCP adapters |
| Native resources | 15 | 11 | direct borrowed file/TCP I/O, OpenOptions presets, sync, mmap, locks and idempotent close; no POSIX `readv`/`writev`, Windows `WSARecv`/`WSASend`, full socket addresses, or timeout getters |
| Performance | 10 | 4 | geometric growth, copied-byte checks, four sizes and three CI batches; workloads, counters, prebuilt fixtures, committed baseline and two-of-three regression comparison are incomplete |
| Documentation and quality | 10 | 7 | bilingual README, contracts, migration, examples, 90.6% library coverage, cross-platform tests and sanitizers; examples are compiled rather than executed, and property/concurrent-close coverage is incomplete |
| **Total** | **100** | **76** | **90 required** |

## Completed capabilities

- Shared `FixedArray[Byte]` storage with logical ranges, geometric growth, COW
  mutation, zero-copy clone/slice/split/freeze, and borrowed `BytesView`.
- Signed and unsigned integers, floats, endian variants, UTF-8, resize,
  reclaim, unsplit, and checked spare-capacity initialization.
- Borrowed synchronous `Read`/`Write`, validated `IoSlice` types, scalar
  vectored fallback, exact-progress helpers, and structured `IoError`.
- Cursor-based `BufReader`/`BufWriter`, recoverable pending tails, seek,
  BufStream, memory pipe, Cursor, Empty, Repeat, Take, Chain, and LineWriter.
- Direct native scalar file/TCP FFI, durability sync, open-option presets,
  mmap owner retention, TCP shutdown/timeouts/ports, independent external
  objects, locks, finalizers, and idempotent close.
- Fixed-buffer async traits and wrappers, cancellation-protected copy progress,
  cross-target tests, sanitizer jobs, generated-interface checks, and a 90%
  library coverage gate.

## Release blockers for 90

1. Implement real native vectored I/O and advertise capability only on the
   supported platform paths.
2. Override async TCP shutdown with a real write-half close and normalize all
   non-cancellation runtime failures to `IoError` while preserving cancellation.
3. Validate or make internal the unsafe fixed-array adoption boundary so a
   malformed range cannot create an invalid zero-copy view.
4. Complete the benchmark matrix: small and short writes, capacity scan,
   native read/write, TCP loopback, async copy, vectored and mmap workloads.
5. Construct inputs/files/adapters outside timed regions; record allocation,
   copied-byte, lower-level-call and syscall counts.
6. Commit an Ubuntu x86_64 baseline and enforce the stated two-of-three 10%
   regression policy rather than checking each batch only for structure.
7. Add model/property coverage for short I/O, seek, vectored boundaries,
   cancellation points and concurrent close; enforce native-package coverage
   independently and execute the examples in CI.

The score describes implemented capability, not throughput relative to Rust.
It should only increase when the corresponding implementation and gate are both
present in the repository.
