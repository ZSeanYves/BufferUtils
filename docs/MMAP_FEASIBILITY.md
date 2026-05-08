# mmap Feasibility

## Motivation

The native backend already provides experimental file-handle style I/O through
`NativeFileSource`, `NativeFileSink`, `NativeBufReader`, and
`NativeBufWriter`.

The next obvious reduced-copy investigation is a read-only file mapping path:

- avoid reading the whole file into an owned MoonBit `Bytes` snapshot
- avoid repeated chunk copies for large sequential read scenarios
- explore whether a file-backed read-only view can fit the current API model

## Scope

This study is intentionally narrow:

- read-only mappings only
- experimental native backend only
- native target only
- no writable mmap
- no resizable mmap
- no stable root-package API
- no stable zero-copy claim

## Earlier Feasibility Conclusion

The original feasibility work found that the OS-facing side was not the real
blocker.

The real blocker was the MoonBit-facing side:

- there was no stable public `C memory -> MoonBit BytesView` bridge
- lifetime and invalidation around `close()` / `munmap()` could not be expressed
  through a stable public `BytesView` API

## Current Project Status

The project no longer stops at documented-only feasibility.

It now implements mmap-backed native research through:

- `new_mmap_file_view(path)`
- `NativeByteView`

This is a native-only borrowed handle, not a MoonBit `BytesView`.

## Why NativeByteView Exists Instead of MoonBit BytesView

According to the current MoonBit implementation model:

- `BytesView` is built around `Bytes + start + len`
- `BytesView::make(...)` takes `Bytes`, not an arbitrary foreign C pointer
- MoonBit exposes `moonbit_make_external_object(...)` for external owner
  payloads, but not a stable public constructor for a borrowed `BytesView`
  over arbitrary C memory

That means BufferUtils can reliably:

- map a file region in C
- own and unmap that region in C
- wrap the owner payload in a MoonBit-managed external object
- expose explicit native operations over that memory

But it still cannot safely and publicly:

- expose that mapped region as a stable MoonBit `BytesView`
- tie a public `BytesView` lifetime to `munmap()` / `close()`

## External Owner Impact

The external-object owner model improves native owner management:

- owner lifetime is attached to a MoonBit-managed external object
- explicit close still provides prompt cleanup when the last view closes
- finalizer provides fallback cleanup for forgotten closes

This improves native resource ownership.

It does not create a stable MoonBit `BytesView` bridge.

## Recommendation

Recommendation for now:

- keep the stable root file APIs memory-backed
- keep the experimental native file-handle backend separate from the root
  package
- keep mmap on the research path through `NativeByteView`
- continue to document clearly that `NativeByteView` is not MoonBit `BytesView`
