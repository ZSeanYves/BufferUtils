# Native C Backend

## Status

BufferUtils includes an experimental native-only backend package:

- package path: `ZSeanYves/bufferutils/native`
- target: `native`
- implementation style: MoonBit C FFI plus a small C stub

The stable default package remains pure MoonBit and keeps its existing
semantics.

## Scope

The native backend focuses on real file-handle behavior:

- chunked file reads
- direct file writes
- overwrite and append modes
- buffered native wrappers
- explicit flush and close behavior

The stable root package is unchanged:

- `FileSource` remains a memory-backed snapshot
- `FileSink` remains memory accumulation plus flush-time overwrite

## Experimental Native APIs

### NativeFileSource

- `new_native_file_source(path)`
- `NativeFileSource.read_chunk(size)`
- `NativeFileSource.close()`
- `NativeFileSource.is_closed()`

Behavior:

- opens a native `FILE*` in read mode
- reads chunks without snapshotting the whole file into memory
- returns an empty array at EOF
- requires explicit `close()`
- rejects reads after `close()`

### NativeFileSink

- `NativeFileMode::Overwrite`
- `NativeFileMode::Append`
- `new_native_file_sink(path, mode)`
- `NativeFileSink.write_all(data)`
- `NativeFileSink.flush()`
- `NativeFileSink.close()`
- `NativeFileSink.is_closed()`

Behavior:

- opens a native `FILE*` in overwrite or append mode
- writes chunks directly with `fwrite`
- flushes with `fflush`
- requires explicit `close()`
- `close()` attempts a final flush before `fclose`
- rejects writes and flushes after `close()`

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

Behavior:

- wraps `NativeFileSource` with a refill buffer
- does not snapshot the whole file into memory
- `read_exact` follows streaming-style partial-consumption behavior before a
  possible `Underflow`
- requires explicit `close()`

### NativeBufWriter

- `new_native_buf_writer(path, capacity, mode)`
- `NativeBufWriter.write_byte(b)`
- `NativeBufWriter.write_all(data)`
- `NativeBufWriter.flush()`
- `NativeBufWriter.buffered_len()`
- `NativeBufWriter.capacity()`
- `NativeBufWriter.close()`
- `NativeBufWriter.is_closed()`

Behavior:

- wraps `NativeFileSink` with a local write buffer
- aggregates small writes and flushes when full
- can bypass the local buffer for large direct writes
- `close()` attempts a final flush before closing the wrapped sink
- requires explicit `close()`

## Error Mapping

The C stub uses explicit status codes instead of ambiguous negative returns.

MoonBit-side mapping intentionally stays small:

- invalid path or invalid chunk size -> `BufferError::InvalidInput`
- native open/read/write/flush/close handle failures -> `BufferError::Io`
- EOF is not raised; `read_chunk(size)` returns `[]`

## NativeByteView Cross-reference

The native package also contains experimental `NativeByteView` mmap-backed
research, but that is a narrower borrowed-handle subsystem with its own design
and safety notes.

See:

- [docs/ZERO_COPY_RESEARCH.md](./ZERO_COPY_RESEARCH.md)
- [docs/NATIVE_SAFETY.md](./NATIVE_SAFETY.md)
- [docs/MMAP_FEASIBILITY.md](./MMAP_FEASIBILITY.md)

## Target and Toolchain Caveats

- native backend support depends on MoonBit native target builds
- a working C toolchain is required
- portability should be treated as experimental, not guaranteed
- the stable root package does not depend on the native backend
