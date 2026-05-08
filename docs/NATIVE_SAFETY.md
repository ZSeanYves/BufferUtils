# Native Backend Safety Notes

## Explicit Close Required

The experimental native backend opens real `FILE*` handles through C FFI.

That means:

- users must call `close()`
- repeated `close()` is safe
- reads and writes after `close()` should be treated as errors
- sink `close()` attempts a final flush before releasing the handle
- callers should still use explicit `flush()` when they want a clear durability/error boundary before close

There is no stable auto-finalizer contract exposed as part of this backend yet.

## Why Writer/Sink Views Are Still Not Exposed

Even with a native backend, BufferUtils does not expose writer-side or sink-side borrowed views.

Reasons:

- mutable buffers can grow
- flush state changes over time
- close invalidates the underlying native handle
- borrowed view lifetime rules would become much harder to explain correctly

## Why mmap Is Still Deferred

`v0.21.0` studies mmap, but does not export an experimental mmap view API yet.

The core issue is lifetime safety:

- mmap memory must stay valid while a view exists
- explicit `close()` / `munmap()` would invalidate that memory
- MoonBit's current public C FFI surface does not provide a stable way to
  construct a lifetime-aware public `BytesView` directly from arbitrary external
  memory

So the project keeps mmap in documented feasibility-study mode instead of
pretending it already has a safe read-only view contract.

## File Semantics

### Stable Root Package

- `FileSource`: memory snapshot
- `FileSink`: memory accumulation + flush-time overwrite

### Experimental Native Package

- `NativeFileSource`: chunked `FILE*` reads
- `NativeFileSink`: direct `FILE*` writes with explicit flush/close
- `NativeBufReader`: refill buffer over `NativeFileSource`
- `NativeBufWriter`: local write buffer over `NativeFileSink`

These are intentionally separate semantic models.

## Error Model

The native package reuses the root `BufferError` family through internal bridge helpers:

- `InvalidInput` for invalid sizes or empty paths
- `Io` for native open/read/write/flush/close failures
- `Underflow` for buffered native read APIs like `read_byte()` / `read_exact()` when EOF arrives before enough bytes are available
- `InvalidCapacity` for non-positive native buffer capacities

## Buffered Native Semantics

- `NativeBufReader.read_exact(n)` is streaming-style, so an eventual `Underflow` may occur after partial consumption
- `NativeBufReader.read_to_end()` drains through repeated chunk refills instead of snapshotting the whole file
- `NativeBufWriter.close()` attempts a final flush of its local buffer before closing the wrapped sink
- callers who need separate flush-versus-close error handling should still call `flush()` explicitly before `close()`

## Target and Toolchain Caveats

- native backend support currently depends on MoonBit native target builds
- a working C toolchain is required
- portability should be treated as experimental, not guaranteed

## No Zero-copy Claim

The native backend does not claim:

- zero-copy
- exported mmap APIs
- stable shared-storage views
- guaranteed throughput

It is a file-handle experiment, not a finished no-copy I/O layer.
