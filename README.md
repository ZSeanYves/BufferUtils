# BufferUtils

BufferUtils is a byte-buffer utility library for MoonBit.

It provides:

- low-level in-memory readers and writers
- fixed-capacity and auto-growing buffer writers
- memory-backed streaming-style readers and writers
- file convenience APIs for buffered write and buffered read
- UTF-8 conversion and delimiter-based split helpers

BufferUtils is intentionally conservative about its claims:

- it is not zero-copy
- it does not expose OS-level streaming file handles
- it does not make benchmark-proven performance claims

[English](https://github.com/ZSeanYves/BufferUtils/blob/main/README.md) | [简体中文](https://github.com/ZSeanYves/BufferUtils/blob/main/README_zh_CN.md)

## Overview

BufferUtils has four API layers:

1. `BufferReader` and `BufferWriter` for direct in-memory byte work.
2. Growing-writer support on top of the low-level writer.
3. `MemorySource`, `MemorySink`, `BufReader`, and `BufWriter` for streaming-style memory APIs.
4. `FileSource`, `FileSink`, `new_file_buf_reader`, and `FileBufWriter` as file convenience layers.

Standalone example files were removed in `v0.10.0`. Usage snippets now live in this README so the documented surface stays closer to the release-ready API.

## Installation

```bash
moon add ZSeanYves/bufferutils
```

Or add it to `moon.mod.json`:

```json
{
  "deps": {
    "ZSeanYves/bufferutils": "0.10.0"
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

`BufReader` and `BufWriter` are streaming-style APIs over concrete memory-backed types. BufferUtils does not expose a trait-based custom source/sink abstraction in `v0.10.0`.

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

### Convert and Split Utilities

```moonbit
let text = "MoonBit"
let utf8 = string_to_utf8_bytes(text)
let decoded = utf8_bytes_to_string(utf8)

let bytes = ints_to_bytes([65, 66, 67])
let parts = split_bytes(Bytes::from_array([1, 0, 0, 2]), (0).to_byte())
```

`ints_to_bytes` validates the `0..255` byte range. `utf8_bytes_to_string` raises `Utf8DecodeError` on invalid UTF-8 input.

## Public API Surface

The stable public surface is intentionally small:

- low-level: `BufferReader`, `BufferWriter`, `new_fixed_writer`, `new_growing_writer`
- memory streaming: `MemorySource`, `MemorySink`, `BufReader`, `BufWriter`
- file convenience: `FileSource`, `FileSink`, `new_file_buf_reader`, `FileBufWriter`
- utilities: `bytes_to_array`, `array_to_bytes`, `ints_to_bytes`, `string_to_utf8_bytes`, `utf8_bytes_to_string`, `split_bytes`, `split_array_bytes`

The detailed reference lives in [docs/API.md](./docs/API.md).

## API Stability

BufferUtils is approaching `1.0`. The snake_case APIs documented in [docs/API.md](./docs/API.md) are the intended stable public surface for the `1.0` release.

`new_writer(capacity)` is retained as a legacy compatibility constructor for fixed-capacity writers. Additional compatibility wrappers from earlier releases were removed in `v0.10.0` so the release surface is easier to maintain.

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

More detail is in [docs/DESIGN.md](./docs/DESIGN.md).

## Current Limitations

- not zero-copy
- no OS-level streaming file handles
- `FileSource` reads the whole file into memory on construction
- `FileSink` accumulates bytes in memory and overwrites the file on flush
- no async I/O
- no benchmark claims yet

## Roadmap

- trait-based custom source/sink abstraction
- OS-level streaming file handles
- append mode for `FileSink`
- reduced-copy APIs
- benchmarks

## License

Apache-2.0
