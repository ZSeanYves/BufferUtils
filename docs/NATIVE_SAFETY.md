# Native Safety Notes

## Scope

This document covers the experimental native package:

- native file handles
- buffered native readers and writers
- `NativeByteView` mmap-backed research handles

It does not change the stable root package semantics.

## Native File Handles

The experimental native backend opens real native resources through MoonBit C
FFI.

That means:

- users must call `close()`
- repeated `close()` is safe
- reads and writes after `close()` are errors
- sink `close()` attempts a final flush before releasing the handle
- callers should still use explicit `flush()` when they want a clear
  durability/error boundary before close

There is no stable automatic destructor contract for the general native
file-handle APIs.

## NativeByteView Owner Model

`NativeByteView` uses a MoonBit-managed external owner plus explicit view
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

This is deliberately different from:

- MoonBit `BytesView`
- raw `#external` pointer ownership
- stable foreign-memory-backed view APIs

## Explicit Close

`NativeByteView.close()` closes only the current view.

It does not blindly invalidate every view that shares the same owner.

Current behavior:

- close the current view
- decrement the owner's live-view count
- if the last open view closes, attempt prompt cleanup
- repeated `close()` is safe

Explicit `close()` is still the recommended release path.

## Finalizer Fallback

`NativeByteOwner` is a MoonBit-managed external object, so its payload can be
cleaned through a finalizer if the caller forgets to close surviving views.

Important limits:

- finalizer is a fallback
- finalizer is not a prompt-release guarantee
- callers should still use explicit `close()` for predictable release timing
- finalizer and explicit close are designed to avoid double `munmap()`

## Slice Lifetime

`slice_handle(...)` creates child views over the same owner.

Properties:

- child slices do not duplicate mmap memory
- child slices use slice-local bounds
- parent close does not invalidate surviving child views
- child close does not invalidate surviving parent or sibling views
- the shared owner is released only when the last open view closes

## After-close Behavior

After `close()` on a given view:

- that view must not be used again
- later operations raise `BufferError::Io`
- repeated close remains safe

If final cleanup fails:

- the owner is still treated as closed
- the mapping is not considered reusable

## Error Mapping

The native package reuses the root `BufferError` family through bridge helpers:

- `InvalidInput` for invalid sizes, empty paths, and invalid arguments
- `Io` for native open/read/write/flush/close/mmap/munmap failures
- `Underflow` for buffered native read APIs when EOF arrives before enough
  bytes are available
- `InvalidCapacity` for non-positive native buffer capacities

Platform-specific errno values are not exposed as part of the public API.

## Thread-safety

The shared-owner bookkeeping used by this research path is not thread-safe.

Current assumptions:

- single-threaded use
- no shared concurrent access guarantees
- no locking around the shared owner state
- no atomic live-view counting

Future work would need mutex protection and/or atomic ref-counting before any
concurrency story could be claimed.

## Platform Support

- native backend support depends on MoonBit native target builds
- a working C toolchain is required
- the current mmap research path is Unix-like only
- Windows mmap support is currently unsupported

## What Users Must Not Assume

Users must not assume:

- that `NativeByteView` is MoonBit `BytesView`
- that a stable public `C memory -> MoonBit BytesView` bridge exists
- that finalizer fallback is equivalent to prompt explicit cleanup
- that thread safety is provided
- that external file truncate or rewrite after mapping is inside the safety
  contract
- that BufferUtils is making a stable zero-copy guarantee
