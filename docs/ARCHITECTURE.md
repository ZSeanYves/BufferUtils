# Architecture and Contracts

## Product boundary

BufferUtils is not a replacement for a generic MoonBit array or string
container. Its core contract is:

> Shared immutable byte ranges and copy-on-write mutable buffers, integrated
> with composable synchronous and asynchronous streaming I/O.

The library owns byte ownership and stream-progress contracts. It does not
emulate Rust's ownership type system, and it does not claim every path is
zero-copy.

## Package boundaries

| Package | Source path | Responsibility | Targets |
| --- | --- | --- | --- |
| `buffer` | `src/buffer` | Shared ranges, mutable buffers, cursors, `Buf` and `BufMut` | all supported targets |
| `io` | `src/io` | Fallible synchronous read/write, buffering, seek, and adapters | all supported targets |
| `async_io` | `src/async_io` | Cancellation-aware async traits, buffering, duplex, and copy | native |
| `native` | `src/native` | Files, TCP, mmap, OS errors, and close safety | native |
| `examples` | `src/examples` | Executable documentation | native |
| `bench`, `bench_async` | `src/bench`, `src/bench_async` | Benchmark-only executables and evidence instrumentation | native |

`moon.mod` declares `src` as the module source root, so the source path is
not part of any public import path.

`native` is an operating-system boundary. Its external resources are not
ordinary `SharedBytes` backing storage. `examples` and the benchmark packages
are outside the compatibility promise of the four core packages.

## Ownership model

### `SharedBytes`

`SharedBytes` is an immutable `#valtype` containing a shared backing allocation
and a visible `[start, end)` range. `clone`, `slice`, `prefix`, `suffix`, and
`split_at` do not mutate the source or copy payload bytes on the supported hot
path.

`SharedBytes` does not implement `Buf` and has no consuming methods. Use
`bytes.cursor()` when a read operation needs a mutable position.

### `BytesMut`

`BytesMut` is the mutable construction and accumulation type. `freeze()` returns
an immutable `SharedBytes` snapshot without copying. A later mutation detaches
the smallest required mutable range when a frozen or aliased backing is
reachable. Earlier snapshots remain unchanged.

### `BytesCursor`

`BytesCursor` owns a position independent of its source `SharedBytes`. It is the
only byte-range type intended to advance, split consumptively, copy out, or run
typed `get_*` helpers.

## Copy boundaries

| Operation | Contract |
| --- | --- |
| `SharedBytes::from_array` | Copies the array view |
| `SharedBytes::from_fixed_array` | Validates and copies the selected range |
| `unsafe_adopt_fixed_array` | Explicit unsafe adoption; caller must not mutate the backing |
| `SharedBytes::as_bytes_view` | Borrowed view; no payload copy |
| `BytesMut::freeze` | Shared immutable snapshot; no payload copy |
| `read_to_shared_bytes` final adoption | Transfers its exclusive fixed backing; growth may copy retained prefixes |
| `write_shared` / `write_all_shared` | Borrow the shared backing as Core `Bytes`; no payload copy |
| async `read_to_shared_bytes` final adoption | Freezes the accumulator as shared storage; no final Core `Bytes` materialization |
| async `write_shared` / `write_all_shared` | Extract the backing Core `Bytes` and absolute range before awaiting; no borrowed view crosses an await |
| `SharedBytes::to_array` / `to_bytes` | Explicit materialization |
| `BufRead::fill_buf` | Borrowed internal reader storage until the next reader operation |
| `MappedBytes::copy_range` | Explicit materialization from an mmap view |

The public API must not call a path zero-copy when it crosses one of these
explicit materialization boundaries.

## Borrowed-view inventory

Borrowed values are valid only for the lifetime stated in this table. They are
not ownership transfers and must not be stored for later use unless the caller
materializes them explicitly.

| API | Borrowed value | Valid until |
| --- | --- | --- |
| `SharedBytes::view` | `ArrayView[Byte]` | The backing `SharedBytes` remains reachable; the view is read-only |
| `SharedBytes::as_bytes_view` | `BytesView` | The backing `SharedBytes` remains reachable; the view is read-only |
| `BytesMut::view` | `ArrayView[Byte]` | The next mutation that may detach or rebase the buffer |
| `BufRead::fill_buf` | `ArrayView[Byte]` | The next operation on the same reader |
| `BufReader::buffer` / `BufWriter::buffer` | `ArrayView[Byte]` | The next operation that changes the wrapper buffer |
| `AsyncBufRead::fill_buf` | `ArrayView[Byte]` | The next operation on the same async reader; never across an async suspension |

Use `to_array`, `to_bytes`, or `SharedBytes::clone` when a value must outlive
the stated boundary. A borrowed view must never be used to infer ownership or
to mutate the source.

## Materialization inventory

Every payload copy is explicit in the API and evidence:

| Boundary | Result | Reason |
| --- | --- | --- |
| `SharedBytes::from_array` / `from_fixed_array` | owned immutable backing | safe construction copies caller-owned data |
| `SharedBytes::to_array` / `to_bytes` | owned mutable/Core bytes | caller requested materialization |
| `BufReader::into_parts` / `AsyncBufReader::into_parts` | owned `Bytes` remainder | wrapper storage must leave the reader |
| `BufReader::into_shared_parts` | owned `SharedBytes` remainder | synchronous wrapper storage transfers directly |
| `BufWriter::into_parts` / `AsyncBufWriter::into_parts` | owned `SharedBytes` remainder | wrapper storage must leave the writer |
| `MappedBytes::copy_range` | owned `Bytes` | mmap lifetime must not escape the native owner |
| `BytesMut` detach or growth | new mutable backing | COW protects immutable snapshots and aliases |

