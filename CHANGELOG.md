# Changelog

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
