# BufferUtils API Reference

## 1. Low-Level Buffers

### BufferReader
- `new_reader(buf)`: create a reader over immutable `Bytes`.
- `read_byte()`: read one byte and advance.
- `peek_byte()`: inspect the next byte without advancing.
- `read_exact(n)`: read exactly `n` bytes or raise `Underflow`.
- `read_remaining()`: read all remaining bytes and advance to the end.
- `skip(n)`: advance by `n` bytes with bounds checking.
- `rewind()`: reset the cursor to the beginning.
- `remaining()`: return unread byte count.
- `position()`: return the current byte offset.
- `len()`: return total buffer length.
- `is_empty()`: report whether all bytes have been consumed.

### BufferWriter
Preferred constructors:

- `new_fixed_writer(capacity)`: fixed-capacity writer that raises `Overflow` when full.
- `new_growing_writer(initial_capacity)`: writer that expands automatically.

Methods:

- `write_byte(b)`: append one byte.
- `write_all(data)`: append all bytes, atomically for fixed-capacity writers.
- `reserve(additional)`: ensure room for additional bytes.
- `ensure_capacity(required_capacity)`: ensure total capacity reaches the requested value.
- `flush_to_bytes()`: return a copy of buffered bytes without clearing.
- `clear()`: clear buffered bytes while preserving capacity and growth mode.
- `len()`: return current buffered byte count.
- `capacity()`: return current capacity.
- `remaining_capacity()`: return remaining writable capacity.
- `is_empty()`: report whether the writer currently holds no bytes.

Notes:

- `BufferWriter` is a low-level in-memory accumulator, not a streaming sink.
- `new_writer(capacity)` is retained as a compatibility constructor for fixed writers and is documented under the legacy section below.

## 2. Conversion and Split Utilities

- `bytes_to_array(data)`: copy `Bytes` into `Array[Byte]`.
- `array_to_bytes(data)`: copy `Array[Byte]` into `Bytes`.
- `ints_to_bytes(data)`: validate `0..255` and convert integers to bytes.
- `string_to_utf8_bytes(s)`: UTF-8 encode a string into `Bytes`.
- `utf8_bytes_to_string(b)`: decode UTF-8 bytes into a `String`.
- `split_bytes(buf, delimiter)`: split `Bytes` by delimiter and preserve empty segments.
- `split_array_bytes(arr, delimiter)`: split `Array[Byte]` by delimiter and preserve empty segments.

## 3. Memory Streaming API

### MemorySource
- `new_memory_source(data)`: create a source from `Bytes`.
- `new_memory_source_from_array(data)`: create a source from `Array[Byte]`.
- `read(dst)`: copy up to `dst.length()` bytes into the destination array and return the actual count.
- `read_to_end()`: return all remaining bytes and advance to EOF.
- `remaining()`: return unread bytes remaining.
- `position()`: return current source offset.
- `rewind()`: reset to the beginning.
- `len()`: return total source length.
- `is_empty()`: report whether the source is exhausted.

### MemorySink
- `new_memory_sink()`: create an empty in-memory sink.
- `write(src)`: append all bytes.
- `flush()`: no-op for memory-backed output.
- `to_bytes()`: return a copy of accumulated bytes.
- `clear()`: remove all accumulated bytes.
- `len()`: return accumulated byte count.
- `is_empty()`: report whether the sink is empty.

### BufReader
- `new_buf_reader(source, capacity)`: create a buffered reader over a `MemorySource`.
- `new_file_buf_reader(path, capacity)`: create a buffered reader over a file snapshot.
- `fill_buf()`: refill the internal buffer when needed and return currently buffered length.
- `read_byte()`: read one byte, refilling when necessary.
- `read_exact(n)`: read exactly `n` bytes across refill boundaries.
- `read_to_end()`: read all remaining bytes to EOF.
- `consume(n)`: consume already-buffered bytes only.
- `buffered_len()`: return unread bytes currently buffered.
- `capacity()`: return configured internal buffer size.
- `is_eof()`: report whether EOF has been reached and buffered data is drained.

### BufWriter
- `new_buf_writer(sink, capacity)`: create a buffered writer over a `MemorySink`.
- `write_byte(b)`: append one byte to the internal buffer, flushing when full.
- `write_all(src)`: write a whole chunk, buffering or bypassing as appropriate.
- `flush()`: flush buffered bytes into the sink.
- `buffered_len()`: return bytes currently buffered in the writer.
- `capacity()`: return configured internal buffer size.
- `into_inner()`: flush buffered bytes and return the wrapped `MemorySink`.

Notes:

- `BufReader` and `BufWriter` are concrete-type APIs over `MemorySource` and `MemorySink`.
- BufferUtils does not expose trait-based pluggable source/sink backends in `v0.10.0`.

## 4. File Convenience Layer

### FileSource
- `new_file_source(path)`: read the file into memory and create a snapshot source.
- `read(dst)`: copy bytes from the snapshot into the destination array.
- `read_to_end()`: return all remaining bytes from the snapshot.
- `remaining()`: return unread snapshot bytes.
- `position()`: return current snapshot offset.
- `rewind()`: reset the snapshot cursor.
- `len()`: return total snapshot length.
- `is_empty()`: report whether the snapshot is exhausted.
- `path()`: return the original file path.

### FileSink
- `new_file_sink(path)`: create a file sink that accumulates bytes in memory.
- `write(src)`: append bytes into the accumulated in-memory output.
- `flush()`: overwrite the target file with all accumulated bytes.
- `pending_len()`: return bytes not yet persisted to disk.
- `clear()`: clear accumulated output and reset flush state.
- `path()`: return the target file path.
- `to_bytes()`: return a copy of accumulated bytes.

### FileBufWriter
- `new_file_buf_writer(path, capacity)`: create a buffered file writer.
- `write_byte(b)`: append one byte, flushing local buffer when full.
- `write_all(src)`: append a chunk while preserving order.
- `flush()`: flush the local buffer into the sink, then persist the sink to disk.
- `buffered_len()`: return local in-memory buffered bytes.
- `pending_len()`: return bytes not yet written to disk across both local buffer and file sink.
- `path()`: return target file path.
- `capacity()`: return configured local buffer size.

Notes:

- `FileSource` is a memory-backed snapshot, not an OS-level streaming file handle.
- `FileSink` is memory accumulation plus flush-time overwrite, not append-mode streaming output.

## 5. Errors

### BufferError
- `Overflow(String)`: fixed-capacity write exceeded allowed capacity.
- `Underflow(String)`: read requested more bytes than available.
- `InvalidCapacity(String)`: constructor received a non-positive capacity.
- `InvalidInput(String)`: caller supplied an invalid count or out-of-range value.
- `Io(String)`: file read failed.
- `Flush(String)`: file write or flush failed.

### Utf8DecodeError
- `Utf8DecodeError(String)`: UTF-8 decode failed.

## Legacy Compatibility APIs

- `new_writer(capacity)`: compatibility constructor that still creates a fixed-capacity `BufferWriter`.

No CamelCase compatibility wrappers remain in `v0.10.0`.
