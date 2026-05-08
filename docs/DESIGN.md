# Design

## Design Goals

BufferUtils is designed around a small, concrete, honest byte-buffer API.

Current design goals:

- safe byte-buffer operations
- predictable boundary and error behavior
- a stable pure MoonBit root API with low maintenance overhead
- memory-backed streaming abstractions that do not pretend to be full OS-level I/O
- file convenience helpers that stay explicit about snapshot and flush semantics
- experimental native extensions that do not pollute the stable root package boundary

## API Layers

BufferUtils is intentionally layered.

### Stable Root Package

The stable root package is the primary 1.0-facing API:

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

### Experimental Root Package

The root package also contains a small experimental `BytesView` inspection
layer:

- `BufferReader.peek_slice`
- `BufferReader.remaining_slice`
- `MemorySource.peek_remaining`
- `FileSource.peek_remaining`

These APIs return MoonBit `BytesView`, but BufferUtils does not promise
runtime-level shared-storage or stable zero-copy behavior.

### Experimental Native Backend

`ZSeanYves/bufferutils/native` is a separate experimental package for native
file-handle APIs:

- `NativeFileSource`
- `NativeFileSink`
- `NativeBufReader`
- `NativeBufWriter`

This layer requires `--target native`, a C toolchain, and explicit close.

### Experimental NativeByteView Research

The same native package also contains experimental `NativeByteView` research:

- `new_mmap_file_view`
- `NativeByteView`
- `slice_handle(...)`
- C-side processing operations

This is not part of the stable root API and is not presented as stable
zero-copy.

The current implementation uses a MoonBit-managed external owner object plus
explicit view state, manual live-view counting, and finalizer fallback.

## Stable Root Package

### Low-level Buffers

`BufferReader` and `BufferWriter` provide direct in-memory byte manipulation.

- `BufferReader` is a cursor over immutable `Bytes`
- `BufferWriter` is an in-memory accumulator with fixed or growing behavior

This layer is intentionally explicit and close to raw byte handling.

### Growing Writers

`new_growing_writer(...)` extends the low-level writer model with automatic
capacity growth while preserving the fixed-capacity path.

This allows both:

- protocol-style fixed-capacity writing
- unknown-size output accumulation

### Memory-backed Streaming

`MemorySource`, `MemorySink`, `BufReader`, and `BufWriter` provide
streaming-style APIs over concrete memory-backed types.

This is intentionally not a trait-based pluggable backend design in 1.0.

## Memory-backed File Convenience Layer

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

This lets BufferUtils explore zero-copy-style processing without overstating
what MoonBit currently supports.

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

## Copy And Ownership Semantics

The design intentionally keeps copy boundaries explicit.

Stable root API:

- `flush_to_bytes()` returns a copy
- `MemorySink.to_bytes()` returns a copy
- `FileSink.to_bytes()` returns a copy
- `FileSource` is a full-memory snapshot

Experimental root `BytesView` API:

- returns MoonBit `BytesView`
- is still experimental
- does not claim runtime-level zero-copy guarantees

Experimental `NativeByteView` API:

- is a native-only handle
- is not MoonBit `BytesView`
- keeps ownership in a MoonBit-managed external owner object
- uses `copy_range(...)` as the explicit-copy boundary
- uses `copy_to_file(...)` as native-side transfer

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

BufferUtils 1.0 stabilizes the root pure MoonBit API.

It does **not** stabilize:

- experimental reader/source `BytesView` APIs
- experimental native file-handle APIs
- experimental `NativeByteView` zero-copy research APIs
- stable mmap behavior
- stable foreign-memory-backed MoonBit `BytesView`

That boundary is intentional. It allows the root byte-buffer library to remain
small and stable while experimental native work continues separately.
