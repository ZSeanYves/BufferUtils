# Native Backend Safety Notes

## Explicit Close Required

The experimental native backend opens real `FILE*` handles through C FFI.

That means:

- users must call `close()`
- repeated `close()` is safe
- reads and writes after `close()` should be treated as errors
- `NativeByteView` operations after `close()` should also be treated as errors
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

## Why Stable mmap Views Are Still Deferred

`v0.23.0` adds an experimental native-only `NativeByteView` handle for read-only
mmap research, but it still does not export a stable MoonBit `BytesView` bridge.

The core issue is lifetime safety:

- mmap memory must stay valid while a view exists
- explicit `close()` / `munmap()` would invalidate that memory
- MoonBit's current public C FFI surface does not provide a stable way to
  construct a lifetime-aware public `BytesView` directly from arbitrary external
  memory

So the project uses a more conservative research shape:

- keep the borrowed native memory behind `NativeByteView`
- expose explicit operations and explicit-copy boundaries
- avoid pretending it already has a stable lifetime-bound MoonBit view contract
- keep the current prototype Unix-like native only
- leave Windows unsupported for now

## NativeByteView Ownership Model

`NativeByteView` now uses an explicit shared-owner model:

- MoonBit stores the logical handle state: `handle_id`, `byte_len`, and `closed`
- C stores:
  - a native owner registry with `data`, `len`, `ref_count`, `closed`, and `mapped`
  - a native view registry with `owner_id`, `offset`, `len`, and `closed`
- `new_mmap_file_view(...)` creates one owner plus one root view
- `slice_handle(...)` creates child views that share the same owner and increment
  its ref-count
- `close()` removes only the current view handle, then decrements the shared
  owner's ref-count
- the owner is released and `munmap()` runs only when the ref-count reaches zero
- `owner_ref_count()` remains a research/debug helper rather than a normal usage API

The current C-side state machine remains conservative:

- repeated `close()` is short-circuited by the MoonBit layer
- close removes the current view entry from the registry
- parent close does not invalidate surviving child views
- child close does not invalidate surviving parent or sibling views
- if final `munmap()` fails, the owner is still considered closed and cannot be reused
- owner/view identifiers are monotonic and not reused; the research backend now guards against ID exhaustion instead of silently wrapping IDs
- internal native tests use non-public owner/view live-count probes to verify
  that the final close actually releases the shared owner

## slice_handle Status

`slice_handle(...)` is now available, but only as research-only native API.

It is still intentionally not presented as:

- a stable borrowed-lifetime MoonBit feature
- a general-purpose cross-platform mmap abstraction
- a stable zero-copy API guarantee

## Single-thread Assumption

The mmap registry used by this research path is not thread-safe.

Current assumptions:

- single-threaded use
- no shared concurrent access guarantees
- no locking around the global mmap registry
- no atomic shared-owner model
- future work would need mutex protection and/or atomic ref-counting before any concurrency story could be claimed

## Merge Criteria

Before `NativeByteView` could move from research-only to a broader experimental
surface, the project should at least keep these conditions true:

- documented owner model
- explicit after-close behavior
- complete close / double-close coverage
- no claim that `NativeByteView` is MoonBit `BytesView`
- Unix-like-only limitation stays explicit
- no writable mmap and no stable zero-copy claim

## File Semantics

### Stable Root Package

- `FileSource`: memory snapshot
- `FileSink`: memory accumulation + flush-time overwrite

### Experimental Native Package

- `NativeFileSource`: chunked `FILE*` reads
- `NativeFileSink`: direct `FILE*` writes with explicit flush/close
- `NativeBufReader`: refill buffer over `NativeFileSource`
- `NativeBufWriter`: local write buffer over `NativeFileSink`
- `NativeByteView`: read-only mmap-backed research handle with explicit close
- `NativeByteView.slice_handle(...)`: research-only child handle over the same
  native owner with slice-local bounds

`NativeByteView` is not:

- MoonBit `Bytes`
- MoonBit `BytesView`
- writable mmap

These are intentionally separate semantic models.

The intended `NativeByteView` surface is its constructor plus documented
methods. Users must not manually construct the struct or mutate its internal
fields.

For `NativeByteView`, the research-only operations currently worth keeping are:

- `read_byte_at(...)` for explicit indexed reads
- `copy_range(...)` as the explicit-copy boundary into MoonBit
- `find_byte(...)`, `count_byte(...)`, `index_of(...)`, `equals(...)`, `crc32()`, `checksum_u64()`, and `starts_with(...)` as C-side processing helpers
- `copy_to_file(...)` as a native-side transfer that avoids materializing a large MoonBit array

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
- `slice_handle(...)` uses a native shared-owner/ref-count model, but still
  remains research-only and single-threaded

## Target and Toolchain Caveats

- native backend support currently depends on MoonBit native target builds
- a working C toolchain is required
- portability should be treated as experimental, not guaranteed
- the current mmap research path is Unix-like only and does not support Windows

## No Zero-copy Claim

The native backend does not claim:

- zero-copy
- stable shared-storage MoonBit `BytesView` bridges
- guaranteed throughput

It is a file-handle experiment, not a finished no-copy I/O layer.
