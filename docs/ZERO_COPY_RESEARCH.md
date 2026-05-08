# Zero-copy Research

## Goal

This branch investigates what "true zero-copy" could realistically mean for
BufferUtils without rewriting the stable pure MoonBit root package.

The focus is native-target only:

- experimental C-backed borrowed-byte access
- read-only mmap file views
- C-side operations that avoid copying file contents back into MoonBit

This document does **not** claim that BufferUtils already exposes a stable
zero-copy API.

## What Zero-copy Means Here

For this research branch, "zero-copy" means trying to avoid copying file data
into owned MoonBit `Bytes` or `Array[Byte]` when the caller only needs:

- indexed byte reads
- explicit bounded copies
- C-side scanning or prefix checks
- C-side checksum-style processing

That is different from:

- the stable root package's copy-returning APIs
- the existing reduced-copy internal optimizations
- a stable public `BytesView` bridge over foreign memory

## What Is Possible Today

### BytesView over MoonBit Bytes

BufferUtils already exposes experimental reader/source-side `BytesView` APIs
over MoonBit-managed memory:

- `BufferReader.peek_slice`
- `BufferReader.remaining_slice`
- `MemorySource.peek_remaining`
- `FileSource.peek_remaining`

Those are still experimental and are not presented as stable zero-copy
contracts.

### Native FILE* Streaming

`ZSeanYves/bufferutils/native` already provides experimental `FILE*`-based I/O:

- `NativeFileSource`
- `NativeFileSink`
- `NativeBufReader`
- `NativeBufWriter`

These APIs avoid root-package snapshots, but they still materialize chunk data
as owned MoonBit `Bytes` / `Array[Byte]`.

### NativeByteView Handle

`v0.23.0` adds a new experimental native-only research type:

- `NativeByteView`
- `new_mmap_file_view(path)`

`NativeByteView` does **not** pretend to be a MoonBit `BytesView`. Instead, it
holds a native read-only mapping handle and exposes explicit operations:

- `len()`
- `is_closed()`
- `owner_ref_count()` as a research/debug helper
- `slice_handle(start, len)`
- `read_byte_at(index)`
- `copy_range(start, len)` as an explicit-copy boundary
- `find_byte(b)`
- `count_byte(b)`
- `index_of(pattern)`
- `equals(data)`
- `crc32()`
- `checksum_u64()`
- `starts_with(data)`
- `copy_to_file(path)`
- `close()`

This lets the project explore borrowed native memory access without pretending
that MoonBit currently supports a stable foreign-memory `BytesView` bridge.

Important boundaries:

- `NativeByteView` is not an ordinary MoonBit `Bytes`
- it is not a MoonBit `BytesView`
- `copy_range(...)` is the explicit-copy escape hatch
- `read_byte_at(...)` may be expensive for full scans because each call crosses the MoonBit/C FFI boundary

### mmap Read-only Handle

The current prototype uses read-only mmap on Unix-like native targets:

- `open`
- `fstat`
- `mmap(PROT_READ, MAP_PRIVATE)`
- `munmap`
- `close`

This prototype is:

- experimental
- native-target only
- Unix-like only
- read-only only
- explicit-close only
- no Windows support
- no writable mappings

### C-side Operations

The most credible zero-copy-like benefit in this branch comes from C-side
operations that inspect mmap-backed memory and return only small results:

- `find_byte`
- `count_byte`
- `index_of`
- `equals`
- `crc32`
- `checksum_u64`
- `starts_with`
- `copy_to_file`

These avoid copying the whole file into MoonBit just to answer a query.

## What Is Not Possible Yet

### Stable C Memory -> BytesView Bridge

Current MoonBit public C FFI exposes owned-byte constructors such as:

- `moonbit_make_bytes`
- `moonbit_make_bytes_raw`

But it does not expose a stable public way to construct MoonBit `BytesView`
directly from arbitrary foreign memory.

The builtin `%bytesview.make` path exists internally, but this branch does not
use undocumented runtime hooks as a stable implementation strategy.

### Safe Lifetime-bound mmap BytesView

Without a supported borrowed-byte bridge, the project cannot safely expose:

- a MoonBit `BytesView` that points at mmap memory
- documented invalidation after `close()` / `munmap()`
- a guarantee that old views cannot outlive their mapping

