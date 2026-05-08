# Native Zero-copy Research

## Summary

BufferUtils includes an experimental native-only research subsystem built
around `NativeByteView`.

`NativeByteView` partially achieves zero-copy-style processing by avoiding
large MoonBit array materialization for supported C-side operations. It does
not expose native memory as MoonBit `BytesView`.

The current owner model uses a MoonBit-managed external object created through
`moonbit_make_external_object(...)`, combined with explicit view state, manual
live-view counting, and finalizer fallback.

## Terminology

This document uses the following terms:

- `NativeByteOwner`: the MoonBit-managed external owner object
- `NativeByteView`: the public research handle over a subrange of owner-backed
  native memory
- explicit copy: a deliberate transfer from native memory into a MoonBit-owned
  array
- native-side transfer: data movement that stays in the native layer

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

## MoonBit FFI Basis

The current experiment is intentionally aligned with the documented MoonBit C
FFI model:

- the C backend supports native interop through MoonBit FFI
- a plain `#external type` maps to an opaque foreign pointer shape and does not
  give BufferUtils a MoonBit-managed owner lifetime
- an abstract type can instead be backed by a MoonBit-managed object
- `moonbit_make_external_object(finalize, payload_size)` creates that kind of
  MoonBit-managed external object and allows a finalizer to release foreign
  resources stored in the payload
- raw C pointers cannot simply be returned as MoonBit `Bytes` or `String`
  because those values require MoonBit-managed object layout
- this makes an external owner object a good fit for `NativeByteView` owner
  state
- it still does not provide a stable public bridge from arbitrary C memory to
  MoonBit `BytesView`

This is why the research path prefers:

- `C mmap memory -> NativeByteOwner external object -> NativeByteView`

instead of pretending it can safely provide:

- `C mmap memory -> MoonBit BytesView`

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

### MoonBit-managed External Owner

The borrowed native memory is kept behind a shared owner model instead of being
exposed as MoonBit `BytesView`.

That shared owner is a MoonBit-managed external object rather than a raw C
registry owner.

### mmap-backed Memory

The research path currently uses read-only mmap on Unix-like native targets.

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

### Shared Slice Handles

`slice_handle(...)` creates child views over the same owner.

- child views do not duplicate mmap memory
- child views use slice-local bounds
- parent close does not invalidate already-created child views
- child close does not invalidate surviving parent or sibling views

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

### No MoonBit BytesView Bridge

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

The current mmap-backed path is verified on Unix-like native targets only.
Windows mmap support is currently unsupported.

### No Thread-safety Guarantee

The native shared-owner bookkeeping is not thread-safe.

This subsystem currently assumes single-threaded use and does not provide a
concurrency guarantee.

## Ownership Model

`NativeByteView` uses an explicit owner/view split.

MoonBit-visible `NativeByteView` values hold:

- `owner`
- `offset`
- `byte_len`
- `closed`

Those fields are private implementation details and are not part of the
intended supported API surface.

The real native memory owner lives inside a MoonBit-managed external object:

- `NativeByteOwner`
  - `data`
  - `len`
  - `live_views`
  - `closed`
  - `mapped`

Important properties:

- `new_mmap_file_view(...)` creates one owner plus one root view
- `slice_handle(...)` creates child views over the same owner
- child slices increase the owner's live-view count
- `close()` closes only the current view
- the owner is released when its live-view count reaches zero
- the external-object finalizer is a fallback if callers forget to close

## State Transitions

```text
open / mmap success
    -> owner(live_views = 1) + root view
slice_handle(...)
    -> owner(live_views += 1) + child view
close(view)
    -> mark current view closed
    -> owner(live_views -= 1)
owner live_views == 0
    -> munmap + cleanup owner payload
finalizer fallback
    -> munmap + cleanup owner payload if a surviving view was not explicitly closed
after-close operation on a closed view
    -> error
```

Operational rules:

- `close()` is idempotent at the MoonBit layer
- if final `munmap()` fails, the owner is still treated as closed and cannot be
  reused
- operations check open state before crossing into C

## Safety Model

The safety story is explicit and conservative:

- the mapping is valid only while at least one open view still references the
  shared owner
- repeated `close()` is safe
- after `close()`, later operations raise `BufferError::Io`
- out-of-bounds reads map to `BufferError::Underflow`
- invalid arguments map to `BufferError::InvalidInput`
- external file truncate or rewrite after mapping is outside the safety contract
- the owner finalizer is a fallback, not a deterministic prompt-release
  contract

## Performance Model

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

Interpret the results conservatively:

- `read_byte_scan` mainly measures MoonBit-to-C per-byte FFI overhead
- `count_byte`, `find_byte`, `index_of`, `equals`, `crc32`, and
  `checksum_u64` better represent C-side zero-copy-style processing
- `copy_range` is an explicit-copy baseline
- `copy_to_file` is a native-side transfer path
- `slice_*` cases additionally exercise the shared-owner/live-view path
- all native file and mmap results are strongly affected by page cache,
  filesystem cache, page faults, CPU, OS, compiler, and runtime version

The benchmark suite is for local regression tracking, not throughput
guarantees.

## Stabilization Criteria

This research track should only move closer to broader experimental status if:

- ownership and close semantics stay clearly documented
- after-close behavior stays fully tested
- `NativeByteView` continues to be described as native-only research API
- docs continue to state that it is not MoonBit `BytesView`
- docs continue to state that it is not a stable zero-copy guarantee
- Unix-like-only and single-thread assumptions stay explicit
