# BufferUtils View / Slice Notes

## Status

BufferUtils exposes a small experimental `BytesView` inspection layer on the
root package:

- `BufferReader.peek_slice(n)`
- `BufferReader.remaining_slice()`
- `MemorySource.peek_remaining()`
- `FileSource.peek_remaining()`

These APIs are experimental before 1.x stabilization decisions.

This is not a stable zero-copy claim.

## Scope

These view APIs are limited to MoonBit-managed memory:

- immutable `Bytes`
- immutable `MemorySource` contents
- immutable `FileSource` snapshots

They are intentionally separate from `NativeByteView`.

`NativeByteView` is a native research handle over external mmap/native memory.
The APIs in this document are root-package `BytesView` inspection APIs over
MoonBit-managed memory.

## What These APIs Promise

The experimental APIs promise:

- non-consuming peek-style access
- read-only `BytesView` results
- stable bounds checks and error behavior for their current signatures
- no change to existing consuming APIs such as `read_exact()` or
  `read_remaining()`

They do not promise:

- shared-storage behavior across all targets
- zero-copy behavior
- stable zero-copy performance across all targets
- stable long-term public API status without further review

## Why Reader-side Only

Reader-side data is safer for this experiment because:

- `BufferReader` works over immutable `Bytes`
- `MemorySource` is backed by immutable `Bytes`
- `FileSource` is backed by an immutable in-memory snapshot

By contrast, writer and sink types hold mutable `Array[Byte]` state.
Exposing borrowed views there would make invalidation and aliasing risks much
harder to document safely.

## Runtime Uncertainty

BufferUtils currently uses `Bytes[start:end]` to form these experimental
results, and MoonBit types those expressions as `BytesView`.

At the library level, BufferUtils cannot currently guarantee whether MoonBit
runtime slicing is:

- a shared-storage view
- a copy
- or implementation-dependent across targets

Because of that uncertainty, the docs intentionally describe these results as
experimental `BytesView` APIs rather than guaranteed borrowed no-copy views.

## Copy-returning APIs Stay Unchanged

This experiment does not change the semantics of:

- `BufferWriter.flush_to_bytes()`
- `MemorySink.to_bytes()`
- `FileSink.to_bytes()`
- `BufferReader.read_exact()`
- `BufferReader.read_remaining()`
- `MemorySource.read_to_end()`
- `FileSource.read_to_end()`
- `BufReader.read_to_end()`

Those APIs keep their existing copy-returning or consuming semantics.

## File Snapshot Semantics

`FileSource` remains a memory-backed file snapshot.

That means:

- the file is read into memory when `new_file_source(path)` runs
- later file rewrites do not affect an existing `FileSource`
- `peek_remaining()` is always about the in-memory snapshot, not the live file
  on disk