### Writer / Sink Borrowed View

This branch still does not expose writer-side or sink-side borrowed views.
Those remain riskier because of:

- mutation
- growth
- flush state transitions
- close invalidation

## Prototype APIs

Experimental native-only research APIs in this branch:

```moonbit
new_mmap_file_view(path : String) -> NativeByteView raise BufferError

NativeByteView.len() -> Int
NativeByteView.is_closed() -> Bool
NativeByteView.owner_ref_count() -> Int raise BufferError
NativeByteView.slice_handle(start : Int, len : Int) -> NativeByteView raise BufferError
NativeByteView.read_byte_at(index : Int) -> Byte raise BufferError
NativeByteView.copy_range(start : Int, len : Int) -> Array[Byte] raise BufferError
NativeByteView.find_byte(b : Byte) -> Int raise BufferError
NativeByteView.count_byte(b : Byte) -> Int raise BufferError
NativeByteView.index_of(data : Array[Byte]) -> Int raise BufferError
NativeByteView.equals(data : Array[Byte]) -> Bool raise BufferError
NativeByteView.crc32() -> Int raise BufferError
NativeByteView.checksum_u64() -> UInt64 raise BufferError
NativeByteView.starts_with(data : Array[Byte]) -> Bool raise BufferError
NativeByteView.copy_to_file(path : String) -> Unit raise BufferError
NativeByteView.close() -> Unit raise BufferError
```

These APIs belong to `ZSeanYves/bufferutils/native`, not the stable root
package.

`owner_ref_count()` is intentionally kept as a research/debug helper. It is
useful for lifecycle tests and admission review, but it is not part of the
recommended quick-usage path for `NativeByteView`.

## Safety Model

The current safety model is explicit and conservative:

- the mapping is valid only until `close()`
- repeated `close()` is safe
- after `close()`, later operations raise `BufferError::Io`
- out-of-bounds reads map to `BufferError::Underflow`
- invalid arguments map to `BufferError::InvalidInput`
- `slice_handle(...)` can keep child views alive after a parent handle is closed
  because the native owner remains alive until the last child closes
- external file truncate or rewrite after mapping is outside the safety contract
- the branch still does not try to expose borrowed MoonBit `BytesView` over that
  shared native owner

This is why the prototype stays as a handle-based API instead of a public
MoonBit `BytesView`.

## NativeByteView Ownership Model

The current owner model is explicit and split into owners and views:

- MoonBit code stores a `NativeByteView` value with:
  - `handle_id`
  - `byte_len`
  - `closed`
- those fields are intentionally private in the source package and are not part
  of the intended supported API surface
- the actual mmap-backed memory is owned by a C-side `NativeByteOwner`
- each MoonBit-visible view corresponds to a C-side `NativeByteViewEntry`
- `slice_handle(...)` creates child views that point at the same owner with a
  different `offset` / `len` window
- `close()` removes only the current view entry; the owner is released only
  when its `ref_count` reaches zero

The important owner split is:

- MoonBit `NativeByteView`
  - `handle_id`
  - `byte_len`
  - `closed`
- C owner registry entry
  - `id`
  - `data`
  - `len`
  - `ref_count`
  - `closed`
  - `mapped`
- C view registry entry
  - `id`
  - `owner_id`
  - `offset`
  - `len`
  - `closed`

The real owner of the mapped memory is the C owner registry entry, not the
MoonBit value.

The intended API surface is:

- `new_mmap_file_view(...)`
- documented `NativeByteView` methods

Users must not manually construct or mutate `NativeByteView` values.

## State Transition

The lifecycle is now intentionally split between owner and view state:

```text
open / mmap success
    -> owner(ref_count = 1) + root view
slice_handle(...)
    -> owner(ref_count += 1) + child view
close(view)
    -> remove current view entry
    -> owner(ref_count -= 1)
owner ref_count == 0
    -> munmap + free owner
after-close operation on a closed view
    -> error
```

Important notes:

- `close()` is idempotent at the MoonBit layer
- a successful close removes only the current view entry
- parent close does not invalidate already-created child views
- a failed final `munmap()` / close still leaves the owner logically closed
- repeated close does not double `munmap()` because owner release only happens
  on the final ref-count transition to zero
