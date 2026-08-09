# Native Package

`native` is the platform extension for BufferUtils 0.40. The portable `buffer`
and `io` packages do not depend on C or a host operating system.

`NativeFile` provides validated open options, borrowed read/write, flush, seek,
`sync_all`, `sync_data`, and idempotent close. `NativeTcpStream` and
`NativeTcpListener` provide blocking TCP streams with timeout and shutdown
controls. `MappedBytes` provides read-only mmap-backed storage with
owner-retaining slices; `copy_range` is the explicit copy boundary.

Every resource is an independent MoonBit external object. The C payload stores
its resource, state, raw OS error, close state, and platform mutex. There is no
global handle registry or global last-error slot. Finalizers are fallback
cleanup; callers should close resources explicitly on success, error, and
cancellation.

The native package is an opt-in backend, not a replacement for the portable
traits. Use `NativeFile` for blocking file handles, `NativeTcpStream` and
`NativeTcpListener` for TCP, and `MappedBytes` only when a read-only mmap is
appropriate. See [`docs/ARCHITECTURE.md`](../../docs/ARCHITECTURE.md) for naming,
ownership, and native-lifetime rules.

POSIX builds use `open/read/write/lseek/mmap` and pthread mutexes. Windows
builds use UTF-8 to UTF-16 path conversion, Win32 file and mapping APIs,
Winsock TCP, and critical sections. The current portable vectored API reports
capability and uses scalar fallback where a platform implementation is not
available; see [`docs/PERFORMANCE.md`](../../docs/PERFORMANCE.md) for the
measured native diagnostic scope.

Run native tests with:

```bash
moon test src/native --target native --deny-warn
```
