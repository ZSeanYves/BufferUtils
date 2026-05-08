# BufferUtils Benchmark Baseline

## Status

Benchmark coverage remains experimental in `v0.23.0`.

The goal of this baseline is repeatability and trend tracking, not marketing claims.
BufferUtils still does not claim benchmark-proven high performance.

## Scope

The current benchmark runner covers:

- `memory_buffer_reader_sequential_read`
- `memory_buffer_reader_remaining_slice_experimental`
- `memory_buffer_reader_peek_slice_experimental`
- `memory_buffer_writer_fixed_write`
- `memory_buffer_writer_growing_write`
- `memory_streaming_buf_reader_read_to_end`
- `memory_streaming_buf_writer_write_all_flush`
- `file_memory_source_read_snapshot`
- `file_memory_source_peek_remaining_experimental`
- `file_memory_sink_flush_write`
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

The current sizes are:

- `1KB`
- `64KB`
- `1MB`
- `10MB`

## How To Run

From the repository root:

```bash
moon run src/bench --target native --release
```

This runs a dedicated benchmark executable under `src/bench/`.
The native backend cases require a native target and a working C toolchain because they are compiled through MoonBit C FFI.

## Output Format

The runner prints CSV-style rows:

```text
name,size,bytes,temp_file,mean_us,throughput_mib_per_s,runs
```

Fields:

- `name`: benchmark case name
- `size`: human-readable size label
- `bytes`: byte length for the case
- `temp_file`: `true` when the benchmark writes or reads benchmark files under `.tmp/`
- `mean_us`: average elapsed time in microseconds across repeated runs
- `throughput_mib_per_s`: simple MiB/s throughput derived from `bytes / mean_us`
- `runs`: repeat count used for the mean

## Methodology

The current runner uses:

- `1` warmup run per benchmark case and size
- `5` measured runs per benchmark case and size
- `mean_us` as the arithmetic mean across measured runs only

This is intentionally a lightweight repeated-run baseline, not a statistically rigorous benchmark harness.

## Temporary Files

File-related benchmark cases create fixtures under:

```text
.tmp/bufferutils-bench/
```

This directory is ignored by Git.

## Interpretation Notes

This benchmark is intended as a baseline, so read the numbers conservatively:

- small-input measurements are more sensitive to runtime noise
- file benchmarks include the current memory-backed file convenience model
- native backend benchmarks are experimental and native-target only
- `file_memory_*` benchmarks cover the stable memory-backed file convenience layer
- `native_file_*` benchmarks cover direct native `FILE*`-handle reads and writes
- `native_buffered_*` benchmarks cover buffered wrappers over those native file handles
- `native_mmap_view_*` benchmarks cover experimental native-only zero-copy research handles
- experimental view/slice benchmark cases may still copy depending on MoonBit runtime behavior
- file-system cache can significantly affect repeated native read results
- small native file cases are sensitive to fixture allocation and per-call overhead
- native file read results are strongly affected by filesystem cache and should not be treated as raw disk throughput
- `native_mmap_view_read_byte_scan_experimental` mainly reflects MoonBit-to-C per-byte FFI overhead
- `native_mmap_view_find_byte_experimental` and `native_mmap_view_checksum_experimental` are better indicators of C-side zero-copy-style processing
- `native_mmap_view_count_byte_experimental`, `native_mmap_view_index_of_experimental`, `native_mmap_view_equals_experimental`, and `native_mmap_view_crc32_experimental` are C-side processing cases that avoid copying the full payload back into MoonBit
- `native_mmap_view_copy_range_explicit_copy` is an explicit-copy baseline, not a borrowed-view guarantee
- `native_mmap_view_copy_to_file_experimental` measures native-side transfer to disk without materializing a large MoonBit array

## Current Hotspots

Based on the current implementation, the main copy and allocation hotspots are expected to be:

- `BufferWriter.flush_to_bytes()` still returning `buf.copy()`
- `FileSink.flush()` still converting accumulated `Array[Byte]` to `Bytes`
- `FileSource` still reading the whole file into memory on construction
- benchmark fixture generation still materializing patterned input arrays
- repeated `pattern_bytes(...)` setup work in benchmark fixture generation

These are useful places to revisit later if the project decides to pursue more aggressive performance work after `1.0`.

## v0.12.0 Reduced-Copy Notes

`v0.12.0` keeps the benchmark format stable and uses it to track reduced-copy changes.

The main implementation changes behind this release are:

