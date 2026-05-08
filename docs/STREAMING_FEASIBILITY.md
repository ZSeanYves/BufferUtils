# OS-level Streaming Feasibility

## Scope

This document records the pure-MoonBit feasibility investigation for stable
OS-level file streaming in the root package.

It is intentionally separate from the experimental native package:

- the stable root file layer remains memory-backed
- the experimental native package now provides C-backed file-handle APIs for
  native targets
- this document explains why the stable root package still does not expose
  handle-based streaming file APIs

## Current Stable File Model

The stable root package keeps file convenience APIs simple and memory-backed:

- `FileSource`: reads a file into a byte snapshot
- `FileSink`: accumulates bytes in memory and materializes the full content on
  `flush()`
- `new_file_buf_reader(...)`: builds a buffered reader over a memory-backed file
  snapshot
- `FileBufWriter`: buffers in MoonBit and eventually flushes through
  `FileSink`

This is convenient, predictable, and portable, but it is not OS-level streaming.

## Motivation

A stable root streaming file layer would ideally provide:

- chunked reads without full-file snapshot allocation
- incremental writes without rewriting the entire accumulated file image
- explicit flush / close lifecycle
- append / overwrite control at the handle layer
- better scaling for very large files

## MoonBit File API Investigation

### Stable APIs Found

The locally available `moonbitlang/x/fs` interface is path-and-content oriented.
It currently exposes operations such as:

- `read_file_to_bytes`
- `read_file_to_string`
- `write_bytes_to_file`
- `write_string_to_file`
- `is_file`
- `create_dir`
- `path_exists`
- `is_dir`
- `remove_file`
- `read_dir`
- `remove_dir`

### Stable Handle APIs Not Found

The local interface survey did not find a stable root-package file-handle API
surface for operations such as:

- `open`
- `close`
- `read`
- `read_at`
- `write`
- `write_at`
- `append`
- `flush`

## Why Stable Root Streaming Is Deferred

The root package keeps OS-level streaming deferred because the current pure
MoonBit file surface does not provide a stable, portable, handle-oriented
contract for:

- handle lifetime and explicit release
- append semantics
- flush semantics
- partial read / write error reporting
- cross-target behavior consistency

Those are exactly the areas where resource ownership and runtime differences
start to matter more.

## Current Experimental Alternative

The experimental native package now provides a separate native-target path for
handle-based file I/O:

- `NativeFileSource`
- `NativeFileSink`
- `NativeBufReader`
- `NativeBufWriter`

That package is:

- experimental
- native-target only
- C-toolchain dependent
- explicit-close based

It exists to explore real file-handle semantics without changing the stable root
API contract.

## Compatibility With Existing APIs

If stable root streaming is ever added in the future, it should remain additive.
It would not replace the current convenience layer:

- `FileSource` should remain a memory-backed snapshot API
- `FileSink` should remain a memory-backed accumulator with overwrite
  materialization on `flush()`
- root stable users should not be forced onto native-only behavior

## Recommendation

Keep the stable root file layer memory-backed.

Continue to treat real file-handle streaming as experimental native work until
MoonBit exposes a stronger stable contract for handle ownership, flush, close,
and cross-target semantics.

## Risks

- runtime differences across targets
- resource lifetime complexity
- append semantics
- partial I/O error handling
- CI portability
- C-toolchain dependence for current native experimentation
