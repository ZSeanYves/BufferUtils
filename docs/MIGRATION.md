# BufferUtils Migration Guide

0.40 is pre-1.0 and intentionally has no deprecation layer. The generated
interfaces and the current README are authoritative for the final RC.

## 0.37 to 0.40

### Fixed-array construction

`SharedBytes::from_fixed_array` now validates and copies the selected range.
The call shape is unchanged:

```moonbit
let shared = @buffer.SharedBytes::from_fixed_array(storage, 0, length)
```

Code with exclusive backing ownership may use:

```moonbit
let shared = @buffer.SharedBytes::unsafe_adopt_fixed_array(storage, 0, length)
```

After adoption, the caller must never mutate `storage` while the value or any
derived range remains reachable.

### Lazy lines and split

Eager arrays became cursors:

```moonbit
let lines = reader.lines()
while lines.next() is Some(line) {
  process(line)
}

let fields = reader.split(b',')
while fields.next() is Some(field) {
  process(field)
}
```

Line terminators and delimiters follow the contracts in
[ARCHITECTURE.md](ARCHITECTURE.md). I/O and UTF-8 errors are raised by the
individual `next()` operation.

### Trait and naming changes

Typed `Buf`/`BufMut` and async helpers are provided as defaults. Existing
implementations normally need no changes. Use the trait-qualified form when a
custom type has a conflicting method name.

Equivalent asynchronous names use `Async`, pending data is named
`buffered_len`, memory writers expose `to_bytes`, and progress fields use
`bytes_copied`.

Port-only native methods remain available; structured `local_addr()` and
`peer_addr()` should be preferred when family and host information matter.

## 0.40.0-rc.1 to rc.2

### Consuming reads moved to `BytesCursor`

Before:

```moonbit
let value = bytes.get_u32_be()
let prefix = bytes.split_to(4)
```

After:

```moonbit
let cursor = bytes.cursor()
let value = cursor.get_u32_be()
let prefix = cursor.split_to(4)
```

`SharedBytes` is now immutable and does not implement `Buf`. Pass
`bytes.cursor()` to `BufChain`, `BufTake`, and `BufReaderAdapter` when
consumption is required.

### Range operations

| Old operation | Current operation |
| --- | --- |
| `bytes.truncate(n)` | `bytes.prefix(n)` |
| `bytes.split_off(n)` | `bytes.split_at(n).suffix()` |
| `bytes.split_to(n)` | `bytes.cursor().split_to(n)` |
| `bytes.copy_to(dst)` | `bytes.cursor().copy_to(dst)` |
| `bytes.get_u32_be()` | `bytes.cursor().get_u32_be()` |
| `bytes.get_utf8(n)` | `bytes.cursor().get_utf8(n)` |

`split_at` returns `SharedBytesSplit`. Use `prefix()` and `suffix()` to keep
the range-only path allocation-free; use `into_parts()` when a tuple is needed.

### Ownership behavior

`BytesMut::freeze` still returns an immutable value. Later mutable writes detach
through COW when a frozen or aliased range is reachable. `from_fixed_array`
remains the safe copying constructor; `unsafe_adopt_fixed_array` is the only
explicit adoption boundary.

## Verification after migration

```bash
moon fmt --check
moon info --target all
scripts/normalize_interfaces
git diff --exit-code
moon check --target all --deny-warn
moon test --target all --deny-warn
moon doc --frozen
```

