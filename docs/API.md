# API Reference

## Stability Model

BufferUtils has four API layers:

1. Stable root API
2. Experimental root `BytesView` inspection API
3. Experimental native file-handle API
4. Experimental native `NativeByteView` zero-copy research API

Stable means part of the pure-MoonBit root compatibility boundary.
Experimental means public, documented, and tested, but outside that stability
promise.

## Stable Root API

### BufferReader

- `new_reader(buf)`: create a reader over immutable `Bytes`
- `read_byte()`: read one byte and advance
- `peek_byte()`: inspect the next byte without advancing
- `read_exact(n)`: read exactly `n` bytes or raise `Underflow`
- `read_remaining()`: read all remaining bytes and advance to the end
- `skip(n)`: advance by `n` bytes with bounds checking
- `rewind()`: reset the cursor to the beginning
- `remaining()`: return unread byte count
- `position()`: return the current byte offset
- `len()`: return total buffer length
- `is_empty()`: report whether all bytes have been consumed

### BufferWriter

Preferred constructors:

- `new_fixed_writer(capacity)`: fixed-capacity writer that raises `Overflow`
  when full
- `new_growing_writer(initial_capacity)`: writer that expands automatically

Methods:

- `write_byte(b)`: append one byte
- `write_all(data)`: append all bytes, atomically for fixed-capacity writers
- `reserve(additional)`: ensure room for additional bytes
- `ensure_capacity(required_capacity)`: ensure total capacity reaches the
  requested value
- `flush_to_bytes()`: return a copy of buffered bytes without clearing
- `clear()`: clear buffered bytes while preserving capacity and growth mode
- `len()`: return current buffered byte count
- `capacity()`: return current capacity
- `remaining_capacity()`: return remaining writable capacity
- `is_empty()`: report whether the writer currently holds no bytes

Notes:

- `BufferWriter` is a low-level in-memory accumulator, not a streaming sink
- `new_writer(capacity)` remains available as a compatibility constructor for
  fixed writers

### MemorySource

- `new_memory_source(data)`: create a source from `Bytes`
- `new_memory_source_from_array(data)`: create a source from `Array[Byte]`
- `read(dst)`: copy up to `dst.length()` bytes into the destination array and
  return the actual count
- `read_to_end()`: return all remaining bytes and advance to EOF
- `remaining()`: return unread bytes remaining
- `position()`: return current source offset
- `rewind()`: reset to the beginning
- `len()`: return total source length
- `is_empty()`: report whether the source is exhausted

### MemorySink

- `new_memory_sink()`: create an empty in-memory sink
- `write(src)`: append all bytes
- `flush()`: no-op for memory-backed output
- `to_bytes()`: return a copy of accumulated bytes
- `clear()`: remove all accumulated bytes
- `len()`: return accumulated byte count
- `is_empty()`: report whether the sink is empty

### BufReader

- `new_buf_reader(source, capacity)`: create a buffered reader over a
  `MemorySource`
- `new_file_buf_reader(path, capacity)`: create a buffered reader over a file
  snapshot
- `fill_buf()`: refill the internal buffer when needed and return buffered
  length
- `read_byte()`: read one byte, refilling when necessary
- `read_exact(n)`: read exactly `n` bytes across refill boundaries
- `read_to_end()`: read all remaining bytes to EOF
- `consume(n)`: consume already-buffered bytes only
- `buffered_len()`: return unread bytes currently buffered
- `capacity()`: return configured internal buffer size
- `is_eof()`: report whether EOF has been reached and buffered data is drained

### BufWriter

- `new_buf_writer(sink, capacity)`: create a buffered writer over a
  `MemorySink`
- `write_byte(b)`: append one byte to the internal buffer, flushing when full
- `write_all(src)`: write a whole chunk, buffering or bypassing as appropriate
- `flush()`: flush buffered bytes into the sink
- `buffered_len()`: return bytes currently buffered in the writer
- `capacity()`: return configured internal buffer size
- `into_inner()`: flush buffered bytes and return the wrapped `MemorySink`

