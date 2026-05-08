# mmap Feasibility

## Motivation

The native backend already provides experimental file-handle style I/O through
`NativeFileSource`, `NativeFileSink`, `NativeBufReader`, and
`NativeBufWriter`.

The next obvious reduced-copy investigation is a read-only file mapping path:

- avoid reading the whole file into an owned MoonBit `Bytes` snapshot
- avoid repeated chunk copies for large sequential read scenarios
- explore whether a file-backed read-only view can fit the current API model

This document records the original `v0.21.0` feasibility conclusion and the
`v0.23.0` research-track follow-up.

## Scope

This study is intentionally narrow:

- read-only mappings only
- experimental native backend only
- native target only
- no writable mmap
- no resizable mmap
- no stable root-package API
- no zero-copy claim

## Current Native Backend

Today the experimental native package provides:

- `NativeFileSource`: chunked `FILE*` reads
- `NativeFileSink`: direct `FILE*` writes with explicit `flush()` / `close()`
- `NativeBufReader`: buffered reads over `NativeFileSource`
- `NativeBufWriter`: buffered writes over `NativeFileSink`

The stable root package remains unchanged:

- `FileSource`: memory-backed file snapshot
- `FileSink`: memory-backed accumulation + flush-time overwrite

## mmap Prototype Decision

Decision progression:

- `v0.21.0`: documented-only
- `v0.23.0` research track: native-only `NativeByteView` prototype, but still
  no stable MoonBit `BytesView` bridge

Reason:

MoonBit's current native FFI gives BufferUtils enough surface to allocate owned
`Bytes` and to manage external objects, but not enough public surface to safely
construct a MoonBit `BytesView` directly from arbitrary mmap-backed memory.

During this investigation:

- `moonbit.h` exposed `moonbit_bytes_t`, `moonbit_make_bytes`, and
  `moonbit_make_bytes_raw`
- `moonbit.h` exposed `moonbit_make_external_object` for custom payloads
- the documented C FFI model distinguished MoonBit-managed abstract objects
  from plain external pointer types
- MoonBit builtin code exposed `BytesView::make(...)`, but only as the internal
  primitive `%bytesview.make`, not as a stable C FFI hook

That means BufferUtils can reliably:

- map a file region in C
- own and unmap that region in C
- copy mapped bytes into owned MoonBit `Bytes`

But it cannot currently and safely:

- expose that mapped region as a stable MoonBit `BytesView`
- tie `BytesView` validity to `munmap()` / `close()`
- guarantee safe behavior after explicit close or external file changes

`v0.23.0` therefore stops at a narrower research prototype:

- `new_mmap_file_view(path) -> NativeByteView`
- a MoonBit-managed external owner object created through
  `moonbit_make_external_object(...)`
- explicit indexed reads
- explicit-copy extraction through `copy_range(...)`
- C-side operations like `find_byte`, `checksum_u64`, and `starts_with`

This is a native-only borrowed handle backed by an external owner bridge, not a
MoonBit `BytesView`.

## API Sketch

If MoonBit later exposes a safe FFI story for borrowed/read-only byte views, the
native experimental package could revisit something like:

```moonbit
new_mmap_file_source(path : String) -> MmapFileSource raise BufferError

MmapFileSource.len() -> Int
MmapFileSource.is_empty() -> Bool
MmapFileSource.as_view() -> BytesView raise BufferError
MmapFileSource.close() -> Unit raise BufferError
MmapFileSource.is_closed() -> Bool
```

That sketch remains experimental-only and native-only. It is not part of the
stable API surface today.

The current research-track prototype instead looks like:

```moonbit
new_mmap_file_view(path : String) -> NativeByteView raise BufferError

NativeByteView.len() -> Int
NativeByteView.read_byte_at(index : Int) -> Byte raise BufferError
NativeByteView.copy_range(start : Int, len : Int) -> Array[Byte] raise BufferError
NativeByteView.find_byte(b : Byte) -> Int raise BufferError
NativeByteView.checksum_u64() -> UInt64 raise BufferError
NativeByteView.starts_with(data : Array[Byte]) -> Bool raise BufferError
NativeByteView.close() -> Unit raise BufferError
NativeByteView.is_closed() -> Bool
```

## Lifetime Model

Any future mmap-backed view would need a stricter lifetime model than the rest
of the library:

- the mapping must stay alive while the view is used
- explicit `close()` / `munmap()` would invalidate the mapping
- using a view after close would need to be forbidden
- external file truncation or mutation would remain outside BufferUtils safety
  guarantees

Current MoonBit FFI does not provide a stable way to encode this lifetime model
for public `BytesView` results.

## Platform Constraints

If BufferUtils revisits a concrete mmap prototype later, the first scope should
be Unix-like native targets only:

- macOS
- Linux

Likely system calls:

- `open`
- `fstat`
- `mmap`
- `munmap`
- `close`

Windows support is not part of this study.

## Safety Risks

Main risks that block a public experimental mmap API today:

- no stable public C-side `BytesView` construction hook
- explicit-close invalidation risk for borrowed views
- undefined behavior risk after external truncate or rewrite
- platform-specific mapping semantics
- page-fault and cache effects that do not map cleanly to simple throughput
  claims

## Benchmark Caveats

`v0.21.0` added no mmap benchmark case.

`v0.23.0` research adds native-only experimental mmap benchmark cases, but they
must still be read conservatively because they do not prove a stable
zero-copy-like API contract.

If a future prototype lands, its benchmark notes will need to separate:

- mapping or view-creation cost
- first-touch page-fault cost
- repeated cached access
- actual user-visible traversal cost

An mmap benchmark would still not prove raw disk throughput or stable zero-copy
behavior.

## Recommendation

Recommendation for now:

- keep the stable root file APIs memory-backed
- keep the current experimental native backend on the `FILE*` path for stable
  exported behavior
- keep mmap on the research path through `NativeByteView`
- defer any stable borrowed MoonBit view API until MoonBit exposes a safer
  borrowed-byte FFI story

The next useful trigger for revisiting this work would be one of:

- a stable public FFI constructor for read-only byte views
- a stable external-byte owner type with slice/view support
- a documented MoonBit-native lifetime model for externally backed views
