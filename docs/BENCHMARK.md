# Benchmark Guide

## Purpose

BufferUtils includes a benchmark runner for local regression tracking.

Its job is to help compare relative behavior across:

- pure in-memory buffer operations
- memory-backed streaming APIs
- memory-backed file convenience APIs
- experimental native file-handle APIs
- experimental mmap-backed `NativeByteView` research APIs

The benchmark is intentionally conservative. It is for local trend tracking,
not for benchmark-proven performance claims.

## How To Run

From the repository root:

```bash
moon run src/bench --target native --release
```

The benchmark executable lives under `src/bench/`.

Native benchmark cases require:

- `--target native`
- a working C toolchain
- a platform that can build the experimental native package

## Output Format

The runner prints CSV-style rows:

```text
name,size,bytes,temp_file,mean_us,throughput_mib_per_s,runs
```

Field meanings:

- `name`: benchmark case name
- `size`: human-readable size label
- `bytes`: byte length of the case
- `temp_file`: `true` when the case reads or writes benchmark files under `.tmp/`
- `mean_us`: mean elapsed time in microseconds across measured runs
- `throughput_mib_per_s`: simple MiB/s figure derived from `bytes / mean_us`
- `runs`: repeat count used for `mean_us`

## Benchmark Groups

The current benchmark suite groups cases by backend and API shape.

### memory_buffer

- `memory_buffer_reader_sequential_read`
- `memory_buffer_reader_remaining_slice_experimental`
- `memory_buffer_reader_peek_slice_experimental`
- `memory_buffer_writer_fixed_write`
- `memory_buffer_writer_growing_write`

These cover direct in-memory reader/writer operations.

### memory_streaming

- `memory_streaming_buf_reader_read_to_end`
- `memory_streaming_buf_writer_write_all_flush`

These cover memory-backed streaming APIs built on `MemorySource` /
`MemorySink`.

### file_memory_backed

- `file_memory_source_read_snapshot`
- `file_memory_source_peek_remaining_experimental`
- `file_memory_sink_flush_write`

These cover the stable file convenience layer:

- `FileSource` as a memory-backed snapshot
- `FileSink` as memory accumulation plus flush-time overwrite

### native_file_experimental

- `native_file_source_read_chunk_experimental`
- `native_file_sink_write_flush_experimental`

These cover direct native `FILE*`-handle reads and writes in the experimental
native package.

### native_buffered_experimental

- `native_buffered_reader_read_to_end_experimental`
- `native_buffered_writer_write_flush_experimental`

These cover buffered wrappers over native file handles.

### native_mmap_view_experimental

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

These cover `NativeByteView` research operations over mmap-backed native memory.

## Methodology

The current runner uses:

- `1` warmup run per benchmark case and size
- `5` measured runs per benchmark case and size
- `mean_us` as the arithmetic mean across measured runs only

This is a lightweight repeated-run baseline, not a statistically rigorous
benchmark harness.

Current benchmark sizes:

- `1KB`
- `64KB`
- `1MB`
- `10MB`

Temporary benchmark files live under:

```text
.tmp/bufferutils-bench/
```

This directory is ignored by Git.

## Local Observations

The following 10MB numbers come from a current local native-target run on this
repository. They are local observations, not portable throughput claims.

| Case | 10MB local observation | Interpretation |
|---|---:|---|
| `file_memory_source_read_snapshot` | ~662 MiB/s | Memory-backed `FileSource` snapshot read |
| `file_memory_sink_flush_write` | ~109 MiB/s | Memory-backed `FileSink` flush write |
| `native_file_source_read_chunk_experimental` | ~2622 MiB/s | Native chunked read path; strongly cache-sensitive |
| `native_file_sink_write_flush_experimental` | ~178 MiB/s | Native direct write + flush |
| `native_buffered_reader_read_to_end_experimental` | ~215 MiB/s | Buffered native reader path |
| `native_buffered_writer_write_flush_experimental` | ~185 MiB/s | Buffered native writer path |
| `native_mmap_view_find_byte_experimental` | ~3313 MiB/s | C-side mmap scan with small result only |
| `native_mmap_view_count_byte_experimental` | ~11446 MiB/s | C-side full scan/count; highly cache-sensitive |
| `native_mmap_view_checksum_experimental` | ~835 MiB/s | C-side checksum over mmap-backed memory |
| `native_mmap_view_crc32_experimental` | ~137 MiB/s | C-side CRC32 checksum |
| `native_mmap_view_copy_range_explicit_copy` | ~2540 MiB/s | Explicit copy into a MoonBit array |
| `native_mmap_view_copy_to_file_experimental` | ~3635 MiB/s | Native-side transfer to another file |
| `native_mmap_view_slice_count_byte_experimental` | ~13833 MiB/s | C-side count on a child slice handle |
| `native_mmap_view_slice_crc32_experimental` | ~198 MiB/s | C-side CRC32 on a child slice handle |
| `native_mmap_view_slice_copy_range_explicit_copy` | ~3709 MiB/s | Explicit copy from a child slice handle |

## Interpreting Results

Read the results conservatively.

What the numbers are good for:

- spotting regressions between releases
- comparing relative behavior between backends
- identifying whether work stays in C or crosses back into MoonBit

Important interpretation notes:

- `read_byte_scan` mainly measures MoonBit-to-C per-byte FFI overhead
- `count_byte`, `find_byte`, `index_of`, `equals`, `crc32`, and `checksum_u64`
  better represent C-side zero-copy-style processing
- `copy_range` is an explicit-copy baseline, not a borrowed-view guarantee
- `copy_to_file` is a native-side transfer path that avoids materializing a
  large MoonBit array in MoonBit code
- the `slice_*` cases additionally exercise the shared-owner/ref-count path of
  `NativeByteView`
- experimental root `BytesView` cases may still copy depending on MoonBit
  runtime behavior

## Caveats

These benchmarks do **not** prove:

- stable zero-copy behavior
- stable mmap throughput across machines
- raw disk throughput
- benchmark-proven high performance guarantees

Native file and mmap results are strongly affected by:

- filesystem cache
- page cache and page-fault behavior
- CPU and OS differences
- compiler and MoonBit runtime version
- fixture setup and allocation behavior

Small-file cases are especially sensitive to:

- FFI call overhead
- benchmark harness overhead
- fixture generation cost

The root file benchmarks also include the current stable semantics:

- `FileSource` still loads the whole file into memory
- `FileSink` still writes the full accumulated buffer with overwrite semantics
- an empty first `FileSink.flush()` still materializes an empty file

## Historical Context

The benchmark suite has grown over several releases:

- `v0.11.0`: initial local regression baseline
- `v0.12.0` to `v0.15.0`: reduced-copy tracking and reader/source view experiments
- `v0.17.0` to `v0.20.0`: experimental native file-handle and buffered-native cases
- `v0.23.0`: experimental `NativeByteView` mmap research cases

The output format has intentionally remained stable so local runs can still be
compared across those iterations.

## Adding New Benchmark Cases

When adding a new benchmark case:

- keep the CSV output fields stable unless there is a strong reason to change them
- choose a case name that clearly reflects its backend group
- prefer adding to an existing backend family such as `memory_buffer_*`,
  `native_file_*`, or `native_mmap_view_*`
- keep temporary files under `.tmp/bufferutils-bench/`
- document whether the case is:
  - memory-backed
  - explicit-copy
  - native-side transfer
  - or C-side processing
- update this guide so readers know how to interpret the new case conservatively
