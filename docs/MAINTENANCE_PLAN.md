# BufferUtils 1.0 Rewrite Execution Report

## Status

| Phase | Status | Evidence |
|---|---|---|
| 0: contracts and gates | Complete | parity matrix, API contract, API/performance scripts |
| 1: shared buffer core | Complete | SharedBytes/BytesMut, COW, 10,000-operation model test |
| 2: synchronous I/O | Complete | traits, seek, combinators, failure recovery, vectored fallback |
| 3: native platform layer | Complete in source | per-resource external objects, files, TCP, mmap, Windows branches |
| 4: async contracts | Complete | own traits, buffers, memory/file/TCP adapters, copy helpers |
| 5: hard switch and release | Complete | empty root API, 1.0.0 manifest, docs, migration, CI matrix |

## Acceptance Snapshot

- `moon check --target all --deny-warn` passes.
- `moon test --target all --deny-warn` passes: 37/37 on wasm, wasm-gc, and js;
  61/61 on native.
- Native-instrumented library coverage excluding the benchmark executable is
  1080/1193 lines (90.5%); the pure buffer/io/async core is 927/947 (97.9%).
  CI enforces the 90% library threshold.
- The root compatibility API and global native handle registry are removed.
- split/freeze/clone/slice paths expose copied-byte instrumentation and test as
  zero.
- Sync buffering tests cover short progress, Interrupted, EOF, WriteZero,
  contract violations, seek invalidation, and pending-tail recovery.
- Native tests cover file seek/close, mmap parent/child lifetime and raw OS
  errors, and TCP loopback. ASan/UBSan and TSan each pass 6/6 locally.
- Async tests cover memory, buffering, pending-tail recovery, independent file
  offsets, buffered seek, TCP loopback, and cancellation progress.
- The performance gate uses 5 warmups and 30 samples, requires zero copied
  payload bytes for shared operations, and enforces the 1MB raw-path 10% budget.

Windows runtime verification and Linux leak detection are enforced by CI
because they cannot be executed from a macOS workstation. The source contains
the Windows UTF-16 file path, Win32 mapping, per-object mutex, and per-object
Winsock lifetime branches.

## Scope Boundary

TLS, compression, full codec frameworks, and UDP are not part of the 1.0
denominator. Rust lifetime, Send, and Sync types are represented through
immutable shared storage, COW, explicit Close, and native mutex boundaries.
