# Security Policy

Security fixes are supported for the latest published 0.x release only.
BufferUtils is pre-1.0 and may make documented breaking changes between minor
versions.

Report suspected memory-safety, race, path-handling, or resource-lifetime
issues privately through GitHub Security Advisories for this repository. Do
not include secrets or production data in a report. Include the operating
system, MoonBit toolchain identity, target backend, minimal reproducer, and any
ASan/UBSan/TSan output.

The native package uses C FFI and is covered by sanitizer jobs. An absence of
sanitizer findings is not a security guarantee. `unsafe_adopt_fixed_array` is
an explicit unsafe contract: mutating adopted storage while shared bytes are
reachable is unsupported.
