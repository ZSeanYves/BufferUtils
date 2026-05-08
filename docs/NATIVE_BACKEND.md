# Native C Backend

## Status

`v0.22.0` keeps the experimental native-only backend package introduced in
`v0.17.0`, hardened in `v0.18.0`, extended with experimental buffered wrappers
in `v0.19.0`, audited for mmap feasibility in `v0.21.0`, and reviewed again in
the `v0.22.0` release-candidate audit:

- package path: `ZSeanYves/bufferutils/native`
- target: `native`
- implementation style: MoonBit C FFI + a small C `FILE*` stub

The stable default package remains pure MoonBit and keeps its existing semantics.

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

## mmap Feasibility Outcome

`v0.21.0` does not export an experimental `MmapFileSource`.

Why:

- the OS-facing side is feasible on Unix-like targets in principle
- the MoonBit-facing side is the real blocker
- current public FFI support can allocate owned `Bytes`, but it does not expose
  a stable public constructor for a `BytesView` borrowed from arbitrary mmap
  memory
- BufferUtils therefore cannot yet express a clear lifetime contract between
  `as_view()` and explicit `close()` / `munmap()`

The current recommendation is to keep mmap in feasibility-study mode rather than
ship a copied API under a misleading mmap/view name. See
[docs/MMAP_FEASIBILITY.md](./MMAP_FEASIBILITY.md).

## What It Does Not Do Yet

- no exported mmap API yet
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

Run them with:

```bash
moon run src/bench --target native --release
```

## Recommendation

Treat the native backend as a mainline experimental branch of the architecture:

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

MoonBit-side mapping intentionally stays small:

- invalid path or invalid chunk size -> `BufferError::InvalidInput`
- native open/read/write/flush/close handle failures -> `BufferError::Io`
- EOF is not raised; `read_chunk(size)` returns `[]`

## Benchmark Caveats

- native benchmark cases require the native target and a working C toolchain
- repeated read benchmarks can be heavily affected by filesystem cache
- small benchmark cases are noisy because fixture setup and FFI call overhead matter more
- the current runner uses a light warmup before timed runs
- native numbers are experimental local observations, not release claims
