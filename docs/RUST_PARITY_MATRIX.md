# Rust Parity Matrix

This matrix defines the BufferUtils 1.0 release gate. The score is a delivery
measurement, not a claim that MoonBit has Rust's ownership or OS model.

## Weighted Areas

| Area | Weight | Required gate |
| --- | ---: | --- |
| `buffer` shared bytes and cursor operations | 25 | 100% of core rows |
| synchronous `io` traits and adapters | 30 | 100% of core rows |
| asynchronous traits and adapters | 25 | 100% of core rows |
| native files, sockets, seek, and mmap | 10 | Linux/macOS/Windows rows |
| documentation, API snapshots, and release tooling | 10 | all release checks |

The release requires every row marked `core` and a weighted score of at least
80. Rows marked `extension` are deliberately outside the 1.0 denominator:
TLS, compression, full codec frameworks, and UDP datagrams.

## Buffer Core (25)

| Capability | Class | Verification |
| --- | --- | --- |
| immutable shared `SharedBytes` | core | model and target tests |
| mutable COW `BytesMut` | core | mutation and alias tests |
| O(1) split, split-off, clone, freeze | core | copied-byte counter is zero |
| `Buf` cursor and chunk operations | core | conformance tests |
| `BufMut` reserve and put operations | core | capacity model tests |
| endian integers and UTF-8 | core | boundary tests |
| explicit Core `SharedBytes`/`Array` conversion | core | copy counter tests |

## Synchronous I/O (30)

| Capability | Class | Verification |
| --- | --- | --- |
| `Read` and `Write` partial progress | core | memory/native/fault backends |
| Interrupted retry, EOF, WriteZero | core | injected failures |
| `BufRead::fill_buf/consume/read_until/read_line` | core | allocation-free parser tests |
| `Seek` and `SeekFrom` | core | cursor/file tests |
| `BufReader` and `BufWriter` bypass paths | core | call counters and benchmarks |
| pending-tail recovery and `into_parts` | core | flush failure tests |
| Cursor, Empty, Repeat, Take, Chain, LineWriter | core | adapter matrix |
| vectored I/O fallback and capability reporting | core | scalar equivalence tests |

## Asynchronous I/O (25)

| Capability | Class | Verification |
| --- | --- | --- |
| `AsyncRead` and `AsyncWrite` | core | memory/file/socket adapters |
| async buffered reader/writer | core | partial and backpressure tests |
| async seek for files | core | independent-offset tests |
| cancellation-safe copy and close | core | cancellation tests |
| TCP stream/listener adapters | core | loopback tests |
| codec/TLS/compression/UDP | extension | not scored in 1.0 |

## Native and Release Quality (20)

The native rows require Linux, macOS, and Windows CI. The release also requires
all stable MoonBit targets, generated interface snapshots, documentation
examples, sanitizer runs, property tests, and the performance budget script.
