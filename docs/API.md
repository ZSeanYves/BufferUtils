# BufferUtils API Reference

## Stable Root API

### Low-Level Buffers

### BufferReader
- `new_reader(buf)`: create a reader over immutable `Bytes`.
- `read_byte()`: read one byte and advance.
- `peek_byte()`: inspect the next byte without advancing.
- `peek_slice(n)`: Experimental. Return a non-consuming read-only `BytesView` for the next `n` bytes.
- `read_exact(n)`: read exactly `n` bytes or raise `Underflow`.
- `read_remaining()`: read all remaining bytes and advance to the end.
- `remaining_slice()`: Experimental. Return a non-consuming read-only `BytesView` for unread bytes.
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

### Conversion and Split Utilities

- `bytes_to_array(data)`: copy `Bytes` into `Array[Byte]`.
- `array_to_bytes(data)`: copy `Array[Byte]` into `Bytes`.
- `ints_to_bytes(data)`: validate `0..255` and convert integers to bytes.
- `string_to_utf8_bytes(s)`: UTF-8 encode a string into `Bytes`.
- `utf8_bytes_to_string(b)`: decode UTF-8 bytes into a `String`.
- `split_bytes(buf, delimiter)`: split `Bytes` by delimiter and preserve empty segments.
- `split_array_bytes(arr, delimiter)`: split `Array[Byte]` by delimiter and preserve empty segments.

### Memory Streaming API

### MemorySource
- `new_memory_source(data)`: create a source from `Bytes`.
- `new_memory_source_from_array(data)`: create a source from `Array[Byte]`.
- `read(dst)`: copy up to `dst.length()` bytes into the destination array and return the actual count.
- `read_to_end()`: return all remaining bytes and advance to EOF.
- `peek_remaining()`: Experimental. Return a non-consuming read-only `BytesView` for unread bytes.
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
- `BufReader.read_exact(n)` is streaming-style: if EOF is reached after partial progress, some already-consumed buffered bytes may remain consumed before `Underflow` is raised.
- BufferUtils does not expose trait-based pluggable source/sink backends in the stable default package.

### File Convenience Layer

### FileSource
- `new_file_source(path)`: read the file into memory and create a snapshot source.
- `read(dst)`: copy bytes from the snapshot into the destination array.
- `read_to_end()`: return all remaining bytes from the snapshot.
- `peek_remaining()`: Experimental. Return a non-consuming read-only `BytesView` over the in-memory snapshot.
- `remaining()`: return unread snapshot bytes.
- `position()`: return current snapshot offset.
- `rewind()`: reset the snapshot cursor.
- `len()`: return total snapshot length.
- `is_empty()`: report whether the snapshot is exhausted.
- `path()`: return the original file path.

### FileSink
- `new_file_sink(path)`: create a file sink that accumulates bytes in memory.
- `write(src)`: append bytes into the accumulated in-memory output.
- `flush()`: overwrite the target file with the current accumulated bytes, creating or overwriting an empty file when the accumulated data is empty.
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
- `FileSource` snapshot creation reads the whole file into memory up front.
- `FileSink` is memory accumulation plus flush-time overwrite, not append-mode streaming output.
- Experimental `peek_*` / `*_slice()` APIs return `BytesView`, but BufferUtils does not currently guarantee that MoonBit runtime slicing is always shared-storage or no-copy.
- These APIs are not part of the stable copy-returning API family. They are intended for read-only, non-consuming inspection.

## Experimental Root BytesView API

These APIs are experimental, non-consuming, and read-only:

- `BufferReader.peek_slice`
- `BufferReader.remaining_slice`
- `MemorySource.peek_remaining`
- `FileSource.peek_remaining`

They return MoonBit `BytesView`, but BufferUtils does not guarantee
runtime-level shared-storage or stable zero-copy behavior.

## Experimental Native Backend

Package: `ZSeanYves/bufferutils/native`

These APIs are experimental and native-target only. They are not part of the stable default root package surface.

- `native_backend_version()`: native C FFI probe for backend wiring.
- `NativeFileMode::Overwrite`: open a native sink in overwrite mode.
- `NativeFileMode::Append`: open a native sink in append mode.
- `new_native_file_source(path)`: open a native `FILE*`-backed source without snapshotting the whole file.
- `NativeFileSource.read_chunk(size)`: read up to `size` bytes from the native file handle. EOF returns an empty array.
- `NativeFileSource.close()`: release the underlying file handle. Repeated close is safe.
- `NativeFileSource.is_closed()`: report whether the source has already been closed.
- `new_native_file_sink(path, mode)`: open a native `FILE*`-backed sink in overwrite or append mode.
- `NativeFileSink.write_all(data)`: write the provided byte array directly to the native file handle.
- `NativeFileSink.flush()`: flush stdio state into the target file.
- `NativeFileSink.close()`: attempt a final flush and then close the underlying file handle. Repeated close is safe.
- `NativeFileSink.is_closed()`: report whether the sink has already been closed.
- `new_native_buf_reader(path, capacity)`: open a buffered native reader over `NativeFileSource`.
- `NativeBufReader.fill_buf()`: refill the local buffer when it has been fully consumed.
- `NativeBufReader.read_byte()`: read a single byte, raising `Underflow` at EOF.
- `NativeBufReader.read_exact(n)`: read exactly `n` bytes, possibly across multiple native chunks.
- `NativeBufReader.read_to_end()`: read all remaining bytes until EOF.
- `NativeBufReader.consume(n)`: consume bytes already buffered locally.
- `NativeBufReader.buffered_len()`: return unread bytes currently buffered.
- `NativeBufReader.capacity()`: return configured local buffer capacity.
- `NativeBufReader.is_eof()`: report whether EOF has been reached and the local buffer is empty.
- `NativeBufReader.close()`: close the wrapped native file source. Repeated close is safe.
- `NativeBufReader.is_closed()`: report whether the reader has already been closed.
- `new_native_buf_writer(path, capacity, mode)`: open a buffered native writer over `NativeFileSink`.
- `NativeBufWriter.write_byte(b)`: append one byte, flushing when the local buffer is full.
- `NativeBufWriter.write_all(data)`: buffer small writes and bypass the local buffer for large writes when possible.
- `NativeBufWriter.flush()`: flush local buffered bytes into the native sink and then flush stdio state.
- `NativeBufWriter.buffered_len()`: return bytes still sitting in the local writer buffer.
- `NativeBufWriter.capacity()`: return configured local buffer capacity.
- `NativeBufWriter.close()`: attempt a final flush and then close the wrapped native sink. Repeated close is safe.
- `NativeBufWriter.is_closed()`: report whether the writer has already been closed.

