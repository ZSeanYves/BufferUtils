# Design

## Design Goals

BufferUtils is designed around a small, concrete, honest byte-buffer API.

Current design goals:

- safe byte-buffer operations
- predictable boundary and error behavior
- a stable pure MoonBit root API with low maintenance overhead
- memory-backed streaming abstractions that do not pretend to be full OS-level
  I/O
- file convenience helpers that stay explicit about snapshot and flush
  semantics
- experimental native extensions that do not pollute the stable root package
  boundary

## Non-goals

BufferUtils is not trying to be:

- a stable zero-copy library
- a stable mmap library
- a stable OS-level streaming abstraction in the root package
- a benchmark-proven high-performance guarantee
- a general-purpose trait-based I/O framework

## Architecture Overview

BufferUtils is intentionally layered:

1. Stable pure-MoonBit root package
2. Experimental root `BytesView` inspection APIs
3. Experimental native file-handle backend
4. Experimental `NativeByteView` zero-copy research

Each layer has a different stability and ownership story.

## Stable Root Package

The stable root package is the primary 1.x-facing API:

- `BufferReader`
- `BufferWriter`
- `MemorySource`
- `MemorySink`
- `BufReader`
- `BufWriter`
- `FileSource`
- `FileSink`
- `FileBufWriter`
- `new_file_buf_reader`
- conversion helpers
- split helpers
- `BufferError`

This layer is pure MoonBit and does not require a native target or C toolchain.

## Memory-backed Streaming

`MemorySource`, `MemorySink`, `BufReader`, and `BufWriter` provide
streaming-style APIs over concrete memory-backed types.

This design keeps the stable API easy to understand:

- source/sink types are concrete
- ownership stays inside MoonBit-managed buffers
- bounds and EOF behavior are predictable

Trait-based pluggable backends are intentionally deferred.

## File Convenience Layer

The root file APIs are convenience helpers, not OS-level streaming handles.

### FileSource

`FileSource` reads file bytes into memory at construction time and behaves as a
snapshot.

Consequences:

- later external file changes do not affect an existing `FileSource`
- large files incur snapshot memory cost up front

### FileSink

`FileSink` accumulates bytes in memory and persists them on `flush()`.

Its semantics are:

- flush-time overwrite
- current accumulated bytes are materialized to the file path
- an empty first flush still creates or overwrites an empty file

### FileBufWriter

`FileBufWriter` layers a local write buffer over `FileSink`.

This keeps the root API easy to use for buffered file output without claiming
native file-handle streaming semantics.

## Experimental Native Backend

The native backend explores real file handles through MoonBit C FFI plus a
small C stub layer.

It currently provides:

- `NativeFileSource` for chunked `FILE*` reads
- `NativeFileSink` for direct `FILE*` writes with explicit flush/close
- `NativeBufReader` as a refill buffer over `NativeFileSource`
- `NativeBufWriter` as a local write buffer over `NativeFileSink`

Important boundaries:

- native APIs are experimental
- they are native-target only
- they do not replace `FileSource` / `FileSink`
- they require explicit `close()`
- native sink `close()` attempts a final flush, but explicit `flush()` remains
  the clearer error boundary when callers need to distinguish flush and close

## Experimental NativeByteView Research

`NativeByteView` is a narrower research path over read-only mmap-backed native
memory.

Its design goal is not “turn C memory into MoonBit `BytesView`”. Its goal is:

- keep large data in native memory
- expose an explicit handle with bounds checks
- provide C-side operations that avoid full MoonBit array materialization
- keep ownership and invalidation explicit

The current implementation uses a MoonBit-managed external owner object plus:

- explicit view state
- manual live-view counting
- finalizer fallback

This lets BufferUtils explore zero-copy-style processing without overstating
what MoonBit currently supports.

## Copy / Reduced-copy / Zero-copy Boundaries

The design intentionally keeps copy boundaries explicit.

Stable root API:

- `flush_to_bytes()` returns a copy
- `MemorySink.to_bytes()` returns a copy
- `FileSink.to_bytes()` returns a copy
- `FileSource` is a full-memory snapshot

Experimental root `BytesView` APIs:

- return MoonBit `BytesView`
- are still experimental
- do not claim runtime-level zero-copy guarantees

Experimental `NativeByteView` API:

- is a native-only handle
- is not MoonBit `BytesView`
- keeps ownership in a MoonBit-managed external owner object
- uses `copy_range(...)` as the explicit-copy boundary
- uses `copy_to_file(...)` as native-side transfer

Reduced-copy internal optimizations are implementation details, not stable API
claims.

## Error Model

BufferUtils uses concrete error types with conservative semantics.

### Stable Root Package

- `Overflow`: fixed-capacity write exceeded capacity
- `Underflow`: read requested more bytes than available
- `InvalidCapacity`: constructor received a non-positive capacity
- `InvalidInput`: caller supplied an invalid count or value
- `Io`: file or native operation failed
- `Flush`: memory-backed file sink flush failed

### Experimental Native Package

The native package reuses the same `BufferError` family instead of exposing
platform-specific errno details as part of the public API.

## Ownership Model

Stable root package:

- ownership lives in MoonBit-managed buffers
- file convenience APIs either snapshot into memory or accumulate in memory

Experimental `NativeByteView`:

- the owner is a MoonBit-managed external object
- views carry `offset`, `byte_len`, and `closed`
- child slices share the same owner
- explicit `close()` is still required
- finalizer fallback exists, but it is not a deterministic prompt-release
  contract

## Why Trait-based Source / Sink Is Deferred

Trait-based custom backends remain deferred because:

- they would enlarge the stable root API surface before 1.0
- the current concrete types already explain implemented behavior clearly
- keeping the surface small makes docs and behavior easier to keep aligned

## Why Stable Zero-copy Is Not Claimed

BufferUtils does not claim stable zero-copy because:

- stable root file APIs are still memory-backed
- copy-returning APIs are still intentionally copy-returning
- reader/source `BytesView` APIs are experimental only
- there is still no stable public `C memory -> MoonBit BytesView` bridge
- `NativeByteView` remains explicit-close native research API

The native research path can achieve zero-copy-style processing for supported
C-side operations, but that is not the same as a stable library-wide zero-copy
contract.

## 1.0 Stability Boundary

BufferUtils 1.x stabilizes the root pure MoonBit API.

It does not stabilize:

- experimental reader/source `BytesView` APIs
- experimental native file-handle APIs
- experimental `NativeByteView` zero-copy research APIs
- stable mmap behavior
- stable foreign-memory-backed MoonBit `BytesView`

That boundary is intentional. It allows the root byte-buffer library to remain
small and stable while experimental native work continues separately.
