# Native Backend Safety Notes

## Explicit Close Required

The experimental native backend opens real native resources through MoonBit C
FFI.

That means:

- users must call `close()`
- repeated `close()` is safe
- reads and writes after `close()` are errors
- `NativeByteView` operations after `close()` are also errors
- sink `close()` attempts a final flush before releasing the handle
- callers should still use explicit `flush()` when they want a clear
  durability/error boundary before close

There is no stable automatic destructor contract for the general native
file-handle APIs.

## Why Writer/Sink Views Are Still Not Exposed

Even with a native backend, BufferUtils does not expose writer-side or sink-side
borrowed views.

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

`NativeByteView` now uses a MoonBit-managed external owner plus explicit view
state.

MoonBit stores:

- a `NativeByteOwner` abstract object created through
  `moonbit_make_external_object(...)`
- per-view `offset`, `byte_len`, and `closed`

The external owner payload stores:

- `data`
- `len`
- `live_views`
- `closed`
- `mapped`

Important properties of the model:

- `new_mmap_file_view(...)` creates one owner with `live_views == 1`
- `slice_handle(...)` creates child views over the same owner and increments
  `live_views`
- `close()` closes only the current view and decrements `live_views`
- when `live_views` reaches zero, cleanup runs immediately and `munmap()` is
  attempted
- the external-object finalizer is a fallback if callers forget to close a
  surviving view
- `owner_ref_count()` remains a research/debug helper rather than a normal
  usage API

This selects the hybrid model for the current experiment:

- MoonBit-managed owner object
- manual live-view counting
- finalizer fallback for forgotten closes

## Current State Machine

The C-side state machine remains conservative:

- repeated `close()` is short-circuited by the MoonBit layer
- close decrements the current owner's live-view count
- parent close does not invalidate surviving child views
- child close does not invalidate surviving parent or sibling views
- if final `munmap()` fails, the owner is still considered closed and cannot be
  reused
- internal native tests use non-public owner/view live-count probes to verify
  that the final close actually releases the shared owner

The MoonBit finalizer is a fallback, not a deterministic prompt-release API.
Callers still need explicit `close()` when they want predictable release timing.

## slice_handle Status

`slice_handle(...)` is now available, but only as research-only native API.

It is still intentionally not presented as:

- a stable borrowed-lifetime MoonBit feature
- a general-purpose cross-platform mmap abstraction
- a stable zero-copy API guarantee

## Single-thread Assumption

The shared-owner bookkeeping used by this research path is not thread-safe.

Current assumptions:

- single-threaded use
- no shared concurrent access guarantees
- no locking around the shared owner state
- no atomic shared-owner model
- future work would need mutex protection and/or atomic ref-counting before any
  concurrency story could be claimed

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
  shared owner with slice-local bounds

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
- `find_byte(...)`, `count_byte(...)`, `index_of(...)`, `equals(...)`,
  `crc32()`, `checksum_u64()`, and `starts_with(...)` as C-side processing
  helpers
- `copy_to_file(...)` as a native-side transfer that avoids materializing a
  large MoonBit array

## Error Model

The native package reuses the root `BufferError` family through internal bridge
helpers:

- `InvalidInput` for invalid sizes or empty paths
- `Io` for native open/read/write/flush/close/mmap/munmap failures
- `Underflow` for buffered native read APIs like `read_byte()` / `read_exact()`
  when EOF arrives before enough bytes are available
- `InvalidCapacity` for non-positive native buffer capacities

## FFI Basis

The current `NativeByteView` experiment uses a MoonBit-managed external owner
because that matches the documented C FFI direction better than a raw external
pointer owner:

- abstract owner object on the MoonBit side
- payload allocated through `moonbit_make_external_object(...)`
- finalizer as a fallback for foreign resource cleanup

This still does not create a stable public `BytesView` bridge over foreign
memory.

## Buffered Native Semantics

- `NativeBufReader.read_exact(n)` is streaming-style, so an eventual
  `Underflow` may occur after partial consumption
- `NativeBufReader.read_to_end()` drains through repeated chunk refills instead
  of snapshotting the whole file
- `NativeBufWriter.close()` attempts a final flush of its local buffer before
  closing the wrapped sink
- callers who need separate flush-versus-close error handling should still call
  `flush()` explicitly before `close()`
- `slice_handle(...)` uses a MoonBit-managed external owner plus manual
  live-view counting, but still remains research-only and single-threaded

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

It is an experimental file-handle and borrowed-handle research layer, not a
finished no-copy I/O contract.
