# Changelog

## v0.37.0

### Breaking
- `SharedBytes::from_fixed_array` and both buffered-writer `into_parts` APIs
  now validate and propagate invalid fixed-array ranges.

### Added
- Async runtime error normalization with cancellation preservation and real
  TCP write-half shutdown.
- Native POSIX vectored file/TCP I/O, Windows socket vectored I/O, capability
  reporting, and per-resource syscall counters.
- Small/short/vectored/native benchmark workloads, three-batch baseline gates,
  and executable example tests.
- `docs/MIGRATION_0.36_TO_0.37.md` for the source migration.

## v0.36.0

### Breaking
- Changed `Read::read` to borrowed `FixedArray` ranges and `Write::write` to
  borrowed `Bytes` ranges; `read_array`/`write_array` are explicit copy adapters.
- Replaced growable array storage with FixedArray logical ranges and removed
  0.35 source compatibility.

### Added
- Added zero-copy `SharedBytes::as_bytes_view`, typed signed/float accessors,
  `BytesMut` resize/reclaim/unsplit/spare-capacity APIs, and validated IoSlice.
- Added BufReader peek/lines/split helpers, cursor-based BufWriter recovery,
  BufStream/Sink, memory pipe endpoints, and structured finish failures.
- Added native OpenOptions, sync_all/sync_data, direct borrowed file/TCP I/O,
  TCP shutdown/timeouts/addresses, async shutdown, and cancellation-protected copy.
- Added the 100-point parity matrix, migration/API contracts, examples, 64 MiB
  benchmark coverage, and three-batch CI performance structure.

## v1.0.0

### Breaking
- Removed the complete pre-1.0 root Buffer/Reader/Writer/source/sink API.
- Removed snapshot file semantics and the global native integer-handle layer.
- Renamed the immutable shared handle to SharedBytes because Bytes is a
  MoonBit builtin; mutable storage is BytesMut.

### Added
- Added COW shared storage with O(1) freeze, split, and slice operations.
- Added Read, Write, BufRead, Seek, Close, Cursor, Empty, Repeat, Take, Chain,
  LineWriter, BufReader, and BufWriter with structured errors and recovery.
- Added NativeFile, NativeTcpStream, NativeTcpListener, and MappedBytes backed
  by independent external objects and platform mutexes.
- Added BufferUtils-owned async traits, generic async buffering, independent
  file offsets, seek-aware buffered wrappers, memory/file/TCP adapters, copy,
  and bidirectional copy.
- Added the parity matrix, API contracts, 10,000-operation model test,
  three-platform CI, sanitizer jobs, and median/p95 raw-path performance gates.

## v0.26.0

### Added
- Added the target-independent `buffer` package with shared immutable cursors,
  growing mutable buffers, capacity checks, endian integers, and UTF-8 bounds.
- Added `Read`, `Write`, `BufRead`, and `Close` contracts with generic
  `BufReader[R]` and `BufWriter[W]`, vectored helpers, partial progress, and
  structured errors.
- Added real streaming native file adapters and a native-focused async package
  built on `moonbitlang/async@0.20.2`.
- Added failure-injection, interruption, EOF, recovery, cancellation, mmap
  finalizer, and large-transfer bypass tests.

### Changed
- Replaced exact-length repeated growth in hot append paths with geometric
  capacity growth, removing the native buffered reader's O(n^2) behavior.
- Extended benchmark output with median, min, max, and median throughput.
- Added shared mmap clone and common close semantics while preserving the
  external-owner finalizer fallback.

### Performance
- On the recorded local 10 MiB benchmark, legacy native buffered reading moved
  from about 265 ms / 37.7 MiB/s to a 1.70 ms median / 5882 MiB/s.
- The new generic native path recorded a 4.45 ms median / 2246 MiB/s on the
  same warm-cache environment.

### Compatibility
- The pre-0.26 root APIs remain available. Their file snapshot/accumulator
  semantics are unchanged; new file code should use the native or async APIs.

## v0.25.0

### Changed
- Migrated the module manifest from `moon.mod.json` to the current `moon.mod` format.
- Upgraded `moonbitlang/x` from `0.4.38` to `0.4.46`.
- Replaced deprecated `try?` usage in tests with current typed error handling.
- Removed the deprecated-warning suppression and scoped the native test-only filesystem dependency to tests.
- Updated installation documentation for the current manifest format.

### Compatibility
- Preserved the public package interfaces and runtime behavior.
- Added `docs/MAINTENANCE_PLAN.md` for the intentionally breaking v2 design direction.

## v0.24.0

