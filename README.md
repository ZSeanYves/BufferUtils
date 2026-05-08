# BufferUtils

A byte-buffer utility library for MoonBit.

BufferUtils provides stable pure-MoonBit byte-buffer APIs for reading, writing,
conversion, splitting, memory-backed streaming, and file convenience
workflows. It also includes experimental native-target extensions for C-backed
file handles and mmap-backed `NativeByteView` research, now backed by a
MoonBit-managed external owner bridge with explicit close and finalizer
fallback.

BufferUtils does not claim stable zero-copy behavior. `NativeByteView` is an
experimental native-only research API, not MoonBit `BytesView`.

[English](https://github.com/ZSeanYves/BufferUtils/blob/main/README.md) | [简体中文](https://github.com/ZSeanYves/BufferUtils/blob/main/README_zh_CN.md)

## Highlights

- Stable root API for byte readers, writers, memory sources/sinks, and file convenience helpers
- Fixed-capacity and auto-growing buffer writers
- Boundary-checked reads, writes, conversion, and split utilities
- Memory-backed `BufReader` / `BufWriter`
- File convenience APIs with overwrite-materialization flush semantics
- Experimental native C backend for native-target file handles
- Experimental mmap-backed `NativeByteView` for C-side zero-copy-style processing
- CI coverage for Ubuntu/macOS, root package tests, native package tests, and benchmark smoke

## What Is Stable In 1.0

The stable root package is the pure MoonBit API surface:

- `BufferReader` / `BufferWriter`
- `MemorySource` / `MemorySink`
- `BufReader` / `BufWriter`
- `FileSource` / `FileSink`
- `FileBufWriter` / `new_file_buf_reader`
- conversion helpers
- split helpers
- `BufferError`

The stable root package intentionally keeps file support honest:

- `FileSource` is a memory-backed snapshot created at construction time
- `FileSink` is a memory-backed accumulator that persists on `flush()`
- `FileSink.flush()` uses overwrite-materialization semantics, including creating or overwriting an empty file when the accumulated data is empty

## What Is Experimental

BufferUtils keeps several capabilities outside the stable root API boundary:

- Reader/source `BytesView` inspection APIs:
  - `BufferReader.peek_slice`
  - `BufferReader.remaining_slice`
  - `MemorySource.peek_remaining`
  - `FileSource.peek_remaining`
- Native file-handle APIs in `ZSeanYves/bufferutils/native`:
  - `NativeFileSource`
  - `NativeFileSink`
  - `NativeBufReader`
  - `NativeBufWriter`
- Native zero-copy research APIs in `ZSeanYves/bufferutils/native`:
  - `NativeByteView`
  - `new_mmap_file_view`
  - `NativeByteView.slice_handle`
  - `NativeByteView` C-side operations

Experimental does not mean hidden. It means the API is available, documented,
and tested, but it is not part of the stable 1.0 compatibility promise.

## Installation

```bash
moon add ZSeanYves/bufferutils
```

Or add it to `moon.mod.json`:

```json
{
  "deps": {
    "ZSeanYves/bufferutils": "0.23.0"
  }
}
```

## Quick Start

### In-memory Reading

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

`new_writer(capacity)` remains available as a compatibility constructor for
fixed-capacity writers, but `new_fixed_writer` and `new_growing_writer` are
the preferred release-facing entry points.

### Memory-backed Streaming

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

`BufReader` and `BufWriter` are streaming-style APIs over concrete memory-backed
types. BufferUtils does not currently expose a stable trait-based custom
source/sink abstraction.

### File Convenience APIs

```moonbit
let writer = new_file_buf_writer(".tmp/out.bin", 4)
writer.write_all([72, 101, 108, 108, 111])
writer.flush()

let reader = new_file_buf_reader(".tmp/out.bin", 4)
let header = reader.read_exact(2)
let rest = reader.read_to_end()
```

`FileSource` and `FileSink` are convenience APIs, not OS-level streaming file
handles. `FileSource` snapshots the file into memory. `FileSink` and
`FileBufWriter` accumulate in memory and materialize to disk on `flush()`.

### Native File-handle Backend Experimental

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
let chunk = source.read_chunk(2)
source.close()
```

The native backend is experimental and native-target only. It requires
`--target native`, a working C toolchain, and explicit `close()`. It does not
replace the stable pure MoonBit file convenience layer.

### NativeByteView Zero-copy Research Experimental

```moonbit
import {
  "ZSeanYves/bufferutils/native" @native,
}

let view = @native.new_mmap_file_view(".tmp/native-view.bin")
let first = view.read_byte_at(0)
let prefix = view.copy_range(0, 8)
let found = view.find_byte((42).to_byte())
let count = view.count_byte((0).to_byte())
let checksum = view.checksum_u64()
let starts = view.starts_with([1, 2, 3])
view.close()
```

`NativeByteView` is an experimental native-only research handle for read-only
mmap-backed access on Unix-like targets. Its owner is a MoonBit-managed
external object with explicit close plus finalizer fallback, not a stable
MoonBit `BytesView` bridge.

It is important to be precise about what this means:

- it is not MoonBit `BytesView`
- it is not a stable zero-copy API
- it requires explicit `close()`
- it has no deterministic automatic destructor contract; finalizer is fallback only
- it does not provide a thread-safety guarantee
- Windows mmap support is currently unsupported

The performance advantage of this path is not that it turns C memory into
MoonBit `BytesView`. It does not. The advantage is that large data can stay in
native or mmap memory while C performs operations such as search, count,
checksums, prefix checks, equality checks, and file transfer. MoonBit receives
small results such as `Int` or `Bool`, or explicitly requests a copy through
`copy_range(...)`. The owner itself is MoonBit-managed, so forgotten close
calls can still be cleaned up by the runtime finalizer.

## Performance Overview

BufferUtils includes a native benchmark runner for local regression tracking:

```bash
moon run src/bench --target native --release
```

The runner prints CSV-style rows:

```text
name,size,bytes,temp_file,mean_us,throughput_mib_per_s,runs
```

The current suite compares:

- pure in-memory buffer operations
- memory-backed streaming APIs
- memory-backed file convenience APIs
- experimental native file-handle APIs
- experimental mmap-backed `NativeByteView` operations

### Benchmark Methodology

The current benchmark runner uses:

- `1` warmup run per case and size
- `5` measured runs per case and size
- arithmetic mean for `mean_us`
- `.tmp/bufferutils-bench/` for temporary benchmark files

It is designed for repeatable local regression tracking, not for publishable
performance claims.

### Local Benchmark Observations

The table below comes from a current local native-target benchmark run on this
repository. These numbers are local observations, not guaranteed throughput.

| Case | 10MB local observation | Interpretation |
|---|---:|---|
| `native_file_source_read_chunk_experimental` | ~2656 MiB/s | Native chunked read path; strongly affected by filesystem cache |
| `native_file_sink_write_flush_experimental` | ~188 MiB/s | Native file sink write + flush |
| `native_buffered_reader_read_to_end_experimental` | ~224 MiB/s | Buffered native reader path |
| `native_buffered_writer_write_flush_experimental` | ~187 MiB/s | Buffered native writer path |
| `native_mmap_view_find_byte_experimental` | ~3363 MiB/s | C-side mmap scan; no large MoonBit array materialization |
| `native_mmap_view_count_byte_experimental` | ~12139 MiB/s | C-side full scan/count; highly cache-sensitive |
| `native_mmap_view_checksum_experimental` | ~922 MiB/s | C-side checksum over mmap-backed memory |
| `native_mmap_view_crc32_experimental` | ~150 MiB/s | C-side CRC32 checksum |
| `native_mmap_view_copy_range_explicit_copy` | ~2827 MiB/s | Explicit copy from native view into MoonBit array |
| `native_mmap_view_copy_to_file_experimental` | ~4046 MiB/s | Native-side transfer to another file path |

### What The Numbers Mean

The benchmark numbers are most useful as:

- regression signals across releases
- relative comparisons between memory-backed, native-file, and mmap-backed paths
- a way to see where work stays in C and where it crosses back into MoonBit

For example:

- `native_mmap_view_read_byte_scan_experimental` mainly measures per-byte FFI overhead
- `find_byte`, `count_byte`, `index_of`, `equals`, `crc32`, and `checksum_u64` better represent C-side zero-copy-style processing
- `copy_range` is an explicit-copy baseline
- `copy_to_file` is a native-side transfer path that avoids materializing a large MoonBit array in MoonBit code

### What The Numbers Do Not Mean

These numbers are not performance guarantees. Native file and mmap benchmarks
are strongly affected by page cache, filesystem cache, CPU, OS, compiler,
MoonBit runtime version, and fixture setup.

Do not read the benchmark as proof that BufferUtils provides:

- stable zero-copy behavior
- stable mmap throughput across machines
- raw disk throughput measurement
- benchmark-proven high performance guarantees

## API Layers

BufferUtils currently has four user-facing layers:

1. Stable root API
   - in-memory readers/writers
   - conversion helpers
   - split helpers
   - memory-backed streaming
   - memory-backed file convenience
2. Experimental root `BytesView` inspection API
   - non-consuming read-only slices over MoonBit-managed memory
3. Experimental native file-handle API
   - `NativeFileSource`, `NativeFileSink`, `NativeBufReader`, `NativeBufWriter`
4. Experimental native zero-copy research API
   - `NativeByteView` and `new_mmap_file_view(...)`

The stable 1.0 boundary is the root pure-MoonBit API. The experimental layers
remain available, but they are not part of that stability promise.

## Error Handling

BufferUtils uses:

- `BufferError` for buffer, capacity, validation, flush, and file I/O errors
- `Utf8DecodeError` for UTF-8 decoding failures

Common cases include:

- `Underflow` when a read goes past available bytes
- `Overflow` when a fixed-capacity writer cannot accept more data
- `InvalidInput` for negative lengths or out-of-range integers
- `Io` or `Flush` for file-related failures

The native package reuses the same `BufferError` family rather than exposing
raw platform-specific errno values as part of the public API.

## Safety And Limitations

- `FileSource` is still a memory-backed snapshot
- `FileSink` is still a memory-backed accumulator plus flush-time overwrite
- experimental reader/source `BytesView` APIs return `BytesView`, but BufferUtils does not guarantee runtime-level shared-storage behavior
- native APIs require `--target native`, a C toolchain, and explicit `close()`
- `NativeByteView` is native-only research API, not MoonBit `BytesView`
- `NativeByteView` is validated on Unix-like native targets; Windows mmap support is currently unsupported
- `NativeByteView` uses a MoonBit-managed external owner with finalizer fallback, but still has no deterministic automatic destructor contract
- the native shared-owner bookkeeping does not provide a thread-safety guarantee
- BufferUtils does not claim stable zero-copy or stable mmap behavior
- there is no async I/O layer in the stable root package

## Documentation

- [docs/API.md](./docs/API.md): API reference and stable/experimental layering
- [docs/DESIGN.md](./docs/DESIGN.md): current architecture and design boundaries
- [docs/BENCHMARK.md](./docs/BENCHMARK.md): benchmark guide, methodology, and caveats
- [docs/VIEW_API.md](./docs/VIEW_API.md): experimental root `BytesView` notes
- [docs/NATIVE_BACKEND.md](./docs/NATIVE_BACKEND.md): experimental native backend overview
- [docs/NATIVE_SAFETY.md](./docs/NATIVE_SAFETY.md): native lifecycle and safety notes
- [docs/MMAP_FEASIBILITY.md](./docs/MMAP_FEASIBILITY.md): mmap feasibility background
- [docs/ZERO_COPY_RESEARCH.md](./docs/ZERO_COPY_RESEARCH.md): `NativeByteView` zero-copy research design notes
- [docs/STREAMING_FEASIBILITY.md](./docs/STREAMING_FEASIBILITY.md): earlier OS-level streaming feasibility study

## Roadmap

- stabilize the root pure-MoonBit API
- keep experimental `BytesView` APIs under observation before any stabilization decision
- continue experimental native backend hardening across more targets and CI environments
- keep `NativeByteView` explicitly research-only until ownership, portability, and concurrency questions are better answered
- continue reduced-copy and benchmark-regression tracking without overstating zero-copy claims

## License

Apache-2.0