- several writer paths now append chunks instead of pushing bytes one by one
- `BufReader.read_exact()` and `BufReader.read_to_end()` now use chunk-oriented buffered copies
- `BufferReader.read_exact()` and `read_remaining()` now slice and copy contiguous ranges directly
- `new_file_buf_reader(...)` no longer creates an extra copied `MemorySource` snapshot from `FileSource`
- `FileSink.flush()` now skips redundant rewrites when no bytes are pending

These changes are intended to reduce unnecessary copying and allocation churn, not to provide zero-copy behavior.

## v0.12.0 Reduced-Copy Observations

`v0.12.0` reduced repeated byte-by-byte pushes and unnecessary intermediate copies in writer, reader, sink, and source paths.

These numbers are local observations only and should not be treated as guaranteed performance.

- One local reduced-copy audit run in `v0.13.0` observed `BufReader.read_to_end`, `10MB`: around `209 MiB/s`
- One local reduced-copy audit run in `v0.13.0` observed `FileSource` snapshot, `10MB`: around `133 MiB/s`
- One local reduced-copy audit run in `v0.13.0` observed `FileSink` flush, `10MB`: around `62.7 MiB/s`

## Remaining Hotspots

- `BufferWriter.flush_to_bytes()` still returns a copy by design.
- `MemorySink.to_bytes()` and `FileSink.to_bytes()` still return copies by design.
- `FileSource` still loads the whole file into memory.
- `FileSink.flush()` still writes the full accumulated buffer when bytes are pending.
- Benchmark fixture allocation can affect small-size cases.

## v0.14.0 View / Slice Experiment

`v0.14.0` adds experimental benchmark coverage for reader/source slice-style APIs.

These cases are intended to compare API shape and local runtime behavior:

- `read_remaining()` vs `remaining_slice()`
- `read_exact()`-style consumption vs `peek_slice()`
- `FileSource.read_to_end()` vs `FileSource.peek_remaining()`

The benchmark output format is unchanged.
The new experimental cases should still be read conservatively because MoonBit runtime slicing may still allocate or copy internally.

`v0.15.0` keeps these cases explicitly experimental. They are useful for observing runtime behavior and relative trends, not for proving stable zero-copy or cross-target performance guarantees.

## v0.17.0 Native Backend Note

`v0.17.0` adds experimental native backend benchmark cases through `ZSeanYves/bufferutils/native`.

These cases are still experimental:

- they require native target builds
- they require a C toolchain
- they do not replace the stable memory-backed file benchmarks
- they do not imply zero-copy or cross-target guarantees

One local run on this repository observed:

- `native_file_source_read_chunk_experimental`, `10MB`: around `2549 MiB/s`
- `native_file_sink_write_flush_experimental`, `10MB`: around `179 MiB/s`

These are local observations only, not release promises.

## v0.18.0 Native Backend Hardening Note

`v0.18.0` does not add new native benchmark case names. Instead, it hardens the
native backend's lifecycle and error-path behavior around those existing cases.

Interpret native numbers conservatively:

- `NativeFileSource` read throughput is especially sensitive to filesystem cache
- `NativeFileSink` write throughput reflects `fwrite` plus `fflush`, not a stable release guarantee
- small-file runs still include noticeable fixture setup and FFI call overhead
- all native benchmark results remain local observations rather than publishable performance claims

One local `v0.18.0` native-target run on this repository observed:

- `native_file_source_read_chunk_experimental`, `10MB`: around `2664 MiB/s`
- `native_file_sink_write_flush_experimental`, `10MB`: around `187 MiB/s`
- `file_memory_source_read_snapshot`, `10MB`: around `614 MiB/s`
- `file_memory_sink_flush_write`, `10MB`: around `112 MiB/s`

## v0.19.0 Native Buffered Note

`v0.19.0` adds experimental native buffered cases on top of the direct handle
backend:

- `native_buffered_reader_read_to_end_experimental`
- `native_buffered_writer_write_flush_experimental`

These cases are still native-target only, still experimental, and still subject
to the same filesystem-cache and small-input caveats as the direct native file
cases. They are useful for comparing buffered native handle behavior against:

- memory-backed `BufReader` / `BufWriter`
- direct native `NativeFileSource` / `NativeFileSink`
- the stable memory-backed file convenience layer

## v0.20.0 Native Benchmark Stabilization Note

`v0.20.0` keeps the CSV fields stable but makes the case names easier to group by backend:

- `memory_buffer_*`
- `memory_streaming_*`
- `file_memory_*`
- `native_file_*`
- `native_buffered_*`