### Changed
- Replaced the previous C registry owner model for `NativeByteView` with a MoonBit-managed external object owner.
- Preserved the experimental native `NativeByteView` public API while improving owner lifecycle management.
- Clarified README and docs around stable root APIs, experimental native APIs, NativeByteView zero-copy research, and benchmark interpretation.

### Native
- `NativeByteView` now holds a MoonBit-managed `NativeByteOwner` with a C payload and finalizer fallback.
- `slice_handle(...)` continues to share the same owner without copying mmap memory.
- `close()` still provides explicit cleanup, while the finalizer acts as a fallback if callers forget to close.

### Documentation
- Reworked README and docs to clarify supported scope, limitations, performance observations, and stable/experimental boundaries.
- Added clearer explanations for why BufferUtils does not expose C memory as MoonBit `BytesView`.

### Notes
- This release does not claim stable zero-copy behavior.
- `NativeByteView` remains experimental, native-only, and not MoonBit `BytesView`.
- Windows mmap support and thread-safety guarantees are still not provided.

## v0.23.0

### Added
- Added an experimental native-only `NativeByteView` research API for explicit borrowed-byte access over read-only mmap mappings.
- Added `new_mmap_file_view(path)` plus native-only mmap tests and benchmark cases.
- Added more C-side mmap research operations for counting, pattern search, equality checks, CRC32, and native-side file copy.
- Added a shared-owner / ref-count model for `NativeByteView` slices, including research-only `slice_handle(...)` and owner-ref-count inspection.
- Added zero-copy research documentation for the zero-copy research branch.

### Changed
- Reframed mmap from documented-only feasibility into a native-only research prototype that still does not expose a stable MoonBit `BytesView` bridge.
- Clarified that the mmap research path now uses a MoonBit-managed external-owner safe bridge with explicit view state, manual live-view counting, and finalizer fallback instead of a direct MoonBit `BytesView` bridge.
- Clarified across README, native backend docs, safety notes, and benchmark notes that the new mmap path is experimental, Unix-like native-target only, and not a zero-copy guarantee.
- Kept the stable root package and the existing experimental `FILE*`-based native APIs unchanged while adding the research-only byte-view handle.
- Kept `NativeByteView.owner_ref_count()` positioned as a research/debug helper instead of a recommended usage API.
- Reworked README and documentation around the stable root API, the experimental native backend, and `NativeByteView` zero-copy research.
- Added more concrete local benchmark observation tables with explicit caveats instead of broad performance wording.

### Notes
- v0.23.0 is a research-track release for native zero-copy exploration.
- No stable root API is changed.
- BufferUtils still does not claim stable zero-copy behavior.

### Fixed
- Hid `NativeByteView` implementation fields behind private package fields so generated interface summaries no longer expose them as intended public API surface.
- Removed duplicate `slice_*` mmap benchmark entries from the benchmark documentation.
- Added monotonic native mmap ID exhaustion guards and stronger internal owner/view release verification tests for the safe bridge.

## v0.22.0

### Changed
- Performed a 1.0 release-candidate audit across stable root APIs, experimental `BytesView` APIs, and experimental native APIs.
- Clarified release positioning and public API stability boundaries.
- Confirmed mmap remains documented-only because safe C-to-`BytesView` construction is not currently available.

### Fixed
- Cleaned release-facing documentation wording around zero-copy, mmap, native backend, and benchmark limitations.

### Notes
- v0.22.0 introduces no new core behavior.
- This is a release-candidate audit version before 1.0.

## v0.21.0

### Added
- Added mmap feasibility documentation for the experimental native mmap investigation.

### Changed
- Clarified across README, native backend docs, safety notes, and benchmark notes that mmap remains under feasibility study.
- Kept the experimental native backend on the existing `FILE*`-based read/write path instead of exporting a misleading mmap view API.

### Notes
- v0.21.0 does not add stable APIs.
- v0.21.0 does not add an exported experimental mmap API.
- BufferUtils still does not claim zero-copy behavior.

## v0.20.0

### Added
- Added clearer benchmark grouping for memory-backed, native file-handle, and native buffered cases.
- Added benchmark warmup documentation and native buffered local-observation notes.

### Changed
- Kept CSV benchmark fields stable while renaming benchmark case names to make backend groups easier to compare.
- Tightened native API documentation around the intended experimental public surface.
- Clarified filesystem-cache caveats and simple repeated-run benchmark methodology for native read/write observations.

### Notes
- v0.20.0 does not add new stable APIs.
- Native APIs remain experimental and native-target only.

## v0.18.0

### Added
- Added stronger native-only lifecycle coverage for `NativeFileSource` and `NativeFileSink`.
- Added overwrite/append roundtrip tests across native and memory-backed file layers.
- Added native backend notes about explicit close semantics, cache effects, and error-code mapping.

