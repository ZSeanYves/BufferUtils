# Design

BufferUtils 1.0 has four boundaries:

1. buffer owns pure MoonBit shared storage and COW mutation.
2. io owns fallible synchronous progress and buffering contracts.
3. async_io owns async contracts while delegating scheduling to
   moonbitlang/async.
4. native owns OS resources through per-resource external objects.

SharedBytes and immutable slices are logical zero-copy. MappedBytes is the
native physical zero-copy extension. Core Array/Bytes conversions are explicit
copies. No API claims zero-copy where lifetime or layout cannot be expressed.

The root package is intentionally empty in 1.0. This prevents two competing
Buffer, Reader, Writer, and file semantics from returning to the public
surface. TLS, compression, full codec frameworks, and UDP datagrams are
extension work, not part of the 1.0 score.
