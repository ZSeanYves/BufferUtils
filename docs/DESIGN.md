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

This layer does not expose a trait-based extension point in the stable default package.

### Layer 4: File Convenience Layer

`FileSource`, `FileSink`, `new_file_buf_reader`, and `FileBufWriter` provide file-oriented convenience APIs.

- `FileSource` reads file bytes into memory at construction time.
- `FileSink` accumulates bytes in memory and overwrites the target file on flush.
- `new_file_buf_reader` reuses `BufReader` over a `FileSource` snapshot.
- `FileBufWriter` batches writes before sending them into `FileSink`.

This is deliberately a convenience layer, not a claim of OS-level streaming file-handle support.

### Layer 5: Experimental Native C Backend

`ZSeanYves/bufferutils/native` introduces an experimental native-only package for file-handle based streaming.

- `NativeFileSource` opens a native `FILE*` and reads chunk by chunk.
- `NativeFileSink` opens a native `FILE*`, writes directly, and supports explicit flush/close.
- `NativeBufReader` layers a refill buffer over `NativeFileSource`.
- `NativeBufWriter` layers a small-write buffer over `NativeFileSink`.
- `NativeByteView` adds a native-only research handle for read-only mmap-backed access without pretending to be a stable MoonBit `BytesView`
- the implementation uses MoonBit C FFI plus a small C stub layer
- the C stub uses explicit status codes so MoonBit code does not need to guess from ambiguous return values
- the stable root package does not depend on this backend at runtime

This lets the project explore real file handles without changing the stable semantics of `FileSource` and `FileSink`.

## mmap Feasibility and Research Handle

`v0.21.0` documented mmap feasibility. `v0.23.0` keeps that conclusion about
MoonBit `BytesView`, but adds a narrower native-only research handle:
`NativeByteView`.

The important distinction is:

- the OS-facing mmap side is feasible on Unix-like native targets
- the stable MoonBit-facing borrowed-`BytesView` side is still **not** solved

This branch therefore does **not** export an mmap-backed MoonBit `BytesView`.
Instead it exports a native-only handle with explicit operations such as:

- `read_byte_at(index)`
- `copy_range(start, len)`
- `find_byte(b)`
- `count_byte(b)`
- `index_of(pattern)`
- `equals(data)`
- `crc32()`
- `checksum_u64()`
- `starts_with(data)`
- `copy_to_file(path)`

That keeps the borrowed memory behind an explicit native lifetime boundary
instead of pretending the project already has a safe lifetime-bound
`BytesView`.

The research branch now keeps mmap-backed subviews behind a shared-owner
`NativeByteView` handle model with explicit close and ref-counted native owner
release. This still remains native-only research API, not a stable MoonBit
`BytesView` bridge.

## Reduced-Copy Direction

`v0.12.0` improves several hot paths with reduced-copy techniques while preserving the public API.

The current direction is:

- prefer chunk-oriented append or blit paths over repeated per-byte `push`
- avoid redundant conversions when a memory-backed snapshot can be reused directly
- keep explicit-copy APIs explicit in both implementation and documentation

This does not change the overall design boundary:

- `flush_to_bytes()` still returns a copy
- `to_bytes()` accessors still return copies
- `FileSource` still creates a memory snapshot
- `FileSink` still persists by flush-time overwrite
- repeated flushes without pending data should not change observable output

## View / Slice Experiment

`v0.14.0` explores a narrow view/slice-style API on reader-side immutable data only, and `v0.15.0` hardens its semantics and documentation without expanding the API surface.

The current experiment focuses on:

- `BufferReader.peek_slice(n)`
- `BufferReader.remaining_slice()`
- `MemorySource.peek_remaining()`
- `FileSource.peek_remaining()`

The design constraints are:

- only immutable or snapshot-backed reader/source types participate
- writer and sink internals are not exposed as borrowed views
- existing copy-returning APIs keep their original semantics
- returned `BytesView` values are documented as experimental read-only views, not as guaranteed no-copy contracts

This keeps the experiment small and reversible while the project evaluates how MoonBit runtime slicing behaves in practice.

For now, the project treats these methods as experimental public APIs:

- callable and documented
- safe to rely on for non-consuming inspection and bounds/error semantics
- not positioned as stable zero-copy guarantees before `1.0`

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
- the stable root package does not use OS-level streaming file handles
- `FileSource` is a memory snapshot
- `FileSink` is memory accumulation plus flush-time overwrite
- the experimental native backend is native-target only
- native resources require explicit `close()`
- native sink `close()` attempts a final flush, but explicit `flush()` remains the recommended durability boundary
- native buffered readers and writers are still experimental wrappers over native handles, not stable root APIs
- no stable borrowed `BytesView` bridge from C memory
- `NativeByteView` is still experimental native-only research API
- no append mode for stable root file sinks
- no async I/O
- no benchmark claims yet

## Roadmap

- native backend hardening across more targets and CI environments
- native borrowed-byte view research, gated on safer MoonBit borrowed-byte FFI support
- trait-based custom source/sink abstraction
- borrowed byte views
- read-only slice API stabilization
- true zero-copy investigation
- reduced-copy APIs
- benchmark baseline refinement and historical comparison tooling

## Feasibility Link

See [docs/NATIVE_BACKEND.md](./NATIVE_BACKEND.md), [docs/NATIVE_SAFETY.md](./NATIVE_SAFETY.md), [docs/STREAMING_FEASIBILITY.md](./STREAMING_FEASIBILITY.md), [docs/MMAP_FEASIBILITY.md](./MMAP_FEASIBILITY.md), and [docs/ZERO_COPY_RESEARCH.md](./ZERO_COPY_RESEARCH.md) for the file-handle investigation history and the current experimental native backend direction.