Notes:

- `BufReader` and `BufWriter` are concrete-type APIs over `MemorySource` and
  `MemorySink`
- `BufReader.read_exact(n)` is streaming-style: if EOF is reached after partial
  progress, already-consumed buffered bytes may remain consumed before
  `Underflow` is raised

### FileSource

- `new_file_source(path)`: read the file into memory and create a snapshot
  source
- `read(dst)`: copy bytes from the snapshot into the destination array
- `read_to_end()`: return all remaining bytes from the snapshot
- `remaining()`: return unread snapshot bytes
- `position()`: return current snapshot offset
- `rewind()`: reset the snapshot cursor
- `len()`: return total snapshot length
- `is_empty()`: report whether the snapshot is exhausted
- `path()`: return the original file path

### FileSink

- `new_file_sink(path)`: create a file sink that accumulates bytes in memory
- `write(src)`: append bytes into the accumulated in-memory output
- `flush()`: overwrite the target file with the current accumulated bytes,
  including creating or overwriting an empty file when the accumulated data is
  empty
- `pending_len()`: return bytes not yet persisted to disk
- `clear()`: clear accumulated output and reset flush state
- `path()`: return the target file path
- `to_bytes()`: return a copy of accumulated bytes

### FileBufWriter / `new_file_buf_reader`

- `new_file_buf_writer(path, capacity)`: create a buffered file writer
- `FileBufWriter.write_byte(b)`: append one byte, flushing local buffer when
  full
- `FileBufWriter.write_all(src)`: append a chunk while preserving order
- `FileBufWriter.flush()`: flush the local buffer into the sink, then persist
  the sink to disk
- `FileBufWriter.buffered_len()`: return local in-memory buffered bytes
- `FileBufWriter.pending_len()`: return bytes not yet written to disk across
  both local buffer and file sink
- `FileBufWriter.path()`: return target file path
- `FileBufWriter.capacity()`: return configured local buffer size
- `new_file_buf_reader(path, capacity)`: create a buffered reader over a file
  snapshot

Notes:

- `FileSource` is a memory-backed snapshot, not an OS-level streaming file
  handle
- `FileSink` is memory accumulation plus flush-time overwrite, not append-mode
  streaming output

### Conversion Helpers

- `bytes_to_array(data)`: copy `Bytes` into `Array[Byte]`
- `array_to_bytes(data)`: copy `Array[Byte]` into `Bytes`
- `ints_to_bytes(data)`: validate `0..255` and convert integers to bytes
- `string_to_utf8_bytes(s)`: UTF-8 encode a string into `Bytes`
- `utf8_bytes_to_string(b)`: decode UTF-8 bytes into a `String`

### Split Helpers

- `split_bytes(buf, delimiter)`: split `Bytes` by delimiter and preserve empty
  segments
- `split_array_bytes(arr, delimiter)`: split `Array[Byte]` by delimiter and
  preserve empty segments

### Errors

- `BufferError::Overflow(String)`
- `BufferError::Underflow(String)`
- `BufferError::InvalidCapacity(String)`
- `BufferError::InvalidInput(String)`
- `BufferError::Io(String)`
- `BufferError::Flush(String)`
- `Utf8DecodeError(String)`

## Experimental Root BytesView APIs

These APIs are experimental, non-consuming, and read-only:

- `BufferReader.peek_slice`
- `BufferReader.remaining_slice`
- `MemorySource.peek_remaining`
- `FileSource.peek_remaining`

They return MoonBit `BytesView`, but BufferUtils does not guarantee
runtime-level shared-storage or stable zero-copy behavior.

These APIs operate only on MoonBit-managed memory:

- immutable `Bytes`
- immutable memory-backed sources
- immutable file snapshots

They do not imply any C-memory-backed `BytesView` support.

## Experimental Native File-handle APIs

Package: `ZSeanYves/bufferutils/native`

These APIs are experimental, native-target only, and require a working C
toolchain plus explicit `close()`.

### NativeFileSource

