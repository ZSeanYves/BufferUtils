# Native Package

`src/native` contains the experimental native-target backend for BufferUtils.

It is built with MoonBit C FFI and a small `FILE*`-based C stub.

The stable default package remains pure MoonBit. This package exists to explore:

- real file-handle reads
- real file-handle writes
- buffered file-handle reads
- buffered file-handle writes
- overwrite and append modes
- explicit flush and close behavior
- explicit native lifecycle and error-path handling

Run native-only tests with:

```bash
moon test -p ZSeanYves/bufferutils/native --target native
```

Run the shared benchmark runner with native cases enabled via:

```bash
moon run src/bench --target native --release
```

This package is experimental. It requires explicit `close()`, does not replace
the stable memory-backed file helpers, and still does not export an mmap API in
`v0.22.0`.

Read-only mmap investigation notes live in [../../docs/MMAP_FEASIBILITY.md](../../docs/MMAP_FEASIBILITY.md).
