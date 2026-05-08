# Native Package

`src/native` contains the experimental native-target backend for BufferUtils.

The stable default package remains pure MoonBit. This package exists to provide
and evaluate native-target-only extensions such as:

- real file-handle reads
- real file-handle writes
- buffered file-handle reads
- buffered file-handle writes
- overwrite and append modes
- explicit flush / close lifecycle
- read-only mmap-backed `NativeByteView` research handles

It is built with MoonBit C FFI plus small C shims for native file-handle and
mmap-backed behavior.

Run native-only tests with:

```bash
moon test -p ZSeanYves/bufferutils/native --target native
```

Run the shared benchmark runner with native cases enabled via:

```bash
moon run src/bench --target native --release
```

## Scope

This package is experimental.

- it requires `--target native`
- it requires a C toolchain
- it does not replace the stable memory-backed file helpers
- it does not change the stable root API

The file-handle layer includes:

- `NativeFileSource`
- `NativeFileSink`
- `NativeBufReader`
- `NativeBufWriter`

The mmap research layer includes:

- `NativeByteView`
- `new_mmap_file_view(...)`

## NativeByteView Research Scope

`NativeByteView` is a native-only research handle over read-only mmap-backed
memory on Unix-like native targets.

It is:

- experimental
- explicit-close based
- not MoonBit `BytesView`
- not a stable zero-copy guarantee
- not a writable mmap API

The current implementation uses a MoonBit-managed external owner object with a
C payload. That owner keeps the mapped region alive and provides finalizer
fallback if callers forget to close every live view.

`read_byte_at(...)` is useful for explicit indexed access, but large sequential
scans through that method mostly measure per-call FFI overhead. The more
meaningful zero-copy-style research paths are C-side operations such as:

- `find_byte`
- `count_byte`
- `index_of`
- `equals`
- `crc32`
- `checksum_u64`
- `starts_with`
- `copy_to_file(...)`

## Ownership Model

`NativeByteView` is an explicit-close handle, not a lifetime-tracked borrowed
MoonBit view.

- MoonBit stores a managed `NativeByteOwner` external object plus `offset`,
  `byte_len`, and `closed`
- the external owner payload keeps the mmap region alive and carries the live
  view count
- child slices share one owner and raise the owner's live-view count
- `close()` closes only the current view
- the owner is released when its live-view count reaches zero
- repeated `close()` is safe
- if cleanup fails, the view is still treated as closed and cannot be reused
- the owner finalizer is a fallback, not a prompt-release guarantee

`owner_ref_count()` remains available only as a research/debug helper and is
not part of the recommended quick-usage path.

## Safety Notes

- explicit `close()` is still recommended
- the mmap research path assumes single-threaded use
- there is no thread-safety guarantee
- Windows mmap support is not implemented
- the package does not expose a stable public `C memory -> MoonBit BytesView`
  bridge

Read-only mmap investigation notes live in
[../../docs/MMAP_FEASIBILITY.md](../../docs/MMAP_FEASIBILITY.md).
Zero-copy research notes live in
[../../docs/ZERO_COPY_RESEARCH.md](../../docs/ZERO_COPY_RESEARCH.md).