- operations check the MoonBit-side open state before calling into C
- internal native tests additionally verify final owner/view release through
  non-public debug counters instead of widening the documented research API

## Single-thread Assumption

The current mmap registry is not thread-safe.

This research backend assumes single-threaded use:

- no lock-protected registry
- no atomic reference counting
- no concurrency guarantee across multiple threads
- future work would need mutexes and/or atomic ref-count updates before sharing this model across threads

## Monotonic ID Allocation

Native mmap owners and views use monotonic native IDs and do not reuse them.

This branch now guards those counters against exhaustion. If a very long-running
process were ever to exhaust the available owner/view ID space, new native mmap
view creation would fail and the backend would report an explicit native error
instead of silently wrapping identifiers.

That limitation is acceptable for research, but it is a real admission
criterion if this work ever moves toward a broader experimental module.

## slice_handle Status

`slice_handle(...)` is now implemented, but only as research-only native API.

What it gives this branch:

- slice-local bounds over the same mmap-backed memory
- parent/child independent close semantics
- shared owner release only after the final close

What it still does **not** give:

- a MoonBit borrowed-lifetime type
- a stable public zero-copy contract
- thread-safe shared ownership
- Windows portability

## Merge Criteria

If this work ever leaves the research branch, the minimum safety bar should be:

- ownership and explicit-close rules are documented clearly
- close / after-close / double-close tests are complete
- C-side handle invalidation is explicit and repeatable
- `slice_handle(...)` keeps using the documented shared-owner/ref-count model
- docs keep stating that `NativeByteView` is not MoonBit `BytesView`
- docs keep stating that this is not a stable zero-copy guarantee
- Unix-like-only and no-Windows constraints remain explicit
- benchmark notes remain local observations rather than performance promises
- single-thread assumptions remain documented until a real concurrency story exists

## Benchmark Caveats

The native benchmark now includes experimental mmap research cases:

- `native_mmap_view_read_byte_scan_experimental`
- `native_mmap_view_find_byte_experimental`
- `native_mmap_view_count_byte_experimental`
- `native_mmap_view_index_of_experimental`
- `native_mmap_view_equals_experimental`
- `native_mmap_view_crc32_experimental`
- `native_mmap_view_checksum_experimental`
- `native_mmap_view_copy_range_explicit_copy`
- `native_mmap_view_copy_to_file_experimental`
- `native_mmap_view_slice_count_byte_experimental`
- `native_mmap_view_slice_crc32_experimental`
- `native_mmap_view_slice_copy_range_explicit_copy`

These numbers must be read carefully:

- `read_byte_scan` mainly measures MoonBit-to-C per-byte FFI overhead
- `find_byte`, `count_byte`, `index_of`, `equals`, `crc32`, and `checksum_u64` are better indicators of C-side zero-copy-style work
- `copy_range` is an explicit-copy baseline, not a borrowed-view API
- `copy_to_file` is a native-side transfer path that still avoids MoonBit large-array materialization
- the `slice_*` cases additionally exercise the shared-owner/ref-count path by
  closing the root view before operating on the child slice
- filesystem cache and page-fault behavior can dominate results
- none of these results prove stable zero-copy semantics

## Recommendation for 1.0

Recommendation for the stable `1.0` line:

- keep the root package unchanged
- keep `BytesView` APIs experimental
- keep the native backend experimental
- do not merge this branch into a stable release as a zero-copy promise

Recommendation for follow-up research:

- keep this work on a research branch
- continue only if native-only borrowed-handle workflows prove useful
- wait for safer MoonBit support before attempting a public foreign-memory
  `BytesView` bridge

## Merge Decision Matrix

### keep branch

Use this when:

- the work is still best described as research-only
- lifetime safety still depends on explicit close plus branch-local discipline
- Windows support is still absent
- there is still no stable C-memory-to-`BytesView` bridge

### merge as experimental native module

Use this only if:

- docs fully explain ownership, close, and after-close semantics
- tests cover the key lifecycle and correctness boundaries
- the API surface is small and intentionally frozen
- users are unlikely to confuse it with a stable zero-copy root API

### discard

Use this if:

- mmap behavior proves too fragile to explain safely
- test stability becomes poor
- the maintenance cost is higher than the research value
