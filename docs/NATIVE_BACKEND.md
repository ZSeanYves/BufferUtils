# Native C Backend

## Status

`v0.23.0` keeps the experimental native-only backend package introduced in
`v0.17.0`, hardened in `v0.18.0`, extended with experimental buffered wrappers
in `v0.19.0`, audited for mmap feasibility in `v0.21.0`, reviewed again in
the `v0.22.0` release-candidate audit, and extended on the current research
track with a native-only mmap handle experiment:

- package path: `ZSeanYves/bufferutils/native`
- target: `native`
- implementation style: MoonBit C FFI + a small C `FILE*` stub

The stable default package remains pure MoonBit and keeps its existing semantics.

The new mmap research path is narrower than the rest of the native backend:

- native target only
- Unix-like platforms only
- read-only only

## Why This Exists

The stable file convenience layer is intentionally memory-backed:

- `FileSource` snapshots the whole file into memory
- `FileSink` accumulates bytes in memory and overwrites on `flush()`

That model is honest and portable, but it does not provide real file-handle streaming.
The native backend explores that capability without rewriting the stable API surface.

## Current Experimental APIs

- `native_backend_version()`
- `NativeFileMode::Overwrite`
- `NativeFileMode::Append`
- `new_native_file_source(path)`
- `NativeFileSource.read_chunk(size)`
- `NativeFileSource.close()`
- `NativeFileSource.is_closed()`
- `new_native_file_sink(path, mode)`
- `NativeFileSink.write_all(data)`
- `NativeFileSink.flush()`
- `NativeFileSink.close()`
- `NativeFileSink.is_closed()`
- `new_native_buf_reader(path, capacity)`
- `NativeBufReader.fill_buf()`
- `NativeBufReader.read_byte()`
- `NativeBufReader.read_exact(n)`
- `NativeBufReader.read_to_end()`
- `NativeBufReader.consume(n)`
- `NativeBufReader.close()`
- `NativeBufReader.is_closed()`
- `new_native_buf_writer(path, capacity, mode)`
- `NativeBufWriter.write_byte(b)`
- `NativeBufWriter.write_all(data)`
- `NativeBufWriter.flush()`
- `NativeBufWriter.close()`
- `NativeBufWriter.is_closed()`
- `new_mmap_file_view(path)`
- `NativeByteView.len()`
- `NativeByteView.is_closed()`
- `NativeByteView.owner_ref_count()`
- `NativeByteView.slice_handle(start, len)`
- `NativeByteView.read_byte_at(index)`
- `NativeByteView.copy_range(start, len)`
- `NativeByteView.find_byte(b)`
- `NativeByteView.count_byte(b)`
- `NativeByteView.index_of(pattern)`
- `NativeByteView.equals(data)`
- `NativeByteView.crc32()`
- `NativeByteView.checksum_u64()`
- `NativeByteView.starts_with(data)`
- `NativeByteView.copy_to_file(path)`
- `NativeByteView.close()`

## What It Does Today

### NativeFileSource

- opens a native `FILE*` in read mode
- reads chunks without snapshotting the whole file into memory
- returns an empty array at EOF
- requires explicit `close()`
- rejects reads after `close()`

### NativeFileSink

- opens a native `FILE*` in overwrite or append mode
- writes chunks directly with `fwrite`
- flushes with `fflush`
- requires explicit `close()`
- `close()` attempts a final flush before `fclose`
- rejects writes and flushes after `close()`

### NativeBufReader

- wraps `NativeFileSource` with a refill buffer
- supports `fill_buf`, `read_byte`, `read_exact`, `read_to_end`, and `consume`
- does not snapshot the whole file into memory
- `read_exact` follows streaming-style partial-consumption behavior before a possible `Underflow`
- requires explicit `close()`

### NativeBufWriter

- wraps `NativeFileSink` with a local write buffer
- aggregates small writes and flushes when full
- can bypass the local buffer for large direct writes
- `close()` attempts a final flush before closing the wrapped sink
- requires explicit `close()`

### NativeByteView

- opens a read-only mmap-backed native handle on Unix-like native targets
- does not snapshot the entire file into MoonBit-owned memory
- does not expose a stable MoonBit `BytesView`
- supports explicit-copy extraction through `copy_range(...)`
- supports C-side scans and checks such as `find_byte`, `checksum_u64`, and `starts_with`
- requires explicit `close()`

## mmap Research Outcome