Benchmark copy evidence distinguishes `fixture-observed`, `unavailable`, and
native syscall counters. It must never convert a payload size into a claimed
internal copy count.

## Synchronous and asynchronous I/O

`Read` and `Write` classify invalid ranges, short progress, `Interrupted`, EOF,
`WriteZero`, and backend contract violations. `read_exact` and `write_all`
retry ordinary short progress and report cumulative progress on failure.

`BufReader` and `BufWriter` own user-space buffering. `flush` drains the user
buffer; native durability requires `sync_all` or `sync_data`. `into_parts` is
only valid after the wrapper has stopped using its backing storage.

Synchronous callers can use `read_to_shared_bytes` to accumulate directly into
an exclusively owned fixed backing and transfer it to `SharedBytes` without a
final materialization. Geometric capacity growth can still copy the retained
prefix; the API is ownership-preserving, not universally zero-copy.
`write_shared` and `write_all_shared` pass the backing Core `Bytes` plus the
shared range offset through the unchanged `Write` trait. The older
`read_to_end`, `write_all_bytes`, and materializing `into_parts` paths remain
available.

`AsyncRead` and `AsyncWrite` preserve the same progress and error meanings
while adding pending and cancellation behavior. One read chunk in
`async_io::copy` is a cancellation-protected unit; all short writes and the
committed byte count for that chunk complete inside the same protection region.

Async callers can use `read_to_shared_bytes` to freeze the accumulator without
the final materialization performed by `read_to_end`. Appending each completed
read chunk is cancellation-protected. `write_shared` performs one underlying
write; `write_all_shared` protects and accounts for each completed short write
before retrying. Both shared write functions extract the backing Core `Bytes`
and range offset synchronously before awaiting, so a borrowed `BytesView` never
survives a suspension point. The existing Core `Bytes` APIs remain available.

## Native safety

Each native file, socket, listener, and mmap view owns an independent external
object with platform locking and idempotent close state. There is no global
handle registry or global last-error slot. Mmap slices retain their owner;
closing a parent does not invalidate a live child view.

Native errors map to portable `IoErrorKind` values while raw platform codes
remain diagnostic. Callers must close resources on success, error, and
cancellation. ASan/UBSan and TSan validate the same C layer used by release
builds.

## External resource lifetime inventory

| Resource | Owner | Child/lifetime rule | Close contract |
| --- | --- | --- | --- |
| `NativeFile` | `NativeFile` handle | no byte view borrows the file after close | idempotent `Close`; close on success, error, and cancellation |
| `NativeTcpStream` | stream handle | local and peer addresses are snapshots, not handle aliases | shutdown and close are independent, idempotent operations |
| `NativeTcpListener` | listener handle | accepted streams own their handles independently | closing the listener does not close accepted streams |
| `MappedBytes` | mmap owner/view | slices retain the owner; a child keeps its mapping alive | parent and child closes are idempotent |
| async native wrappers | wrapped native resource | wrapper close delegates exactly once to the underlying resource | pending or cancelled operations must still release the resource |

No public shared-byte type owns an OS handle. Native resources and immutable
byte ranges remain separate ownership domains.

## API and naming rules

- Types and error variants use PascalCase.
- Methods and fields use lower snake case.
- `Async*` is reserved for asynchronous wrappers and endpoints.
- `Native*` is reserved for OS resources.
- `get_ref` and `get_mut` borrow a wrapped value; `into_inner` consumes it.
- `*_view` and `buffer()` return borrowed views.
- `to_array` and `to_bytes` name explicit materialization.
- `unsafe_` is mandatory for unsafe adoption boundaries.
- `*_calls` and `*_syscalls` are diagnostic names, not correctness state.

Generated interfaces are the public API source of truth. Public counters and
benchmark fixtures should not become permanent compatibility obligations.

`docs/API_ALLOWLIST.txt` is the exact reviewed public surface generated from
the four compatibility-package interfaces. `scripts/check_api_surface`
regenerates it in memory, writes `.tmp/API_SURFACE_DIFF.md`, and fails on any
undeclared addition, removal, or signature change. `scripts/check_api_names`
enforces the rules above and keeps `SharedBytes`, native mmap owners, and native
socket owners in visibly separate ownership domains. `docs/API_EVIDENCE.tsv`
must cover every public owner; its checker requires a generated documentation
section, all public methods in that section, and a focused test or executable
example. An intentional API change must update the implementation, generated
interfaces, allowlist, API review, migration note, and evidence in the same PR.

## Rust parity inventory

The comparison target is Rust 1.97.1 `std::io`, `bytes` 1.12.1, and Tokio
1.53.1. The inventory is capability-based, not a weighted score.

Implemented capabilities include immutable shared ranges, safe and unsafe
construction boundaries, visible-byte value semantics, mutable freeze/COW,
typed `Buf`/`BufMut`, synchronous buffered I/O, lazy lines/split cursors,
buffer adapters, async buffering and duplex, cancellation-aware copy,
structured socket addresses, and native close safety.

The following remain explicitly excluded:

- Rust ownership and borrowing type-system equivalence
- Uninitialized spare-capacity APIs
- `u128`/`i128` helpers unavailable in the supported MoonBit surface
- TLS, compression, UDP, codec frameworks, and io_uring