### Experimental Native Zero-copy Research APIs

Warning:

- `NativeByteView` is not MoonBit `BytesView`
- this is not a stable zero-copy API
- this is native-target only and Unix-like mmap support is the currently
  validated path
- `owner_ref_count()` is a research/debug helper, not a recommended
  quick-usage API

- `new_mmap_file_view(path)`: open an experimental native-only read-only mmap handle.
- `NativeByteView.len()`: return mapped byte length.
- `NativeByteView.is_closed()`: report whether the mapped handle has already been closed.
- `NativeByteView.owner_ref_count()`: Experimental research/debug helper that reports the shared owner's current live-view count for the current view.
- `NativeByteView.slice_handle(start, len)`: create a child native view over a subrange of the mapped bytes while sharing the same native owner.
- `NativeByteView.read_byte_at(index)`: read one byte directly from the mapped region without copying the whole file into MoonBit.
- `NativeByteView.copy_range(start, len)`: explicitly copy a byte range out of the mapped region.
- `NativeByteView.find_byte(b)`: search the mapped region in C and return the first index or `-1`.
- `NativeByteView.count_byte(b)`: count matching bytes in C without copying the mapped region back into MoonBit.
- `NativeByteView.index_of(pattern)`: search for the first occurrence of a byte pattern in C.
- `NativeByteView.equals(data)`: compare the mapped region against a MoonBit byte array in C.
- `NativeByteView.crc32()`: compute a CRC32 checksum in C over the mapped region.
- `NativeByteView.checksum_u64()`: compute a checksum in C over the mapped region and return the 64-bit result.
- `NativeByteView.starts_with(data)`: compare a MoonBit byte prefix against the mapped region in C.
- `NativeByteView.copy_to_file(path)`: copy the mapped region to a file in the native layer without materializing a large MoonBit array.
- `NativeByteView.close()`: close the current view. The shared owner is released when the last open view closes. Repeated close is safe.

Notes:

- the native backend is experimental public API, not part of the stable 1.0-facing root package
- explicit `close()` is required because native resources are not memory-backed snapshots
- invalid native arguments map to `BufferError::InvalidInput`
- native open/read/write/flush/close failures map to `BufferError::Io`
- `NativeBufReader.read_exact(n)` is streaming-style: an eventual `Underflow` can happen after partial consumption if EOF is reached mid-read
- these APIs do not replace `FileSource` / `FileSink`, which remain memory-backed convenience layers
- this backend does not claim zero-copy behavior
- `NativeByteView` is a native-only research handle, not a stable MoonBit `BytesView` bridge
- `NativeByteView` uses a MoonBit-managed external owner plus manual live-view counting for parent/child slices and still requires explicit `close()`
- `NativeByteView.owner_ref_count()` is kept only as a research/debug helper and is not part of the recommended quick-usage path
- `copy_range(...)` is an explicit-copy API by design
- `copy_to_file(...)` is a native-layer transfer and not a stable zero-copy guarantee
- `new_mmap_file_view(...)` is currently intended for Unix-like native targets only
- Windows mmap support is currently unsupported
- no deterministic automatic destructor contract is provided for native mmap handles; the owner finalizer is fallback only
- no thread-safety guarantee is provided for the native shared-owner bookkeeping
- the intended `NativeByteView` surface is its documented constructor and methods, not manual field construction or mutation
- see `docs/MMAP_FEASIBILITY.md` and `docs/ZERO_COPY_RESEARCH.md` for the current feasibility and research conclusions

## 6. Errors

### BufferError
- `Overflow(String)`: fixed-capacity write exceeded allowed capacity.
- `Underflow(String)`: read requested more bytes than available.
- `InvalidCapacity(String)`: constructor received a non-positive capacity.
- `InvalidInput(String)`: caller supplied an invalid count or out-of-range value.
- `Io(String)`: file I/O or native handle operation failed.
- `Flush(String)`: memory-backed file sink flush failed.

### Utf8DecodeError
- `Utf8DecodeError(String)`: UTF-8 decode failed.

## Legacy Compatibility APIs

- `new_writer(capacity)`: compatibility constructor that still creates a fixed-capacity `BufferWriter`.

No CamelCase compatibility wrappers remain in the stable root package.