`v0.23.0` still does **not** export a stable mmap-backed MoonBit `BytesView`,
but it does add a native-only research handle: `NativeByteView`.

Why:

- the OS-facing side is feasible on Unix-like targets in principle
- the MoonBit-facing side is the real blocker
- current public FFI support can allocate owned `Bytes`, but it does not expose
  a stable public constructor for a `BytesView` borrowed from arbitrary mmap
  memory
- BufferUtils therefore cannot yet express a clear lifetime contract between
  a public MoonBit view and explicit `close()` / `munmap()`

The current research track therefore stops at a more honest boundary:

- keep borrowed native memory behind `NativeByteView`
- allow explicit copy through `copy_range(...)`
- allow C-side operations that avoid copying whole file contents into MoonBit

See [docs/MMAP_FEASIBILITY.md](./MMAP_FEASIBILITY.md) and
[docs/ZERO_COPY_RESEARCH.md](./ZERO_COPY_RESEARCH.md).

## What It Does Not Do Yet

- no stable borrowed MoonBit `BytesView` over mmap memory
- no vectored I/O
- no stable cross-target promise
- no automatic integration into the stable root package

## Relationship To Existing File APIs

The native backend does not replace:

- `FileSource`
- `FileSink`
- `new_file_buf_reader`
- `FileBufWriter`

Those remain the stable memory-backed file convenience layer.

## Benchmark Coverage

The benchmark runner now includes experimental native cases:

- `native_file_source_read_chunk_experimental`
- `native_file_sink_write_flush_experimental`
- `native_buffered_reader_read_to_end_experimental`
- `native_buffered_writer_write_flush_experimental`
- `native_mmap_view_read_byte_scan_experimental`
- `native_mmap_view_find_byte_experimental`
- `native_mmap_view_count_byte_experimental`
- `native_mmap_view_index_of_experimental`
- `native_mmap_view_equals_experimental`
- `native_mmap_view_crc32_experimental`
- `native_mmap_view_checksum_experimental`
- `native_mmap_view_copy_range_explicit_copy`
- `native_mmap_view_copy_to_file_experimental`
- `native_mmap_view_slice_count_byte_experimental`
- `native_mmap_view_slice_crc32_experimental`
- `native_mmap_view_slice_copy_range_explicit_copy`

Run them with:

```bash
moon run src/bench --target native --release
```

## Recommendation

Treat the native backend as a mainline experimental track in the architecture:

- keep the stable root package pure and portable
- evolve native file-handle behavior in a separate package
- harden lifecycle, portability, and buffered wrappers before any stabilization decision

## Error Mapping

The C stub now uses explicit status codes instead of ambiguous negative returns:

- `BUFFERUTILS_NATIVE_OK`
- `BUFFERUTILS_NATIVE_EOF`
- `BUFFERUTILS_NATIVE_OPEN_FAILED`
- `BUFFERUTILS_NATIVE_READ_FAILED`
- `BUFFERUTILS_NATIVE_WRITE_FAILED`
- `BUFFERUTILS_NATIVE_FLUSH_FAILED`
- `BUFFERUTILS_NATIVE_CLOSE_FAILED`
- `BUFFERUTILS_NATIVE_INVALID_HANDLE`
- `BUFFERUTILS_NATIVE_INVALID_ARGUMENT`
- `BUFFERUTILS_NATIVE_MMAP_FAILED`
- `BUFFERUTILS_NATIVE_MUNMAP_FAILED`
- `BUFFERUTILS_NATIVE_OUT_OF_BOUNDS`
- `BUFFERUTILS_NATIVE_CLOSED`
- `BUFFERUTILS_NATIVE_UNSUPPORTED`

MoonBit-side mapping intentionally stays small:

- invalid path or invalid chunk size -> `BufferError::InvalidInput`
- native open/read/write/flush/close handle failures -> `BufferError::Io`
- EOF is not raised; `read_chunk(size)` returns `[]`

## Benchmark Caveats

- native benchmark cases require the native target and a working C toolchain
- repeated read benchmarks can be heavily affected by filesystem cache
- small benchmark cases are noisy because fixture setup and FFI call overhead matter more
- the current runner uses a light warmup before timed runs
- mmap read-byte scans are dominated by MoonBit-to-C FFI overhead, not raw mmap capability
- mmap checksum/find-byte cases are better indicators of C-side zero-copy-style processing
- native numbers are experimental local observations, not release claims
