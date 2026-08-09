# BufferUtils

BufferUtils is a pre-1.0 MoonBit library for shared immutable byte ranges,
copy-on-write mutable buffers, and composable synchronous and asynchronous
streaming I/O. The 0.40 release intentionally breaks the 0.37 source API and
does not provide a deprecation layer.

The current source version is `0.40.0-rc.2`. This repository does not publish
packages or create releases automatically.

## Packages

| Package | Public role | Target |
| --- | --- | --- |
| `buffer` | `SharedBytes`, `BytesMut`, `Buf`/`BufMut`, and zero-copy range operations | all |
| `io` | fallible synchronous I/O traits, buffering, seeking, and adapters | all |
| `async_io` | cancellation-aware async traits, buffering, duplex, and copy | native |
| `native` | blocking files, TCP, mmap, and structured socket addresses | native |

The maintained MoonBit packages live under `src/`; their public import paths
remain `ZSeanYves/bufferutils/{buffer,io,async_io,native}` because `moon.mod`
uses `src` as the module source root. The root `bench/` directory contains
only the Rust reference project and committed benchmark data; MoonBit benchmark
entry points are `src/bench` and `src/bench_async`.

Use the portable packages by default. The `native` package is an explicit
operating-system boundary and requires the native target.

## Quick start

```moonbit
let mutable = @buffer.BytesMut::new(capacity=32)
mutable.put_u16_be(0x1234U.to_uint16())
mutable.put_utf8("MoonBit")
let bytes = mutable.freeze()
let prefix = bytes.slice(0, 2)
let cursor = bytes.cursor()
let value = cursor.get_u16_be()
```

`SharedBytes::from_fixed_array` copies the selected range. The unsafe
`unsafe_adopt_fixed_array` constructor is only for an allocation exclusively
owned by the caller; the source array must not be mutated while any derived
value is reachable. `SharedBytes` is immutable: `clone`, `slice`, `split_at`,
and `freeze` share storage. Use `bytes.cursor()` for consuming reads;
`SharedBytesSplit::prefix` and `suffix` expose split ranges without a tuple
allocation. Mutable aliases detach with copy-on-write.

Synchronous `BufReader::lines` and `split` are lazy cursors:

```moonbit
let reader = @io.BufReader::new(@io.MemoryReader::new(b"one\ntwo\n"))
let lines = reader.lines()
while lines.next() is Some(line) {
  process(line)
}
```

## API policy

The generated `pkg.generated.mbti` files are the authoritative public surface.
Naming follows lower snake case for methods and fields, PascalCase for types,
`Async` for asynchronous counterparts, and `Native` for operating-system
resources. `get_ref`/`get_mut` borrow the wrapped value; `into_inner` consumes
the wrapper. Views are borrowed until the next operation on their owner.

The memory and I/O counter accessors are diagnostic hooks used by tests and
benchmarks. They are observable counters, not synchronization or correctness
state. The `examples` package is executable documentation and is outside the
compatibility promise of the four core packages.

The stable scope includes typed 8/16/32/64-bit integer and floating-point
helpers, short-progress and error contracts, lazy cursors, vectored fallback,
buffer recovery, bounded in-memory duplex, and native close safety. TLS,
compression, UDP, codec frameworks, io_uring, Rust ownership equivalence,
u128/i128, and uninitialized-memory APIs are outside 0.40.

## Verification and evidence

```bash
moon fmt --check
moon info --target all
scripts/normalize_interfaces
git diff --exit-code
moon check --target all --deny-warn
moon test --target all --deny-warn
moon doc --frozen
scripts/check_api_surface
scripts/check_critical_contracts
```

CI additionally enforces overall coverage of at least 95%, at least 90% for
each core package, sanitizer race checks, structural benchmark counters, and
per-case MoonBit/Rust ratio regression gates. These gates do not claim that
MoonBit throughput must equal Rust throughput.

Start with the [documentation index](docs/README.md). It links the
[architecture and contracts](docs/ARCHITECTURE.md), the staged
[maintenance plan](docs/MAINTENANCE_PLAN_0.40.md), the reproducible
[performance evidence](docs/PERFORMANCE.md), the combined
[migration guide](docs/MIGRATION.md), and the manual
[release procedure](docs/RELEASE.md).
