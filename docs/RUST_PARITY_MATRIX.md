# BufferUtils 0.37 Rust Parity Matrix

This matrix compares BufferUtils with the bounded core surface of Rust
`std::io`, `bytes`, and Tokio I/O. TLS, compression, UDP, codec frameworks,
io_uring, and ownership/type-system equivalence are outside the denominator.
A release at the stated 90% maturity level requires at least 90 points, all
correctness and resource-safety blockers resolved, and a measured performance
baseline without unexplained regression.

## Current score

| Area | Weight | Score | Evidence and remaining gap |
| --- | ---: | ---: | --- |
| Buffer and zero-copy | 20 | 19 | FixedArray ranges, geometric growth, COW, typed access, spare capacity, zero-copy BytesView, and checked fixed-array adoption; the backing-array immutability rule remains a documented caller obligation |
| Synchronous I/O | 25 | 24 | borrowed ranges, progress/error contracts, buffering, seek, adapters, validated slices, and native vectored capability; iterator-style text APIs and some platform-specific address accessors remain outside the surface |
| Asynchronous I/O | 20 | 18 | fixed ranges, reusable copy buffer, buffered views, cancellation protection, normalized runtime errors, flush-before-shutdown, and TCP half-close; cancellation-point and async TCP workload coverage can still grow |
| Native resources | 15 | 14 | direct borrowed file/TCP I/O, POSIX `readv`/`writev`, Windows `WSARecv`/`WSASend`, scalar Windows-file fallback, counters, sync, mmap, locks, and idempotent close; full socket-address objects and timeout getters are not exposed |
| Performance | 10 | 7 | four large sizes, isolated small/short/vectored/native/mmap workloads, counters, Ubuntu artifact, toolchain metadata, and two-of-three comparison; fixture construction and async/TCP workloads need further isolation |
| Documentation and quality | 10 | 8 | bilingual README, API/native safety contracts, 0.36→0.37 migration, executable examples, 90% native-target coverage, cross-platform tests, and sanitizers; broad property/concurrent-close suites remain a follow-up |
| **Total** | **100** | **90** | **90 release threshold met; residual deductions are recorded per area** |

## Completed capabilities

- Shared `FixedArray[Byte]` storage with logical ranges, geometric growth, COW
  mutation, zero-copy clone/slice/split/freeze, and borrowed `BytesView`.
- Signed and unsigned integers, floats, endian variants, UTF-8, resize,
  reclaim, unsplit, and checked spare-capacity initialization.
- Borrowed synchronous `Read`/`Write`, validated `IoSlice` types, scalar
  vectored fallback, exact-progress helpers, and structured `IoError`.
- Cursor-based `BufReader`/`BufWriter`, recoverable pending tails, seek,
  BufStream, memory pipe, Cursor, Empty, Repeat, Take, Chain, and LineWriter.
- Direct native borrowed file/TCP FFI, POSIX and Windows vectored paths,
  scalar Windows-file fallback, syscall counters, durability sync, open-option
  presets, mmap owner retention, TCP shutdown/timeouts/ports, independent
  external objects, locks, finalizers, and idempotent close.
- Fixed-buffer async traits and wrappers, cancellation-protected copy progress,
  runtime error mapping, real write-half shutdown, cross-target tests,
  sanitizer jobs, generated-interface checks, executable examples, and a 90%
  library coverage gate.

## Residual gaps after 90

1. Move all benchmark fixture and adapter construction outside timed samples,
   and add dedicated TCP loopback and async-copy rows.
2. Expand property/model coverage to cancellation points, concurrent close,
   random seek and vectored boundary generation.
3. Consider richer socket address and timeout-getter APIs if the bounded Rust
   parity scope is widened.

The score describes implemented capability, not throughput relative to Rust.
It should only increase when the corresponding implementation and gate are both
present in the repository.
