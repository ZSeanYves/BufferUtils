# BufferUtils

BufferUtils 0.37 is a zero-copy shared byte-buffer and I/O toolkit for MoonBit.
Its core path keeps slices, splits, freezes, and buffered pending data in shared
`FixedArray[Byte]` storage. Copying is explicit at the API boundary, so callers
can see when data is materialized as an `Array` or Core `Bytes` value.

## Packages

| Package | Responsibility | Targets |
| --- | --- | --- |
| `buffer` | `SharedBytes`, `BytesMut`, `Buf`, `BufMut`, typed endian access | all targets |
| `io` | fallible synchronous `Read`/`Write`, buffering, seeking, adapters | all targets |
| `async_io` | async traits, buffered wrappers, copy and stream adapters | native |
| `native` | files, TCP, mmap-backed `MappedBytes`, OS error mapping | native |

Install the fixed release from another MoonBit module:

```bash
moon add ZSeanYves/bufferutils@0.37.0
```

The 0.37 release intentionally breaks the 0.36 source API. See
[`docs/MIGRATION_0.36_TO_0.37.md`](docs/MIGRATION_0.36_TO_0.37.md) before upgrading.

## Zero-copy model

`SharedBytes::clone`, `slice`, `split_to`, `split_off`, and
`BytesMut::freeze` share the backing allocation. Mutation of an aliased or
frozen range performs copy-on-write only for the range that must become
mutable. `SharedBytes::as_bytes_view()` is a borrowed Core view over the
fixed storage; it does not allocate. `to_array`, `to_bytes`, `read_array`, and
`write_array` are deliberately named copy adapters.

```moonbit
import { "ZSeanYves/bufferutils/buffer" @buffer }

let mutable = @buffer.BytesMut::new(capacity=32)
mutable.put_u16_be(0x1234U.to_uint16())
mutable.put_utf8("MoonBit")
let immutable = mutable.freeze()
let prefix = immutable.slice(0, 2)
mutable.put_byte(b'!')
ignore(prefix.as_bytes_view())
```

Typed APIs cover signed and unsigned integers, `f32`/`f64`, both byte orders,
UTF-8, capacity management, spare-capacity initialization, reclaim, and
validated split/unsplit operations. Underflow, overflow, invalid UTF-8, and
invalid ranges leave the cursor unchanged and return `BufferError`.

## Synchronous I/O

The primary `Read` method borrows a `FixedArray[Byte]` range and the primary
`Write` method borrows a `Bytes` range. `read_array` and `write_array` are
convenience adapters when an `Array` is more convenient and may copy.

`read_exact` and `write_all` handle short progress, `Interrupted`, EOF, and
`WriteZero`. `BufReader` provides `buffer`, `peek`, `seek_relative`,
`skip_until`, `lines`, and `split`. `BufWriter` uses start/end cursors,
compacts only when needed, and retains a zero-copy pending tail through
`into_parts` or a structured `finish` failure. Cursor, Empty, Repeat, Take,
Chain, LineWriter, BufStream, and memory duplex adapters are included.

```moonbit
import { "ZSeanYves/bufferutils/io" @io }

let source = @io.MemoryReader::new(b"header:payload", max_chunk=3)
let reader = @io.BufReader::new(source, capacity=8)
let header = Array::make(7, (0).to_byte())
@io.Read::read_exact(reader, header.mut_view())
let rest : Array[Byte] = []
@io.read_to_end(reader, rest)
```

`Write::flush` drains user-space buffers only. Native file durability is
requested explicitly with `NativeFile::sync_all()` or `sync_data()`.

## Native and async I/O

Native resources are independent external objects with per-resource state,
mutex protection, idempotent close, and finalizer fallback. `NativeFile`
supports validated open options, seek, flush, durability sync, and mmap.
`NativeTcpStream` supports read/write/both shutdown, timeouts, and local/peer
port metadata. `MappedBytes` keeps its owner alive while slices exist;
`copy_range` is the explicit materialization boundary.

`async_io` defines `AsyncRead`, `AsyncWrite`, `AsyncBufRead`, `AsyncSeek`, and
`AsyncClose` with the same caller-range validation. Buffered async views are
borrowed until the next reader operation. Async copy reuses one fixed buffer,
preserves committed progress across cancellation, and `copy_bidirectional`
invokes the destination's `AsyncWrite::shutdown` hook after EOF. Runtime
errors are normalized to `IoError` while cancellation remains observable.

TLS, compression, UDP datagrams, full codec frameworks, io_uring, and Rust's
ownership/type-system equivalence are intentionally outside this library's
scope.

## Verification

```bash
moon info && scripts/normalize_interfaces && moon fmt
moon check --target all --deny-warn
moon test --target all --deny-warn
scripts/check_api_surface
moon check examples --target native --deny-warn
moon run bench --target native --release > .tmp/bufferutils-bench/results.csv
scripts/check_performance_budget
```

See [`docs/API_CONTRACT.md`](docs/API_CONTRACT.md),
[`docs/RUST_PARITY_MATRIX.md`](docs/RUST_PARITY_MATRIX.md),
[`docs/BENCHMARK.md`](docs/BENCHMARK.md),
[`docs/PERFORMANCE_BASELINE.md`](docs/PERFORMANCE_BASELINE.md), and
[`docs/NATIVE_SAFETY.md`](docs/NATIVE_SAFETY.md) for contracts, release gates,
measurement methodology, and platform safety notes.
