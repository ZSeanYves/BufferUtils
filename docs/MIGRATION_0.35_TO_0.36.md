# Migrating BufferUtils 0.35 to 0.36

Version 0.36 intentionally breaks the 0.35 source API. There is no runtime
compatibility layer. Update the module requirement to `0.36.0`, then make the
following mechanical changes.

## Read and Write

`Read::read` now receives `FixedArray[Byte], offset, length`. This is the
native-borrowed primary path:

```moonbit
let storage = FixedArray::make(4096, (0).to_byte())
let count = Read::read(reader, storage, 0, storage.length())
```

Use `Read::read_array(reader, array.mut_view())` when an existing `Array` is
more convenient; the adapter explicitly copies through a fixed array.
`Write::write` now receives `Bytes, offset, length`. Use
`Write::write_array(writer, array_view)` for an explicit copying adapter.
`Write::flush` only drains user-space buffering. Native file durability is
requested with `NativeFile::sync_all()` or `sync_data()`.

## Buffers

`SharedBytes` ranges share a `FixedArray` allocation. `as_bytes_view()` is the
zero-copy Core view; `to_array()` and `to_bytes()` are copying conversions.
`BytesMut::with_spare_capacity(minimum, callback)` commits the initialized
length returned by the callback and raises `BufferError::InvalidRange` for an
invalid count. `split`, `try_reclaim`, `try_unsplit`, and `unsplit` replace
ad-hoc prefix manipulation.

## Buffered I/O

`BufWriter::into_parts()` returns a zero-copy `SharedBytes` pending tail.
`BufWriter::finish()` returns `Ok(writer)` or `Err(BufWriterFinishError)`; the
error retains the recoverable buffered writer through `into_inner()`.
`BufReader` adds `peek`, `buffer`, `seek_relative`, `skip_until`, `lines`, and
`split`.

## Native and async

Use `NativeOpenOptions` for read/write/append/create/truncate/create-new
combinations. TCP streams expose `shutdown_read`, `shutdown_write`,
`shutdown_both`, and timeout configuration. Async `fill_buf` returns a borrowed
`ArrayView` invalidated by the next reader operation; async copy reuses one
fixed buffer and `AsyncWrite::shutdown` is available for half-close protocols.
