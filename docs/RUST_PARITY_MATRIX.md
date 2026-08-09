# BufferUtils 0.40 Rust Parity Matrix

Reference versions are Rust 1.97.1 `std::io`, `bytes` 1.12.1, and Tokio
1.53.1. The matrix is a capability inventory, not a weighted maturity score.

| Reference area | Status | BufferUtils surface | Evidence |
| --- | --- | --- | --- |
| `bytes::Bytes` clone, slice, split, visible range | implemented | immutable `SharedBytes` plus `BytesCursor` for consumption | buffer state-model, cursor, COW, and zero-copy tests; benchmark copy counters |
| Safe construction from mutable storage | implemented | `from_fixed_array` copies; `unsafe_adopt_fixed_array` is explicit | alias mutation tests |
| Visible-byte equality, ordering, hash, debug | implemented | `SharedBytes` trait implementations | cross-range tests and generated docs |
| `bytes::BytesMut` zeroed, reserve, extend-within, freeze | implemented | `BytesMut` | buffer package tests and COW/growth structural benchmarks |
| `Buf` / `BufMut` 8/16/32/64 integer and float helpers | implemented | big- and little-endian defaults | typed roundtrip and atomic-failure tests |
| `Buf::chain` / `take` adapters | implemented | `BufChain`, `BufTake` | adapter progress tests |
| `std::io::Read`, `Write`, vectored fallback | implemented | synchronous traits and helpers | short-progress, Interrupted, EOF, WriteZero tests |
| `BufReader`, `BufWriter`, seek and recovery | implemented | cursor-based buffering and `into_parts` | recovery, bypass, seek, and model tests |
| Lazy `lines` and `split` | implemented | `Lines[R]`, `Split[R]` | laziness, UTF-8 error, EOF recovery tests |
| `BufRead::has_data_left`, `BufWriter::buffer` | implemented | matching methods | boundary tests and generated interface gate |
| `Buf`/I/O adapters | implemented | `BufReaderAdapter`, `BufMutWriterAdapter` | short read/write and invalid-range tests |
| Tokio typed async read/write helpers | implemented | `AsyncRead`, `AsyncWrite` defaults | signed, unsigned, float endian roundtrips |
| Async lazy lines/split, chain/take, buffered stream | implemented | `AsyncLines`, `AsyncSplit`, `AsyncChain`, `AsyncTake`, `AsyncBufStream` | async cursor and cancellation tests |
| In-memory async duplex | implemented | bounded `duplex` | wait, cancellation, pending-data, EOF tests |
| Bidirectional async copy with independent sizes | implemented | `copy_bidirectional_with_sizes` | committed byte-count tests |
| Structured socket addresses and timeout getters | implemented | `SocketAddress`, local/peer address, timeout getters | native loopback tests |
| Concurrent file/socket/mmap close safety | implemented | native C locks and view lifetime lock | native race helper under ASan/UBSan/TSan |
| Uninitialized spare-capacity APIs | excluded-language | only initialized `FixedArray[Byte]` views are exposed | MoonBit cannot express Rust's `MaybeUninit` ownership contract |
| `u128` / `i128` typed helpers | excluded-language | 8/16/32/64-bit helpers only | current MoonBit public integer surface |
| Rust ownership and borrowing equivalence | excluded-language | runtime COW and documented borrowed-view validity | no ownership-equivalent MoonBit type system |
| TLS, compression, UDP, codec framework, io_uring | excluded-scope | none | explicitly outside BufferUtils 0.40 |

Completion is determined by the release gates in CI: strict checks and docs,
all stable targets, sanitizer races, 95% overall coverage, 90% per-package
coverage, structural performance counters, Rust comparison ratios, and clean
consumer installation. A row is only `implemented` when executable evidence is
present in the repository.
