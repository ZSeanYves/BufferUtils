# BufferUtils

BufferUtils 0.40 is a shared byte-buffer and synchronous, asynchronous, and
native I/O toolkit for MoonBit. Version 0.40 is pre-1.0 and intentionally
breaks the 0.37 API without a deprecation layer.

The current source version is `0.40.0-rc.1`. Do not treat the RC as published
until the release workflow and clean consumer-install jobs have completed.

| Package | Responsibility | Targets |
| --- | --- | --- |
| `buffer` | `SharedBytes`, `BytesMut`, typed `Buf`/`BufMut`, chain/take | all |
| `io` | synchronous traits, buffering, seek, lazy cursors, adapters | all |
| `async_io` | async traits, buffering, lazy cursors, duplex and copy | native |
| `native` | files, TCP, mmap, structured addresses and OS errors | native |

See [`docs/MIGRATION_0.37_TO_0.40.md`](docs/MIGRATION_0.37_TO_0.40.md) before
upgrading.

## Shared buffers

`SharedBytes::from_fixed_array` safely copies its selected range.
`unsafe_adopt_fixed_array` is reserved for backing storage that will never be
mutated again while a shared value is reachable. Clone, slice, split, and
freeze share storage; aliased mutable storage detaches through copy-on-write.

```moonbit
let mutable = @buffer.BytesMut::new(capacity=32)
mutable.put_u16_be(0x1234U.to_uint16())
mutable.put_utf8("MoonBit")
let immutable = mutable.freeze()
let prefix = immutable.slice(0, 2)
```

Typed helpers cover MoonBit's 8/16/32/64-bit signed and unsigned integers,
floats, and both byte orders. Bounds failures leave cursors unchanged.

## Synchronous I/O

`Read` and `Write` preserve short progress, Interrupted, EOF, and WriteZero
contracts. `BufReader::lines` and `split` are lazy cursors:

```moonbit
let reader = @io.BufReader::new(@io.MemoryReader::new(b"one\ntwo\n"))
let lines = reader.lines()
while lines.next() is Some(line) {
  process(line)
}
```

`BufWriter::into_parts` retains pending bytes without I/O. Buffer adapters,
seek, vectored fallback, `BufStream`, memory pipes, chain/take, and line
buffering are included.

## Async and native I/O

The async package provides lazy lines/split, chain/take, buffered streams,
bounded in-memory duplex pipes, typed helpers, and bidirectional copy with
independent buffer sizes. Cancellation leaves only committed progress visible
and preserves pending duplex data.

Native files, sockets, and mmap views use synchronized external state and
idempotent close. TCP exposes structured local/peer addresses and timeout
getters. File/socket/mmap read/write/close races run under ASan/UBSan/TSan.

TLS, compression, UDP, codec frameworks, io_uring, Rust ownership equivalence,
u128 helpers, and uninitialized-memory APIs are outside 0.40 scope.

## Verification

```bash
moon fmt --check
moon info --target all
scripts/normalize_interfaces
git diff --exit-code
moon check --target all --deny-warn
moon test --target all --deny-warn
moon doc --frozen
scripts/check_api_surface
scripts/check_critical_contracts
```

CI additionally enforces at least 95% overall library coverage and 90% for
each of `buffer`, `io`, `async_io`, and `native`; validates structural
benchmark counters; compares per-case MoonBit/Rust ratios; and records peak
RSS separately. No absolute claim of matching Rust throughput is made.

Further contracts and evidence are documented in
[`docs/API_CONTRACT.md`](docs/API_CONTRACT.md),
[`docs/RUST_PARITY_MATRIX.md`](docs/RUST_PARITY_MATRIX.md),
[`docs/BENCHMARK.md`](docs/BENCHMARK.md), and
[`docs/NATIVE_SAFETY.md`](docs/NATIVE_SAFETY.md).

Publishing is maintainer-only and is never performed by CI. See
[`docs/RELEASE_0.40.md`](docs/RELEASE_0.40.md) for the prepublish and clean
consumer-install procedure.