### Changed
- Hardened the experimental native C backend around explicit status codes instead of ambiguous negative return values.
- Clarified that native handle open/read/write/flush/close failures map to `BufferError::Io`, while invalid native arguments map to `BufferError::InvalidInput`.
- Clarified that `NativeFileSink.close()` attempts a final flush before closing, while explicit `flush()` remains the recommended durability boundary.

### Notes
- v0.18.0 does not add new stable public APIs.
- The stable root package remains pure MoonBit, and `FileSource` / `FileSink` keep their memory-backed semantics.

## v0.17.0

### Added
- Added an experimental native C backend package under `native`.
- Added a minimal native FFI probe via `native_backend_version()`.
- Added experimental `NativeFileSource` and `NativeFileSink` for native-target file-handle streaming.
- Added native-only tests for open/read/write/flush/close and native roundtrips.
- Added native backend benchmark cases and native backend design/safety documentation.

### Changed
- Kept the stable root package on the pure MoonBit implementation path.
- Clarified that `FileSource` and `FileSink` still remain memory-backed convenience layers.
- Updated README, API docs, design docs, and benchmark docs to distinguish stable root APIs from experimental native APIs.

### Notes
- v0.17.0 does not replace the stable pure MoonBit file layer.
- The native backend is experimental, native-target only, and does not claim zero-copy behavior.

## v0.16.0

### Added
- Added OS-level streaming file I/O feasibility documentation.
- Added investigation notes for MoonBit file handle, chunked read, append, flush, and close support.

### Changed
- Clarified that current `FileSource` and `FileSink` remain memory-backed convenience layers.
- Updated Roadmap to track OS-level streaming as a feasibility item.

### Notes
- v0.16.0 does not add stable public streaming file APIs.
- Existing file APIs keep their memory-backed semantics.

## v0.15.0

### Added
- Added stronger regression coverage for experimental `BytesView` APIs.
- Added documentation clarifying the guarantees and non-guarantees of view APIs.

### Changed
- Marked reader/source view APIs explicitly as experimental public APIs.
- Clarified why writer/sink views are intentionally not exposed.

### Notes
- v0.15.0 does not add new view APIs.
- `BytesView` support is not a zero-copy performance guarantee.
- Existing copy-returning APIs keep their original semantics.

## v0.14.0

### Added
- Added documentation and experimental reader/source APIs for byte view and slice investigation.
- Added tests for non-consuming peek/view behavior on `BufferReader`, `MemorySource`, and `FileSource`.

### Changed
- Clarified the distinction between copy-returning APIs, reduced-copy internals, and future view-based APIs.

### Notes
- v0.14.0 does not claim zero-copy behavior.
- Existing copy-returning APIs keep their previous semantics.

## v0.13.0

### Added
- Added reduced-copy regression tests for copy-returning APIs, repeated flushes, and EOF behavior.
- Added benchmark comparison notes for the reduced-copy pass.

### Changed
- Clarified copy semantics and remaining hotspots in benchmark and design documentation.

### Fixed
- Strengthened regression coverage around repeated flush and read-to-end behavior after reduced-copy optimizations.

### Notes
- v0.13.0 does not introduce new public APIs.
- Reduced-copy does not mean zero-copy.

## v0.12.0

### Changed
- Reduced copy-heavy paths across reader, writer, streaming, and file convenience implementations without changing the stable public API.
- Switched several byte-append loops from repeated per-byte `push` behavior to chunk-oriented copy paths.
- Updated README, docs, and benchmark notes to describe reduced-copy behavior instead of zero-copy claims.

### Fixed
- Avoided an extra `FileSource` snapshot-to-memory copy when constructing `new_file_buf_reader(...)`.
- Avoided redundant `FileSink.flush()` rewrites when no bytes are pending.
- Added coverage for `flush_to_bytes()` copy semantics, large `BufReader.read_to_end()` inputs, and empty-pending `FileSink.flush()` behavior.

### Notes
- v0.12.0 is a reduced-copy optimization release, not a zero-copy release.
- FileSource and FileSink remain memory-backed by design.

## v0.11.0

### Added
- Added an experimental benchmark baseline runner under `bench`.
- Added `docs/BENCHMARK.md` with benchmark scope, run instructions, output format, and hotspot notes.
- Added benchmark coverage for low-level buffers, memory streaming, and file convenience layers at `1KB`, `64KB`, `1MB`, and `10MB`.

### Changed
- Updated README and README_zh_CN with benchmark entry points and baseline guidance.
- Marked benchmark work as experimental baseline tracking rather than a performance marketing claim.
- Refined roadmap wording around benchmark follow-up work.

