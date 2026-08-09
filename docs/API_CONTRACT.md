# BufferUtils 0.40 API Contract

All byte ranges validate `offset >= 0`, `length >= 0`, and
`offset + length <= storage.length`. Invalid ranges raise `InvalidInput` (I/O)
or `BufferError::InvalidRange` (memory). A failed read/write never advances a
cursor. A backend-reported count outside the requested range is a
`ContractViolation`.

`read_exact` retries ordinary short reads and `Interrupted`, and reports
`UnexpectedEof` with cumulative progress. `write_all` retries short writes and
`Interrupted`, and reports `WriteZero` with cumulative progress.

`SharedBytes` is an immutable range value. `clone`, `slice`, `prefix`, `suffix`,
and `split_at` do not advance or mutate the source. `SharedBytesSplit::into_parts`
is an explicit tuple allocation boundary; its `prefix` and `suffix` accessors
remain range-only. Consumption is represented by `BytesCursor`, which owns an
independent position. `BytesMut` mutations detach before writing whenever a
frozen or aliased range is reachable. `as_bytes_view`, `BytesMut::freeze`, split,
and buffered pending tails do not copy; `to_array`, `to_bytes`, and `read_array`/
`write_array` are explicit copy boundaries.

`SharedBytes::from_fixed_array` validates and copies the selected range, so
later caller mutation cannot change the immutable value.
`unsafe_adopt_fixed_array` is the explicit zero-copy constructor; its caller
must not mutate the fixed array while any derived shared value is reachable.

`BufRead::fill_buf` and async `AsyncBufRead::fill_buf` borrow internal storage.
The view must not be retained across the next operation on that reader.

Native resources are independently closeable, idempotent, externally owned,
and guarded by their native lock. A close or finalizer invalidates subsequent
operations with `IoError::Closed`.

Native vectored operations borrow each segment and execute at most 64 segments
per syscall. Windows files report scalar capability; callers can inspect the
`is_*_vectored` methods before relying on a single underlying call.
