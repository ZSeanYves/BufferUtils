# BufferUtils 0.36 Rust Parity Matrix

This is the 100-point release gate for the deliberately bounded comparison
with Rust `std::io`, `bytes`, and Tokio core I/O. TLS, compression, UDP,
codec frameworks, io_uring, and ownership/type-system equivalence are outside
the denominator. A 0.36 release requires at least 90 points, every correctness
and resource-safety row, and no unexplained performance regression.

| Area | Weight | Current target | Gate |
| --- | ---: | ---: | --- |
| Buffer and zero-copy | 20 | 19 | FixedArray storage, COW, typed access, spare capacity |
| Synchronous I/O | 25 | 24 | borrowed Read/Write, vectored fallback, buffered cursor semantics |
| Asynchronous I/O | 20 | 19 | fixed ranges, cancellation-safe copy, shutdown, buffered views |
| Native resources | 15 | 14 | direct FFI, OpenOptions, sync, TCP lifecycle |
| Performance | 10 | 8 | geometric growth, no per-chunk async copy, benchmark gate |
| Documentation and quality | 10 | 7 | migration/API contracts, examples, tests and interfaces |
| **Total** | **100** | **91** | **90 required for release** |

## Scored Rows

| Area | Points | Verification |
| --- | ---: | --- |
| FixedArray + logical range storage | 4 | buffer model/property tests |
| COW clone/slice/split/freeze and zero-copy `BytesView` | 4 | copied-byte and alias tests |
| resize/reclaim/unsplit/spare-capacity | 3 | capacity and invalid-range tests |
| signed integer, float, endian and UTF-8 APIs | 4 | cursor-preserving boundary tests |
| explicit copy adapters (`to_array`, `to_bytes`) | 2 | conversion tests |
| typed `Buf`/`BufMut` surface | 3 | trait conformance |
| borrowed `Read` and `Write` primary paths | 5 | memory/native adapters |
| exact progress, EOF, interruption and WriteZero | 4 | fault-injection tests |
| IoSlice/IosliceMut validation and vectored fallback | 3 | boundary/conformance tests |
| BufReader peek/seek/skip/lines/split | 4 | parser and seek model tests |
| BufWriter start/end, short-write tail, finish recovery | 4 | failure/recovery tests |
| Cursor, Empty, Repeat, Take, Chain, LineWriter, BufStream | 3 | adapter matrix |
| flush vs sync durability contract | 2 | native file sync tests |
| Async fixed-array/Bytes ranges and shared validation | 4 | async memory tests |
| AsyncBufRead borrowed view and AsyncBufWriter cursors | 4 | view invalidation and short writes |
| reusable copy, cancellation and bidirectional half-close | 4 | async copy tests |
| Async file/TCP adapters and error mapping | 3 | runtime tests |
| async shutdown and cancellation propagation | 5 | cancellation/half-close tests |
| Native direct borrow and external-resource lifecycle | 4 | native tests, sanitizers |
| OpenOptions, sync_all/sync_data, TCP shutdown/timeouts | 3 | native integration tests |
| vectored capability reporting and platform fallback | 2 | target conformance |
| native seek/mmap/close safety | 3 | resource and sanitizer tests |
| native TCP addresses and timeout lifecycle | 3 | loopback tests |
| geometric allocation/copy behavior | 3 | capacity and copied-byte counters |
| 1 KiB..64 MiB benchmark matrix and baseline | 3 | `bench` output + CI gate |
| syscall/allocation/copy instrumentation | 2 | native benchmark counters |
| repeated batches and regression comparison | 2 | CI baseline script |
| API contract and 0.35 to 0.36 migration docs | 3 | docs build/review |
| compilable examples and generated interfaces | 2 | CI example target |
| cross-target tests, coverage, sanitizers | 3 | CI matrix |
| bilingual README and maintenance guidance | 2 | documentation review |
| model, fault-injection and property coverage | 3 | 90% coverage gate |

Rows marked correctness or resource safety are mandatory even when their
weighted score is otherwise met. The remaining rows are explicit follow-up
gates rather than hidden scope: platform-specific `readv/writev`, mmap-to-Core
zero-copy conversion, and an Ubuntu baseline with three 50-run batches. Scalar
vectored fallback remains correct on every target while those optimized native
rows are added.