- `new_native_file_source(path)`
- `NativeFileSource.read_chunk(size)`
- `NativeFileSource.close()`
- `NativeFileSource.is_closed()`

### NativeFileSink

- `NativeFileMode::Overwrite`
- `NativeFileMode::Append`
- `new_native_file_sink(path, mode)`
- `NativeFileSink.write_all(data)`
- `NativeFileSink.flush()`
- `NativeFileSink.close()`
- `NativeFileSink.is_closed()`

### NativeBufReader

- `new_native_buf_reader(path, capacity)`
- `NativeBufReader.fill_buf()`
- `NativeBufReader.read_byte()`
- `NativeBufReader.read_exact(n)`
- `NativeBufReader.read_to_end()`
- `NativeBufReader.consume(n)`
- `NativeBufReader.buffered_len()`
- `NativeBufReader.capacity()`
- `NativeBufReader.is_eof()`
- `NativeBufReader.close()`
- `NativeBufReader.is_closed()`

### NativeBufWriter

- `new_native_buf_writer(path, capacity, mode)`
- `NativeBufWriter.write_byte(b)`
- `NativeBufWriter.write_all(data)`
- `NativeBufWriter.flush()`
- `NativeBufWriter.buffered_len()`
- `NativeBufWriter.capacity()`
- `NativeBufWriter.close()`
- `NativeBufWriter.is_closed()`

Notes:

- these APIs do not replace `FileSource` / `FileSink`
- invalid native arguments map to `BufferError::InvalidInput`
- native open/read/write/flush/close failures map to `BufferError::Io`
- `NativeBufReader.read_exact(n)` is streaming-style and can raise `Underflow`
  after partial consumption

## Experimental NativeByteView APIs

> `NativeByteView` is experimental, native-only, and not MoonBit `BytesView`.
> It uses a MoonBit-managed external owner object with finalizer fallback.

- `new_mmap_file_view(path)`: open an experimental native-only read-only mmap
  handle
- `NativeByteView.len()`: return mapped byte length
- `NativeByteView.is_closed()`: report whether the current view has been closed
- `NativeByteView.owner_ref_count()`: research/debug helper that reports the
  shared owner's current live-view count
- `NativeByteView.slice_handle(start, len)`: create a child view over a subrange
  while sharing the same owner
- `NativeByteView.read_byte_at(index)`: read one byte directly from the mapped
  region
- `NativeByteView.copy_range(start, len)`: explicit copy from native memory
  into MoonBit `Array[Byte]`
- `NativeByteView.find_byte(b)`: search the mapped region in C
- `NativeByteView.count_byte(b)`: count matching bytes in C
- `NativeByteView.index_of(pattern)`: search for a byte pattern in C
- `NativeByteView.equals(data)`: compare the mapped region against a MoonBit
  byte array in C
- `NativeByteView.crc32()`: compute a CRC32 checksum in C
- `NativeByteView.checksum_u64()`: compute a checksum in C and return a 64-bit
  result
- `NativeByteView.starts_with(data)`: compare a MoonBit prefix against the
  mapped region in C
- `NativeByteView.copy_to_file(path)`: native-side transfer to another file
  path without materializing a large MoonBit array
- `NativeByteView.close()`: close the current view; the shared owner is released
  when the last open view closes

Notes:

- `NativeByteView` is not MoonBit `BytesView`
- `owner_ref_count()` is a research/debug helper, not a recommended quick-usage
  API
- `copy_range(...)` is the explicit-copy boundary by design
- `copy_to_file(...)` is a native-side transfer, not a stable zero-copy
  guarantee
- explicit `close()` is still recommended
- the owner finalizer is fallback only, not a deterministic prompt-release
  contract
- Windows mmap support is currently unsupported
- no thread-safety guarantee is provided for the shared-owner bookkeeping

## Unsupported / Non-goals

BufferUtils does not currently claim or provide:

- stable zero-copy
- stable mmap APIs
- stable C-memory-backed MoonBit `BytesView`
- writable mmap through `NativeByteView`
- Windows mmap support
- thread-safe native mmap owner management
- async I/O in the stable root package
