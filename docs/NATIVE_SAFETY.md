# Native Safety

Every native file, socket, listener, and mmap view owns an independent
external object. The object stores its resource, closed state, operation
status, and platform mutex. There is no global handle registry, mutable global
resource table, or global last-error slot.

Mmap slices retain an owner reference. Closing a parent does not invalidate a
child; the owner is unmapped after the last view closes or is finalized.
copy_range materializes an owned Core Bytes value and is the explicit copy
boundary.

POSIX uses fd-level file operations and mmap; Windows uses UTF-8 to UTF-16
conversion, Win32 file mappings, and Winsock. Platform error values are mapped
to portable io.IoErrorKind values while the raw code remains diagnostic.

Close is explicit and idempotent. Finalizers are only a leak-prevention
fallback. Callers must close resources on success, error, and cancellation.
Sanitizer jobs compile the same C layer with ASan/UBSan and TSan.
