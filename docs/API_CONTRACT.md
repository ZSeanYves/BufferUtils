# BufferUtils 0.36 API Contract

All byte ranges validate `offset >= 0`, `length >= 0`, and
`offset + length <= storage.length`. Invalid ranges raise `InvalidInput` (I/O)
or `BufferError::InvalidRange` (memory). A failed read/write never advances a
cursor. A backend-reported count outside the requested range is a
`ContractViolation`.

`read_exact` retries ordinary short reads and `Interrupted`, and reports
`UnexpectedEof` with cumulative progress. `write_all` retries short writes and
`Interrupted`, and reports `WriteZero` with cumulative progress.

Shared buffer mutations detach before writing whenever a frozen or aliased
range is reachable. `as_bytes_view`, `BytesMut::freeze`, split, and buffered
pending tails do not copy; `to_array`, `to_bytes`, and `read_array`/
`write_array` are explicit copy boundaries.

`BufRead::fill_buf` and async `AsyncBufRead::fill_buf` borrow internal storage.
The view must not be retained across the next operation on that reader.

Native resources are independently closeable, idempotent, externally owned,
and guarded by their native lock. A close or finalizer invalidates subsequent
operations with `IoError::Closed`.
