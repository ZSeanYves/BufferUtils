# Migrating from BufferUtils 0.37 to 0.40

0.40 intentionally breaks the 0.37 source API and has no deprecation layer.

## Fixed-array construction now copies

Before, `from_fixed_array` adopted caller storage and later caller mutation
could change supposedly immutable bytes:

```moonbit
let shared = @buffer.SharedBytes::from_fixed_array(storage, 0, length)
```

After, the same call safely copies the selected range:

```moonbit
let shared = @buffer.SharedBytes::from_fixed_array(storage, 0, length)
```

Library internals with exclusive backing ownership may opt into adoption:

```moonbit
let shared = @buffer.SharedBytes::unsafe_adopt_fixed_array(storage, 0, length)
```

After `unsafe_adopt_fixed_array`, no code may mutate `storage` while the value
or any derived slice remains reachable.

## Lines are lazy and exclude terminators

0.37 returned an eager array and retained line terminators:

```moonbit
let lines : Array[String] = reader.lines()
for line in lines { process(line) }
```

0.40 returns a cursor. `next` removes `\n` and an optional preceding `\r`:

```moonbit
let lines = reader.lines()
while lines.next() is Some(line) {
  process(line)
}
```

I/O and UTF-8 failures are raised by the individual `next` call. Use
`into_inner` to recover the buffered reader.

## Delimiter splitting is lazy

0.37 eagerly materialized all segments:

```moonbit
let fields : Array[Bytes] = reader.split(b',')
```

0.40 advances one segment at a time:

```moonbit
let fields = reader.split(b',')
while fields.next() is Some(field) {
  process(field)
}
```

The delimiter is not included. A trailing delimiter produces a final empty
segment, matching the documented cursor contract.

## New trait helpers may affect custom implementations

`Buf`, `BufMut`, `AsyncRead`, and `AsyncWrite` gained default typed helpers.
Existing implementations normally need no changes. If a type defines methods
with the same names outside these traits, call the intended trait explicitly:

```moonbit
let value = @buffer.Buf::get_u32_le(source)
```

## New address type

Port-only methods remain available. Prefer structured addresses when host and
family matter:

```moonbit
let local = stream.local_addr()
let peer = stream.peer_addr()
```

## Naming cleanup

The 0.40 RC uses the same names for equivalent synchronous and asynchronous
operations. Replace the old async-only spellings:

```moonbit
// before
let pending = writer.pending_len()
let output = memory_writer.bytes()
let completed = progress.bytes

// after
let pending = writer.buffered_len()
let output = memory_writer.to_bytes()
let completed = progress.bytes_copied
```

`AsyncMemoryWriter` now uses `BytesMut` backing so writes use the same bulk and
COW paths as the core buffer package. Code that read its `data` field as an
`Array[Byte]` must use the snapshot accessor:

```moonbit
// before
let output = writer.data

// after
let output = writer.to_bytes()
```

Construct the writer with `AsyncMemoryWriter::new`; do not rely on a backing
container type when creating fixtures.

The `examples` package remains executable documentation and is outside the
compatibility promise of the four core packages.

## Verification

Run `moon info --target all` and compile all targets after migrating. Replace
all eager `lines`/`split` uses and the renamed async methods before updating the
dependency constraint.
