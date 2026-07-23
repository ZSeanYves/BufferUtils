# Migration From 0.26 To 1.0

1.0 is a breaking release. There is no runtime compatibility bridge.

| 0.26 API | 1.0 API |
|---|---|
| root Buffer | buffer.SharedBytes |
| root BufferMut | buffer.BytesMut |
| Buffer::peek/slice | SharedBytes::view/slice |
| BufferMut::freeze | BytesMut::freeze |
| root Reader/Writer | io.Read/io.Write |
| root BufReader/BufWriter | io.BufReader[R]/io.BufWriter[W] |
| root MemorySource/MemorySink | io.MemoryReader/io.MemoryWriter |
| root FileSource/FileSink | native.NativeFile or async_io.AsyncFile |
| NativeByteView | native.MappedBytes |
| native integer handle IDs | opaque external objects |
| BufferError | buffer.BufferError for bounds; io.IoError for I/O |

Bytes is a MoonBit builtin and cannot be replaced by a package-local public
type without breaking generated test drivers. The immutable BufferUtils type
is therefore intentionally named SharedBytes.

Recommended migration order:

1. Move imports from the root package to buffer and io.
2. Replace snapshot file APIs with NativeFile and explicit Close.
3. Replace mmap clone/slice calls with MappedBytes::slice; use copy_range when
   an owned Core Bytes value is required.
4. Handle IoError::kind, progress, and raw_code instead of backend strings.