### Notes
- v0.11.0 does not add new core buffer APIs.
- Benchmark output is intended for repeatable local baselines and regression tracking.

## v0.10.0

### Changed
- Reorganized tests into black-box and white-box coverage.
- Reduced the public API surface in preparation for 1.0.
- Moved usage examples from standalone example files into README snippets.
- Updated README and docs to reflect the smaller stable public API.
- Clarified concrete-type API design and moved trait-based custom backends to the roadmap.

### Fixed
- Added missing edge-case coverage for reader, writer, streaming, conversion, split, and file APIs.
- Removed stale paths, obsolete docs references, and example-directory references.

### Removed
- Removed standalone `examples/` files in favor of README-based usage snippets.
- Removed redundant public aliases that are not part of the 1.0 API surface.

### Notes
- v0.10.0 is a pre-1.0 API narrowing and test-structure release.
- No new core I/O behavior is introduced.

## v0.9.0

### Added
- Added stress and edge-case tests across low-level buffers, memory streaming, and file I/O.
- Added examples README and clarified example usage expectations.

### Changed
- Audited documentation and examples for API consistency.
- Refined release-readiness documentation for the upcoming 1.0 release.
- Clarified legacy compatibility APIs and stable snake_case API surface.

### Fixed
- Cleaned up repository hygiene issues found during release hardening.
- Ensured generated and temporary files are not included in release-ready changes.

### Notes
- v0.9.0 is a release hardening version.
- No new core buffer behavior is introduced in this release.

## v0.8.0

### Added
- Added examples for low-level buffers, growing writers, memory streaming, file reading/writing, and roundtrip usage.
- Added API reference documentation.
- Added design notes documentation.
- Added API stability notes for the upcoming 1.0 release.

### Changed
- Reorganized README and README_zh_CN around usage layers.
- Clarified the distinction between low-level buffer APIs and streaming-style APIs.
- Clarified current file I/O limitations.

### Notes
- v0.8.0 focuses on documentation, examples, and release-readiness rather than new core buffer behavior.

## v0.7.0

### Added
- Added `FileSource` for file-backed reads.
- Added file buffered reader helpers.
- Added file read tests and read/write round-trip tests.
- Added documentation for file reading behavior.

### Changed
- Documented file sources as memory-backed snapshots rather than OS-level streaming handles.

### Notes
- v0.7.0 supports file reading through memory-backed snapshots.
- OS-level streaming file handles remain planned for future releases.

## v0.6.0

### Added
- Added `FileSink` for file-backed writes.
- Added `FileBufWriter` for buffered file writing.
- Added file writing examples and tests.
- Added file write behavior documentation.

### Changed
- Documented the distinction between memory-backed streaming and file-backed flush-time writing.

### Notes
- v0.6.0 supports file writing only.
- File reading and OS-level streaming handles are planned for future releases.

## v0.5.0

### Added
- Added memory-backed streaming primitives: `MemorySource` and `MemorySink`.
- Added buffered streaming reader support via `BufReader`.
- Added buffered streaming writer support via `BufWriter`.
- Added refill/consume/flush behavior tests.
- Added large input tests for streaming reader and writer.

### Changed
- Documented the distinction between low-level in-memory buffers and streaming-style memory APIs.

### Notes
- v0.5.0 only supports memory-backed streaming.
- File-backed sources/sinks and custom trait-based backends are planned for future releases.

## v0.4.0

### Added
- Added `new_fixed_writer` and `new_growing_writer`.
- Added writer growth policy support.
- Added `reserve` and `ensure_capacity`.
- Added tests for fixed-capacity and auto-growing writer behavior.
- Added large-write coverage for growing writers.

### Changed
- `new_writer(capacity)` is now documented as a compatibility alias for fixed-capacity writers.
- Writer capacity now represents current capacity and may grow for auto-growing writers.

### Fixed
- Ensured failed fixed-capacity writes do not partially modify the buffer.
- Preserved writer capacity after `clear()`.

## v0.3.0

### Changed
- Reworked public API naming toward snake_case.
- Clarified `BufferReader` and `BufferWriter` semantics.
- Updated README to match implemented capabilities.

### Fixed
- Added bounds checking for `skip`.
- Prevented negative remaining byte counts.
- Removed unsafe writer rewind semantics from the public API.
- Improved integer-to-byte validation.

### Added
- `read_exact`
- `read_remaining`
- `remaining_capacity`
- conversion helpers
- split edge-case tests
- unified `InvalidInput` error variant

### Deprecated
- CamelCase compatibility wrappers such as `readBytes` and `readString` may be removed in a future release.
