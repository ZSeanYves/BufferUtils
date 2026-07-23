# Migrating BufferUtils 0.36 to 0.37

BufferUtils 0.37 is a source-breaking release. Update the module requirement to
`0.37.0`; there is no runtime compatibility layer.

## Checked zero-copy adoption

`SharedBytes::from_fixed_array(data, start, end)` now raises
`BufferError::InvalidRange` when the range is negative, reversed, or outside
the fixed array. The function still adopts storage without copying. After
adoption, callers must treat `data` as immutable for the lifetime of every
shared view.

`BufWriter::into_parts()` and `AsyncBufWriter::into_parts()` now propagate the
same range error. Valid internal cursor ranges remain zero-copy.

## Async shutdown and errors

The default `AsyncWrite::shutdown` flushes the writer. Buffered writers flush
pending bytes before delegating shutdown. TCP adapters perform a real write-half
shutdown. Runtime OS errors are classified as `IoError`; cancellation errors
are re-raised unchanged.

## Native vectored I/O

Native files and TCP streams now implement `read_vectored` and `write_vectored`
with up to 64 borrowed segments. POSIX uses `readv`/`writev`; Windows sockets
use `WSARecv`/`WSASend`. Windows files report scalar capability and preserve the
first-segment fallback contract. Use `is_read_vectored()` and
`is_write_vectored()` when selecting a platform-specific fast path.

Native resources expose read/write syscall counters for diagnostics and
benchmarks. These counters are not synchronization primitives and should not
be used as correctness state.
