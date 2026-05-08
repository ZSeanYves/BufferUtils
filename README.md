# BufferUtils

BufferUtils is a byte-buffer utility library for MoonBit.

It provides:

- low-level in-memory readers and writers
- fixed-capacity and auto-growing buffer writers
- memory-backed streaming-style readers and writers
- file convenience APIs for buffered write and buffered read
- an experimental native C backend package for native-target file handles
- UTF-8 conversion and delimiter-based split helpers

BufferUtils is intentionally conservative about its claims:

- it is not zero-copy
- the stable default package still uses memory-backed file convenience layers
- it does not make benchmark-proven performance claims

[English](https://github.com/ZSeanYves/BufferUtils/blob/main/README.md) | [简体中文](https://github.com/ZSeanYves/BufferUtils/blob/main/README_zh_CN.md)

## Overview

BufferUtils has five API layers:

1. `BufferReader` and `BufferWriter` for direct in-memory byte work.
2. Growing-writer support on top of the low-level writer.
3. `MemorySource`, `MemorySink`, `BufReader`, and `BufWriter` for streaming-style memory APIs.
4. `FileSource`, `FileSink`, `new_file_buf_reader`, and `FileBufWriter` as file convenience layers.
5. `ZSeanYves/bufferutils/native` as an experimental native-target C backend for file handles.

Standalone example files were removed in `v0.10.0`. Usage snippets now live in this README so the documented surface stays closer to the release-ready API.

## Installation

```bash
moon add ZSeanYves/bufferutils
```

Or add it to `moon.mod.json`:

```json
{
  "deps": {
    "ZSeanYves/bufferutils": "0.22.0"
  }
}
```

## Quick Start

### Basic Buffer Reading

```moonbit
let reader = new_reader(Bytes::from_array([1, 2, 3, 4]))

let first = reader.read_byte()
let next_two = reader.read_exact(2)
let rest = reader.read_remaining()
```

### Fixed and Growing Writers

```moonbit
let fixed = new_fixed_writer(4)
fixed.write_all([1, 2, 3, 4])
let fixed_bytes = fixed.flush_to_bytes()

let growing = new_growing_writer(2)
growing.write_all([1, 2, 3, 4, 5])
growing.reserve(16)
growing.ensure_capacity(32)
let growing_bytes = growing.flush_to_bytes()
```

`new_writer(capacity)` is still available as a compatibility constructor for fixed-capacity writers, but `new_fixed_writer` and `new_growing_writer` are the preferred 1.0-facing entry points.

### Memory Streaming

```moonbit
let source = new_memory_source(Bytes::from_array([1, 2, 3, 4, 5]))
let reader = new_buf_reader(source, 2)
let data = reader.read_to_end()

let sink = new_memory_sink()
let writer = new_buf_writer(sink, 2)
writer.write_all([10, 20, 30, 40])
writer.flush()
let sink = writer.into_inner()
let out = sink.to_bytes()
```

`BufReader` and `BufWriter` are streaming-style APIs over concrete memory-backed types. BufferUtils does not expose a trait-based custom source/sink abstraction in the stable default package.

### File Writing

```moonbit
let writer = new_file_buf_writer(".tmp/out.bin", 4)
writer.write_all([72, 101, 108, 108, 111])
writer.flush()
```

`FileSink` and `FileBufWriter` accumulate bytes in memory and write to disk on `flush()`. The current behavior is flush-time overwrite, not append-mode or OS-level streaming file handles.

### File Reading

```moonbit
let reader = new_file_buf_reader(".tmp/input.bin", 4)
let header = reader.read_exact(2)
let rest = reader.read_to_end()
```

`FileSource` is a memory-backed snapshot. The file is read into memory when the source is created, and later external file changes are not reflected by that source instance.

### File Roundtrip

```moonbit
let writer = new_file_buf_writer(".tmp/roundtrip.bin", 4)
writer.write_all([1, 2, 3, 4, 5])
writer.flush()

let reader = new_file_buf_reader(".tmp/roundtrip.bin", 2)
let out = reader.read_to_end()
```

### Experimental Native C Backend

```moonbit
import {
  "ZSeanYves/bufferutils/native" @native,
}

let sink = @native.new_native_file_sink(
  ".tmp/native-out.bin",
  @native.NativeFileMode::Overwrite,
)
sink.write_all([1, 2, 3, 4])
sink.flush()
sink.close()

let source = @native.new_native_file_source(".tmp/native-out.bin")
let first_chunk = source.read_chunk(2)
source.close()

let writer = @native.new_native_buf_writer(
  ".tmp/native-buffered.bin",
  4,
  @native.NativeFileMode::Overwrite,
)
writer.write_all([10, 20, 30, 40, 50])
writer.close()

let reader = @native.new_native_buf_reader(".tmp/native-buffered.bin", 2)
let head = reader.read_exact(2)
let tail = reader.read_to_end()
reader.close()
```

The native backend is experimental and native-target only. It uses a C `FILE*`
backend for chunked reads and direct writes, but it does not replace the stable
pure MoonBit file convenience layer. Explicit `close()` is required. `close()`
attempts a final flush for sinks, but explicit `flush()` is still the clearer
error-handling boundary when callers need to know whether bytes reached the OS
stdio buffer before releasing the handle. `NativeBufReader` and `NativeBufWriter`
build buffered refill/flush behavior on top of those same native file handles
without turning the stable root package into a native-only API.

### Experimental View / Slice API

```moonbit
let reader = new_reader(Bytes::from_array([1, 2, 3, 4]))
let head = reader.peek_slice(2)
let rest = reader.remaining_slice()

let source = new_memory_source(Bytes::from_array([1, 2, 3, 4]))
let snapshot = source.peek_remaining()
```

These APIs are experimental and non-consuming. They return `BytesView`, but BufferUtils does not promise that the underlying MoonBit runtime always represents these results as shared non-copying storage. Treat them as read-only slice/view results rather than zero-copy guarantees.

These APIs are currently experimental public APIs before `1.0`:

- they do not advance reader/source position
- they return read-only `BytesView`
- their bounds checks and error semantics are part of the intended stable behavior
- they are not part of the stable copy-returning API family

BufferUtils intentionally does not expose writer/sink-side views because mutable buffers, growth, `clear()`, and flush-time state changes would make lifetime and invalidation rules much riskier.

### Convert and Split Utilities

```moonbit
let text = "MoonBit"
let utf8 = string_to_utf8_bytes(text)
let decoded = utf8_bytes_to_string(utf8)

let bytes = ints_to_bytes([65, 66, 67])
let parts = split_bytes(Bytes::from_array([1, 0, 0, 2]), (0).to_byte())
```

`ints_to_bytes` validates the `0..255` byte range. `utf8_bytes_to_string` raises `Utf8DecodeError` on invalid UTF-8 input.

## Reduced-Copy Notes

`v0.12.0`, `v0.13.0`, `v0.14.0`, and `v0.15.0` focus on reduced-copy behavior rather than zero-copy behavior.

- `BufferWriter.flush_to_bytes()` still returns a copy and does not clear the writer.
- `MemorySink.to_bytes()` and `FileSink.to_bytes()` still return copies.
- `FileSource` is still a memory-backed snapshot created by reading the file into memory up front.
- `FileSink` is still a memory-backed accumulator that persists on `flush()`.

Several internal paths now prefer chunk-based append and copy logic over repeated per-byte `push` loops, but BufferUtils still does not claim zero-copy semantics.

`v0.14.0` adds an experimental view/slice investigation on reader-side APIs only, and `v0.15.0` hardens its boundary coverage and docs. These APIs do not change existing copy-returning behavior, and they should be treated as reduced-copy experiments rather than stable no-copy contracts.

## Public API Surface

The stable public surface is intentionally small:

- low-level: `BufferReader`, `BufferWriter`, `new_fixed_writer`, `new_growing_writer`
- memory streaming: `MemorySource`, `MemorySink`, `BufReader`, `BufWriter`
- file convenience: `FileSource`, `FileSink`, `new_file_buf_reader`, `FileBufWriter`
- utilities: `bytes_to_array`, `array_to_bytes`, `ints_to_bytes`, `string_to_utf8_bytes`, `utf8_bytes_to_string`, `split_bytes`, `split_array_bytes`

The detailed reference lives in [docs/API.md](./docs/API.md).

Experimental view/slice notes live in [docs/VIEW_API.md](./docs/VIEW_API.md).
Experimental native backend notes live in [docs/NATIVE_BACKEND.md](./docs/NATIVE_BACKEND.md) and [docs/NATIVE_SAFETY.md](./docs/NATIVE_SAFETY.md).
Read-only mmap feasibility notes live in [docs/MMAP_FEASIBILITY.md](./docs/MMAP_FEASIBILITY.md).

## API Stability

BufferUtils is approaching `1.0`. The snake_case APIs documented in [docs/API.md](./docs/API.md) are the intended stable public surface for the `1.0` release.

`new_writer(capacity)` is retained as a legacy compatibility constructor for fixed-capacity writers. Additional compatibility wrappers from earlier releases were removed in `v0.10.0` so the release surface is easier to maintain.

The `BytesView` APIs are public but explicitly experimental before `1.0`. They are available to use, but they are not positioned as stable zero-copy contracts.

## Error Handling

BufferUtils uses:

- `BufferError` for buffer, capacity, validation, flush, and file I/O errors
- `Utf8DecodeError` for UTF-8 decoding failures

Common cases include:

- `Underflow` when a read goes past available bytes
- `Overflow` when a fixed-capacity writer cannot accept more data
- `InvalidInput` for negative lengths or out-of-range integers
- `Io` or `Flush` for file-related failures

## Design Notes

The current design is concrete-type based:

- constructors use `new_*`
- behavior lives on the concrete types
- conversion and split helpers remain standalone functions
- custom trait-based source/sink abstraction is deferred

More detail is in [docs/DESIGN.md](./docs/DESIGN.md), [docs/VIEW_API.md](./docs/VIEW_API.md), [docs/NATIVE_BACKEND.md](./docs/NATIVE_BACKEND.md), [docs/NATIVE_SAFETY.md](./docs/NATIVE_SAFETY.md), and [docs/MMAP_FEASIBILITY.md](./docs/MMAP_FEASIBILITY.md).

## Benchmark Baseline

`v0.11.0` adds an experimental benchmark baseline for repeatable local measurements. `v0.12.0` keeps the same output format while tracking reduced-copy changes, `v0.13.0` adds regression-audit notes, `v0.14.0` adds view/slice experiment benchmark comparisons, `v0.15.0` keeps those cases explicitly in the experimental bucket, `v0.16.0` records the pure-MoonBit streaming feasibility study, `v0.17.0` adds experimental native backend cases, `v0.18.0` hardens the native lifecycle/error-path coverage, `v0.19.0` adds experimental native buffered benchmark cases, `v0.20.0` stabilizes benchmark naming/documentation around memory-backed, native file-handle, and native buffered groups, `v0.21.0` records why experimental mmap stays in feasibility-study mode instead of adding a misleading public API, and `v0.22.0` performs the 1.0 release-candidate audit without changing core behavior.

Run it with:

```bash
moon run src/bench --target native --release
```

The runner prints CSV-style rows with elapsed microseconds, byte length, a simple throughput estimate, and whether the case touches temporary files under `.tmp/bufferutils-bench/`.
Native backend benchmark cases require a native target and a working C toolchain because the experimental backend is compiled through MoonBit C FFI. The current runner uses a light warmup before measured runs, then reports `mean_us` across the configured repeated runs. File-system cache effects can significantly affect repeated native read runs, and small-file cases are especially sensitive to fixture setup and call overhead.

The benchmark guide lives in [docs/BENCHMARK.md](./docs/BENCHMARK.md).

Current benchmark notes remain experimental and local-only. They are useful for regression tracking, not for guaranteed throughput claims.

## Current Limitations

- not zero-copy
- `FileSource` reads the whole file into memory on construction
- `FileSink` accumulates bytes in memory and overwrites the file on flush
- experimental view/slice APIs may still copy depending on MoonBit runtime behavior
- the experimental native backend is currently native-target only
- the experimental native backend requires explicit `close()`, and read-only mmap remains under feasibility study rather than exported API
- the experimental native backend still maps handle failures to `BufferError::Io` rather than exposing platform-specific errno detail
- no async I/O
- no benchmark claims yet

## Roadmap

- native backend hardening across more targets and CI environments
- read-only native mmap feasibility study, pending a safer MoonBit borrowed-byte FFI story
- trait-based custom source/sink abstraction
- borrowed byte views
- read-only slice API stabilization
- true zero-copy investigation
- reduced-copy APIs
- benchmark baseline refinement and historical comparison tooling

## License

Apache-2.0
