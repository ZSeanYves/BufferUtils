# 1.0 API Reference

Generated interfaces are the authoritative signature reference:

- buffer/pkg.generated.mbti
- io/pkg.generated.mbti
- async_io/pkg.generated.mbti
- native/pkg.generated.mbti

## Buffer

SharedBytes is an immutable shared cursor. BytesMut is a growing mutable
buffer with copy-on-write after freeze, split_to, or split_off. Buf/BufMut
expose cursor and typed integer operations.

## Sync I/O

Read, Write, BufRead, Seek, and Close are independent open traits. BufReader[R]
and BufWriter[W] implement Rust-style buffering and recovery. The combinators
are Cursor, Empty, Repeat, Take, Chain, and LineWriter.

## Native and async

The native package exports NativeFile, NativeTcpStream, NativeTcpListener, and
MappedBytes. The async package exports its own traits, seek-aware
AsyncBufReader/AsyncBufWriter wrappers, AsyncFile, memory adapters, and copy
helpers.