Native file read results are strongly affected by filesystem cache.
The benchmark measures observed end-to-end behavior on the local machine, not raw disk throughput.

One local `v0.20.0` native-target run on this repository observed:

- `native_file_source_read_chunk_experimental`, `10MB`: around `2570 MiB/s`
- `native_file_sink_write_flush_experimental`, `10MB`: around `193 MiB/s`
- `native_buffered_reader_read_to_end_experimental`, `10MB`: around `219 MiB/s`
- `native_buffered_writer_write_flush_experimental`, `10MB`: around `196 MiB/s`
- `file_memory_source_read_snapshot`, `10MB`: around `608 MiB/s`
- `file_memory_sink_flush_write`, `10MB`: around `113 MiB/s`

## v0.21.0 mmap Feasibility Note

`v0.21.0` does not add an experimental mmap benchmark case.

Reason:

- the native backend can investigate Unix-like `mmap` at the C level
- but the current MoonBit-facing FFI surface does not provide a stable public
  way to construct a lifetime-aware `BytesView` directly from mmap-backed memory
- exporting a copied API under an mmap/view name would be misleading

So benchmark coverage stays focused on:

- memory-backed file snapshots
- direct native `FILE*` handles
- buffered wrappers over those native handles

If a future mmap prototype lands, benchmark notes will need to distinguish:

- mapping or view-creation cost
- first-touch page-fault cost
- repeated cached access
- actual byte traversal cost

An mmap benchmark would still not prove raw disk throughput or zero-copy
behavior.

## v0.22.0 Release-Candidate Audit Note

`v0.22.0` does not add new benchmark cases or change the CSV output schema.

This release-candidate audit confirms that benchmark positioning remains:

- experimental
- local-observation oriented
- sensitive to runtime noise and filesystem cache
- unsuitable for marketing-style performance claims

## v0.23.0 Zero-copy Research Note

`v0.23.0` adds native-only research cases around `NativeByteView` and read-only
mmap-backed access:

- `native_mmap_view_read_byte_scan_experimental`
- `native_mmap_view_find_byte_experimental`
- `native_mmap_view_count_byte_experimental`
- `native_mmap_view_index_of_experimental`
- `native_mmap_view_equals_experimental`
- `native_mmap_view_crc32_experimental`
- `native_mmap_view_checksum_experimental`
- `native_mmap_view_copy_range_explicit_copy`
- `native_mmap_view_copy_to_file_experimental`

Interpret these carefully:

- `read_byte_scan` is intentionally a worst-case FFI-overhead probe, not a pure mmap speed test
- `find_byte` uses a no-match fixture so it scans the full mapped region instead of exiting early
- `find_byte`, `count_byte`, `index_of`, `equals`, `crc32`, and `checksum_u64` better represent C-side operations that avoid copying the whole file into MoonBit
- `copy_range_explicit_copy` is the explicit-copy comparison point for the research handle
- `copy_to_file_experimental` is a native-side transfer case, not proof of stable zero-copy semantics
- the `slice_*` cases additionally exercise the shared-owner model by closing the
  root view before operating on the child slice
- page cache and first-touch page faults can dominate mmap results
- none of these cases prove a stable zero-copy contract

One local `v0.23.0` native-target run on this repository observed:

- `native_mmap_view_read_byte_scan_experimental`, `10MB`: around `304 MiB/s`
- `native_mmap_view_find_byte_experimental`, `10MB`: around `3322 MiB/s`
- `native_mmap_view_count_byte_experimental`, `10MB`: around `11819 MiB/s`
- `native_mmap_view_checksum_experimental`, `10MB`: around `918 MiB/s`
- `native_mmap_view_copy_range_explicit_copy`, `10MB`: around `2811 MiB/s`
- `native_mmap_view_slice_count_byte_experimental`, `10MB`: around `16554 MiB/s`
- `native_mmap_view_slice_crc32_experimental`, `10MB`: around `200 MiB/s`
- `native_mmap_view_slice_copy_range_explicit_copy`, `10MB`: around `3689 MiB/s`

## Suggested Workflow

Use this benchmark to compare trends between revisions:

1. Run `moon run src/bench --target native --release`.
2. Capture the CSV-style output in a local note or benchmark artifact.
3. Compare throughput and elapsed time by benchmark name and size.
4. Treat regressions in large-input cases as stronger signals than tiny-input noise.

## Non-Goals

This baseline does not currently provide:

- statistical significance reporting beyond repeated means
- automated historical comparison
- memory profiling
- CPU flamegraphs
- benchmark claims for release marketing
