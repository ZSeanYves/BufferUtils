# BufferUtils 1.0 API Contract

## Ownership

`SharedBytes` is immutable shared storage. Cloning, slicing, splitting, and freezing
must not copy payload bytes. `BytesMut` uses copy-on-write whenever a mutable
operation would otherwise mutate storage visible through an immutable or sibling
handle. A conversion to Core `Bytes`, `Array`, or `BytesView` is an explicit
copy boundary unless the API says otherwise.

`MappedBytes` is native-only external read-only storage. Its slices retain the
owner. `close` is idempotent; a finalizer is only a fallback and never the
deterministic release contract.

## I/O progress

An implementation returning an I/O error must not report committed bytes from
the same operation. A short successful return reports the exact committed
count. Helpers accumulate progress from earlier successful operations and
retry only `Interrupted`. A successful zero-byte write is `WriteZero` when data
remains.

## Buffering

`BufReader` exposes only bytes currently owned by its internal buffer. The view
becomes invalid after the next reader operation. `consume(n)` accepts only
`0 <= n <= fill_buf().length()`.

`BufWriter::flush` is the explicit error boundary. After a short write or
flush error, unwritten bytes remain recoverable through `into_parts`. `close`
does not hide a previous flush error and is idempotent.

## Seeking

Seeking discards buffered reader data and flushes buffered writer data before
delegating to the underlying object. `stream_position` reports the logical
position after accounting for unread reader bytes.

## Async cancellation

Progress callbacks run only after the destination has accepted the complete
reported chunk. Cancellation propagates unchanged. Every opened file, socket,
listener, and directory is closed on success, error, and cancellation.
