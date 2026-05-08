# Native Zero-copy Research

## Summary

BufferUtils includes an experimental native-only research subsystem built
around `NativeByteView`.

This research partially achieves zero-copy-style processing by keeping large
file data in native or mmap-backed memory for supported operations. It does
not expose native memory as MoonBit `BytesView`.

The current goal is to explore a safe, explicit, testable native borrowed-handle
model without changing the stable pure MoonBit root API.

## What “Zero-copy” Means Here

In this document, zero-copy means trying to avoid materializing a large owned
MoonBit `Bytes` or `Array[Byte]` when the caller only needs:

- indexed byte reads
- bounded explicit copies
- C-side search and counting
- C-side checksum-style processing
- native-side file transfer

That is different from:

- the stable root package's copy-returning APIs
- reduced-copy internal optimizations
- a stable public MoonBit `BytesView` bridge over foreign memory

## What Is Implemented

### NativeByteView

The current experimental native-only research type is:

- `NativeByteView`
- `new_mmap_file_view(path)`

It is a handle-based API, not a MoonBit borrowed view type.

Supported operations:

- `len()`
- `is_closed()`
- `owner_ref_count()` as a research/debug helper
- `slice_handle(start, len)`
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
- `close()`

### mmap-backed Owner / View Model

The research path currently uses read-only mmap on Unix-like native targets.

The borrowed native memory is kept behind a shared-owner model instead of being
exposed as MoonBit `BytesView`.

### C-side Processing

The most meaningful zero-copy-style benefit in this subsystem comes from
C-side operations that inspect native memory and return only small results:

- `find_byte`
- `count_byte`
- `index_of`
- `equals`
- `crc32`
- `checksum_u64`
- `starts_with`

These avoid copying the full payload back into MoonBit just to answer a query.

### Explicit-copy Boundaries

`copy_range(...)` is intentionally explicit.

It copies a byte range out of native memory into a MoonBit `Array[Byte]`.
That makes the copy boundary visible to callers instead of pretending the
result is borrowed.

### Native-side Transfer

`copy_to_file(...)` copies the mapped region to another file path in the native
layer without first materializing a large MoonBit array.

This is still data movement. It is not a claim that “nothing is copied”. The
important distinction is that the transfer stays in the native layer instead of
round-tripping the payload through MoonBit-owned arrays.

## What Is Not Implemented

### No Stable C Memory -> MoonBit BytesView Bridge

BufferUtils still does not expose a stable public bridge from arbitrary C
memory into MoonBit `BytesView`.

`NativeByteView` is therefore not MoonBit `BytesView`, and this research track
does not use undocumented runtime hooks to fake such a bridge.

### No Writable mmap

The research subsystem is read-only only:

- no writable mappings
- no resizable mappings
- no mutable writer/sink borrowed views

### No Windows Support Yet

The current mmap-backed path is validated on Unix-like native targets only.
Windows mmap support is currently unsupported.

### No Thread-safety Guarantee

The native owner/view registry is not thread-safe.

This subsystem currently assumes single-threaded use and does not provide a
concurrency guarantee.

## Ownership Model

`NativeByteView` uses an explicit owner/view split.

MoonBit-visible `NativeByteView` values hold logical handle state:

- `handle_id`
- `byte_len`
- `closed`

Those fields are intentionally private implementation details and are not part
of the intended supported API surface.

The real native memory owner lives in C:

- `NativeByteOwner`
  - `id`
  - `data`
  - `len`
  - `ref_count`
  - `closed`
  - `mapped`
- `NativeByteViewEntry`
  - `id`
  - `owner_id`
  - `offset`
  - `len`
  - `closed`

Important properties of the model:

- `new_mmap_file_view(...)` creates one owner plus one root view
- `slice_handle(...)` creates child views over the same owner
- child slices increase the owner ref-count
- `close()` removes only the current view entry
- the owner is released only when its ref-count reaches zero

## State Transitions

The lifecycle is intentionally explicit:

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

Operational rules:

- `close()` is idempotent at the MoonBit layer
- parent close does not invalidate already-created child views
- child close does not invalidate surviving parent or sibling views
- if final `munmap()` fails, the owner is still treated as closed and cannot be reused
- operations check open state before crossing into C

## API Reference

Experimental native-only research APIs:

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

Notes:

- `owner_ref_count()` is kept as a research/debug helper
- `read_byte_at(...)` is useful for indexed access and debugging, but full scans
  through this method mainly measure per-byte FFI overhead
- `copy_range(...)` is the explicit-copy boundary
- `copy_to_file(...)` is a native-side transfer path

## Safety Model

The safety story is explicit and conservative:

- the mapping is valid only until `close()`
- repeated `close()` is safe
- after `close()`, later operations raise `BufferError::Io`
- out-of-bounds reads map to `BufferError::Underflow`
- invalid arguments map to `BufferError::InvalidInput`
- external file truncate or rewrite after mapping is outside the safety contract
- this research track still does not try to expose borrowed MoonBit `BytesView`
  over the shared native owner

The current registry also uses monotonic IDs that are not reused. The research
backend now guards those counters against exhaustion instead of silently
wrapping identifiers. Extremely long-running processes that create very large
numbers of owners/views could still hit this guard; that is treated as a
research-backend limitation rather than a stable production guarantee.

## Benchmark Interpretation

The native benchmark suite includes experimental mmap research cases such as:

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

Interpret these results carefully:

- `read_byte_scan` mainly measures MoonBit-to-C per-byte FFI overhead
- `find_byte`, `count_byte`, `index_of`, `equals`, `crc32`, and `checksum_u64`
  are better indicators of C-side zero-copy-style work
- `copy_range` is an explicit-copy baseline
- `copy_to_file` is a native-side transfer path
- `slice_*` cases additionally exercise the shared-owner/ref-count path
- filesystem cache and page-fault behavior can dominate results
- none of these results prove stable zero-copy semantics

## Merge / Stabilization Criteria

If this subsystem ever moves beyond research-only status, the minimum bar
should be:

- ownership and explicit-close rules are documented clearly
- close / after-close / double-close tests remain complete
- C-side handle invalidation stays explicit and repeatable
- `slice_handle(...)` continues to use the documented shared-owner/ref-count model
- docs continue to state that `NativeByteView` is not MoonBit `BytesView`
- docs continue to state that this is not a stable zero-copy guarantee
- Unix-like-only and no-Windows constraints remain explicit
- benchmark notes remain local observations rather than performance promises
- single-thread assumptions remain documented until a real concurrency story exists

Current recommendation:

- keep the root package unchanged
- keep `BytesView` APIs experimental
- keep the native backend experimental
- keep `NativeByteView` explicitly marked as experimental native zero-copy research
- do not present this subsystem as a stable release-time zero-copy promise
