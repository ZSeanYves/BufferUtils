# PR-05 Public API Review

PR-05 intentionally reduces the pre-1.0 compatibility surface and adds no
public symbols. `moon info --target all` produced the reviewed interfaces;
`docs/API_ALLOWLIST.txt` records their exact declarations.

## Intentional removals

The following 13 diagnostic members are removed:

- `BufReader::bypass_read_calls`
- `BufReader::underlying_read_calls`
- `BufWriter::bypass_write_calls`
- `BufWriter::underlying_write_calls`
- `MemoryReader::read_calls`
- `MemoryWriter::write_calls`
- `MemoryWriter::flush_calls`
- `CopyProgress::read_calls`
- `CopyProgress::write_calls`
- `NativeFile::read_syscalls`
- `NativeFile::write_syscalls`
- `NativeTcpStream::read_syscalls`
- `NativeTcpStream::write_syscalls`

These values described implementation activity, not correctness state. Keeping
them public would make buffering strategy, runtime chunking, and OS call shape
permanent compatibility obligations. Synchronous call-count evidence now comes
from test and benchmark probe readers/writers. Native benchmark syscall fields
remain explicit unavailable values (`0`) rather than inferred counts.

## Migration and rollback

Callers must verify committed bytes, ordering, progress, errors, and close
state through the normal I/O contracts. `CopyProgress::bytes_copied` remains
public because it describes committed caller-visible progress.

An individual diagnostic symbol may be restored only with a migration note and
an explicit API decision explaining why the value is stable across buffering,
platform, and runtime changes. A benchmark or test need alone is insufficient;
instrumentation belongs in its fixture or generated diagnostics.

## Governance result

- `scripts/check_api_surface` compares the generated interfaces with the exact
  allowlist and always writes `.tmp/API_SURFACE_DIFF.md`.
- `scripts/check_api_names` enforces the naming and native/shared ownership
  boundaries in `ARCHITECTURE.md`.
- `docs/API_EVIDENCE.tsv` and `scripts/check_api_evidence` require generated
  documentation plus a focused test or executable example for every public API
  owner and all of its public methods.
- `MappedBytes` and `NativeTcp*` remain native resource owners. No native public
  signature exposes `SharedBytes`, and portable packages do not expose
  `MappedBytes`.
