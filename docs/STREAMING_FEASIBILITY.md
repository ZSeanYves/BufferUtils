# OS-level Streaming Feasibility

## Current File Model

- `FileSource`: memory-backed snapshot
- `FileSink`: memory-backed accumulation + flush-time overwrite

## Motivation

- avoid full-file memory snapshots
- support larger files
- support append / incremental writing
- reduce repeated full-buffer writes

## MoonBit File API Investigation

### APIs Found

The local `moonbitlang/x/fs` interface currently exposes:

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

### APIs Missing

I did not find stable exported file-handle APIs in the currently available local MoonBit interfaces:

- `open`
- `close`
- `read`
- `read_at`
- `write`
- `write_at`
- `append`
- `flush`

### Constraints

- the current exported `fs` surface is path-and-content oriented, not handle oriented
- there is no stable exported flush/close lifecycle for file handles in the local interface survey
- append semantics are not exposed as a dedicated stable API
- target/runtime differences would matter a lot for handle lifetime and resource release

## Possible Future Design

### StreamingFileSource

Expected behavior:

- open a file handle
- read chunks
- EOF returns `0`
- close or release the handle

### StreamingFileSink

Expected behavior:

- open a file handle
- write chunks
- flush
- close
- append or overwrite mode

## Compatibility With Existing APIs

These future types would not replace the existing memory-backed convenience layer:

- `FileSource` stays a snapshot source
- `FileSink` stays a memory-backed accumulator

## Recommendation

Keep the stable root file layer memory-backed for `1.0`, and route real file-handle experimentation through a separate native backend package.

## Risks

- runtime differences
- resource lifetime
- error handling
- append semantics
- CI portability
- no stable handle API to rely on today
- the current native backend remains experimental and C-toolchain dependent
