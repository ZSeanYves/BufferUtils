# BufferUtils Design Notes

## Design Goals

- safe byte-buffer operations
- predictable error behavior
- a small concrete public API that is easy to maintain
- memory-backed streaming-style APIs without pretending to be full OS-level I/O
- file convenience helpers that stay honest about their limits

## Layered Architecture

### Layer 1: Low-Level Buffers

`BufferReader` and `BufferWriter` are the most direct APIs.

- `BufferReader` is a cursor over immutable `Bytes`.
- `BufferWriter` is an in-memory accumulator with fixed or growing capacity behavior.

This layer is intentionally explicit and close to raw byte manipulation.

### Layer 2: Growing Writer Behavior

`new_growing_writer` extends the low-level writer model with automatic capacity growth while preserving the fixed-capacity option.

This keeps predictable protocol-style writing available while still supporting unknown output sizes.

### Layer 3: Memory Streaming

`MemorySource`, `MemorySink`, `BufReader`, and `BufWriter` provide streaming-style behavior over concrete memory-backed types.

- `MemorySource` and `MemorySink` are the backing storage types.
- `BufReader` batches refills from `MemorySource`.
- `BufWriter` batches flushes into `MemorySink`.

This layer does not expose a trait-based extension point in `v0.10.0`.

### Layer 4: File Convenience Layer

`FileSource`, `FileSink`, `new_file_buf_reader`, and `FileBufWriter` provide file-oriented convenience APIs.

- `FileSource` reads file bytes into memory at construction time.
- `FileSink` accumulates bytes in memory and overwrites the target file on flush.
- `new_file_buf_reader` reuses `BufReader` over a `FileSource` snapshot.
- `FileBufWriter` batches writes before sending them into `FileSink`.

This is deliberately a convenience layer, not a claim of OS-level streaming file-handle support.

## API Narrowing Principles

`v0.10.0` narrows the public API in preparation for `1.0`.

The rules are:

- constructors use `new_*`
- behavior methods live on concrete types
- standalone helpers are limited to conversion and split utilities
- compatibility APIs should be few and clearly documented
- internal helpers should not be public just to make the surface feel larger

This release removes redundant aliases and keeps the public surface focused on APIs with a clear user-facing purpose.

## Concrete Types Over Traits

BufferUtils intentionally remains concrete-type based for `1.0`.

Why trait-based custom backends are deferred:

- MoonBit trait integration would force a larger public redesign right before `1.0`
- the current concrete types already cover the implemented behavior clearly
- avoiding half-finished abstraction keeps docs and behavior aligned

Trait-based custom source/sink abstraction stays on the roadmap rather than being rushed into the release surface.

## Current Limitations

- not zero-copy
- not OS-level streaming file handles
- `FileSource` is a memory snapshot
- `FileSink` is memory accumulation plus flush-time overwrite
- no append mode for file sinks
- no async I/O
- no benchmark claims yet

## Roadmap

- trait-based custom source/sink abstraction
- OS-level streaming file handles
- append mode for `FileSink`
- reduced-copy APIs
- benchmarks
