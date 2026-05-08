# BufferUtils View / Slice Notes

## Status

`v0.14.0` introduces a small experimental view/slice investigation on reader-side APIs, and `v0.15.0` hardens its tests and documentation.

This is not a zero-copy claim.
It is an experiment around API shape, safety boundaries, and local runtime behavior.

## Experimental APIs

The current experimental APIs are:

- `BufferReader.peek_slice(n)`
- `BufferReader.remaining_slice()`
- `MemorySource.peek_remaining()`
- `FileSource.peek_remaining()`

These APIs are intentionally limited to immutable or snapshot-backed inputs.
They are public today, but still explicitly experimental before `1.0`.

## Why Reader-Side Only

Reader-side data is safer for this experiment because:

- `BufferReader` works over immutable `Bytes`
- `MemorySource` is backed by immutable `Bytes`
- `FileSource` is backed by an immutable in-memory snapshot

By contrast, writer and sink types hold mutable `Array[Byte]` state.
Exposing borrowed views there would make invalidation and aliasing risks much harder to document safely.

## What These APIs Promise

The experimental APIs promise:

- non-consuming peek-style access
- read-only `BytesView` results
- stable bounds checks and error behavior for their current signatures
- no change to existing consuming APIs such as `read_exact()` or `read_remaining()`

They do not promise:

- shared-storage behavior
- zero-copy behavior
- stable zero-copy performance across all targets
- stable long-term public API status without further review before `1.0`

## Runtime Uncertainty

BufferUtils currently uses `Bytes[start:end]` to form these experimental results, and MoonBit types those expressions as `BytesView`.

At the library level, BufferUtils cannot currently guarantee whether MoonBit runtime slicing is:

- a shared-storage view
- a copy
- or implementation-dependent across targets

Because of that uncertainty, the docs intentionally describe these results as experimental `BytesView` APIs rather than guaranteed borrowed no-copy views.

## Experimental Public API Status

The current project status is:

- public and available
- experimental before `1.0`
- not part of the stable copy-returning API family
- not a promise that all MoonBit targets share storage the same way

## Existing Copy-Returning APIs Stay Unchanged

This experiment does not change the semantics of:

- `BufferWriter.flush_to_bytes()`
- `MemorySink.to_bytes()`
- `FileSink.to_bytes()`
- `BufferReader.read_exact()`
- `BufferReader.read_remaining()`
- `MemorySource.read_to_end()`
- `FileSource.read_to_end()`
- `BufReader.read_to_end()`

Those APIs still keep their prior copy-returning or consuming semantics.

## File Snapshot Semantics

`FileSource` remains a memory-backed file snapshot.

That means:

- the file is read into memory when `new_file_source(path)` runs
- later file rewrites do not affect an existing `FileSource`
- `peek_remaining()` is always about the in-memory snapshot, not the live file on disk

## Risks That Prevent Writer Views Today

The main reasons BufferUtils does not expose writer/sink view APIs yet are:

- `Array[Byte]` mutability risk
- `clear()` invalidation risk
- growth and reallocation risk
- ambiguity around how long a borrowed view should remain valid
- flush-time state changes in `FileSink` and `FileBufWriter`

This is why the current view experiment stays on reader/source types only.

## Copy-Returning APIs vs Reduced-Copy Internals vs Experimental Views

- Copy-returning APIs such as `flush_to_bytes()`, `to_bytes()`, `read_remaining()`, and `read_to_end()` keep their existing explicit copy or consuming semantics.
- Reduced-copy internals are implementation details that try to avoid unnecessary intermediate copies and repeated byte pushes.
- Experimental view APIs return `BytesView` for read-only, non-consuming inspection, but they are not marketed or documented as guaranteed zero-copy contracts.

## Next Evaluation Steps

Future work may explore:

- borrowed byte views with explicit lifetime rules
- read-only slice API stabilization
- deeper benchmark comparison for experimental slice APIs
- a true zero-copy investigation when MoonBit runtime guarantees are better understood
