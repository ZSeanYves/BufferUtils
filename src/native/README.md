# Native Package

`src/native` contains the experimental native-target backend for BufferUtils.

It is built with MoonBit C FFI and a small `FILE*`-based C stub.

The stable default package remains pure MoonBit. This package exists to explore:

- real file-handle reads
- real file-handle writes
- buffered file-handle reads
- buffered file-handle writes
- native-only read-only mmap research handles
- overwrite and append modes
- explicit flush and close behavior
- explicit native lifecycle and error-path handling

Run native-only tests with:

```bash
moon test -p ZSeanYves/bufferutils/native --target native
```

Run the shared benchmark runner with native cases enabled via:

```bash
moon run src/bench --target native --release
```

This package is experimental. It requires explicit `close()`, does not replace
the stable memory-backed file helpers, and now includes a native-only
`NativeByteView` / `new_mmap_file_view(...)` research path for read-only
mmap-backed access on Unix-like native targets. That research path uses a
MoonBit-managed external owner object with explicit close plus finalizer
fallback, not a stable MoonBit `BytesView` bridge.

The mmap research path does not expose a stable MoonBit `BytesView` bridge and
does not claim stable zero-copy behavior.
`read_byte_at(...)` is useful for explicit indexed access, but full scans through
that method mainly measure per-call FFI overhead. The more meaningful
zero-copy-style research paths here are C-side operations like `find_byte`,
`count_byte`, `index_of`, `equals`, `crc32`, `checksum_u64`, `starts_with`, and
`copy_to_file(...)`.

`slice_handle(...)` is now available only as research-only native API. It uses
an explicit shared-owner / ref-count model so parent and child views can close
independently without causing use-after-`munmap`.
`owner_ref_count()` stays available only as a research/debug helper and is not
part of the recommended quick-usage path.

## NativeByteView Ownership Model

`NativeByteView` is an explicit-close handle, not a lifetime-tracked borrowed
MoonBit view.

- MoonBit stores a managed `NativeByteOwner` external object plus `offset`,
  `byte_len`, and `closed`
- the external owner payload keeps the mmap region alive and carries the live
  view count
- child slices share one owner and raise the owner's live-view count
- `close()` closes only the current view, and the owner is released
  when its live-view count reaches zero
- repeated `close()` is safe
- if `munmap()` fails, the view is still treated as closed and cannot be reused
- the owner finalizer is a fallback so forgotten closes still release resources

## Single-thread Assumption

This mmap research path assumes single-threaded use.

- the shared-owner bookkeeping is not thread-safe
- there is no cross-thread safety guarantee
- no locking or atomic ref-counting is provided yet
- future work would need mutexes and/or atomic ref-count updates before this
  could claim any concurrency story

## slice_handle Status

`slice_handle(...)` is intentionally still research-only.

- it is backed by a native shared owner plus ref-counted child views
- it is not a MoonBit borrowed-lifetime feature
- it remains single-threaded and explicit-close only
- it is still not a stable zero-copy contract

## Merge Criteria

This experimental research track should only move closer to broader mainline
experimental status if:

- ownership and close semantics stay clearly documented
- after-close behavior stays fully tested
- `NativeByteView` continues to be described as native-only research API
- docs continue to state that it is not MoonBit `BytesView` and not a stable zero-copy guarantee

Read-only mmap investigation notes live in [../../docs/MMAP_FEASIBILITY.md](../../docs/MMAP_FEASIBILITY.md).
Zero-copy research notes live in [../../docs/ZERO_COPY_RESEARCH.md](../../docs/ZERO_COPY_RESEARCH.md).
