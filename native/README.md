# Native Package

`native` is the native-only platform extension for BufferUtils 1.0. The
portable `buffer` and `io` packages do not depend on C or a host operating
system.

## API

- `NativeFile` provides fd/handle-level read, write, flush, seek, and close.
- `NativeTcpStream` and `NativeTcpListener` provide blocking TCP byte streams.
- `MappedBytes` provides read-only mmap-backed storage with owner-retaining
  slices and explicit idempotent close.

Every resource is an independent MoonBit external object. The C payload stores
its resource, status, raw OS error, close state, and platform mutex. There is no
global handle registry or global last-error state. Finalizers are fallback
cleanup; callers should close resources explicitly.

## Platforms

POSIX builds use `open/read/write/fsync/lseek/mmap` and pthread mutexes. Windows
builds use UTF-8 to UTF-16 path conversion, Win32 file and mapping APIs,
Winsock TCP, and critical sections. Windows runtime tests run in CI.

Run native tests with:

```bash
moon test native --target native --deny-warn
```

The native package is intentionally separate from pure targets and does not
promise TLS, compression, UDP, or a writable mmap API in 1.0.
