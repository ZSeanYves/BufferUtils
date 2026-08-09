# Migrating from 0.40.0-rc.1 to 0.40.0-rc.2

rc.2 separates immutable byte ranges from consuming cursors. This is a source
breaking change. There is no compatibility or deprecation layer.

## Consuming reads

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

The cursor owns its position. Creating another cursor from the same
`SharedBytes` starts at the beginning and does not change the original value.
Use `remaining_bytes()` or `into_remaining()` when a range value is needed.

## Removed mutable range methods

`SharedBytes` no longer has `advance`, `clear`, `truncate`, `split_to`,
`split_off`, `copy_to`, `copy_to_fixed`, `remaining`, `chunk`, typed getters,
or `get_utf8`. Use the corresponding `BytesCursor` method for consuming
operations. Use immutable range operations for values:

| rc.1 | rc.2 |
| --- | --- |
| `bytes.truncate(n)` | `bytes.prefix(n)` |
| `bytes.split_off(n)` | `bytes.split_at(n).suffix()` |
| `bytes.split_to(n)` | `bytes.cursor().split_to(n)` |
| `bytes.copy_to(dst)` | `bytes.cursor().copy_to(dst)` |
| `bytes.get_u32_be()` | `bytes.cursor().get_u32_be()` |
| `bytes.get_utf8(n)` | `bytes.cursor().get_utf8(n)` |

`SharedBytes` no longer implements `Buf`. Pass `bytes.cursor()` to APIs that
consume a `Buf`, including `BufChain`, `BufTake`, and `BufReaderAdapter`.

## Splitting without a tuple

Before:

```moonbit
let (left, right) = bytes.split_at(4)
```

After:

```moonbit
let split = bytes.split_at(4)
let left = split.prefix()
let right = split.suffix()
```

`SharedBytesSplit::into_parts()` remains available when a tuple is required,
but it is an explicit allocation boundary. Prefer `prefix()` and `suffix()` in
hot paths.

## Construction and ownership

`from_fixed_array` continues to copy the selected range. Use
`unsafe_adopt_fixed_array` only when the caller exclusively owns the backing
array and will never mutate it while any derived `SharedBytes` is reachable.
`BytesMut::freeze` still returns an immutable value and preserves copy-on-write
isolation from later mutable writes.

## Verification

After migration, run the package checks and generated-interface check:

```bash
moon info --target all
scripts/normalize_interfaces
moon check --target all --deny-warn
moon test --target all --deny-warn
moon doc --frozen
```
