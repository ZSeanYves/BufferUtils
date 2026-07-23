# BufferUtils

BufferUtils 1.0 is a Rust-inspired byte buffer and I/O library for MoonBit.
The 1.0 surface is intentionally split into pure core packages and a
native-only platform package.

| Package | Scope | Targets |
|---|---|---|
| ZSeanYves/bufferutils/buffer | SharedBytes, BytesMut, Buf, BufMut | wasm, wasm-gc, js, native |
| ZSeanYves/bufferutils/io | Read, Write, BufRead, Seek, Close, combinators | wasm, wasm-gc, js, native |
| ZSeanYves/bufferutils/async_io | async traits, buffered wrappers, file/socket adapters | native |
| ZSeanYves/bufferutils/native | files, TCP, mmap-backed MappedBytes | native |

The old root package is an empty module entry point. Buffer/BufferMut,
source/sink snapshots, and the old native handle API were removed in 1.0.
Use docs/MIGRATION_0.26_TO_1.0.md for the hard switch.

## Install

~~~bash
moon add ZSeanYves/bufferutils@1.0.0
~~~

## Shared bytes

MoonBit reserves the builtin identifier Bytes; BufferUtils therefore names
its immutable shared handle SharedBytes. This is the library's public name,
not a claim that conversion to Core Bytes is free.

~~~moonbit
import { "ZSeanYves/bufferutils/buffer" @buffer }

let mutable = @buffer.BytesMut::new(capacity=32)
mutable.put_u16_be(0x1234U.to_uint16())
mutable.put_utf8("MoonBit")
let immutable = mutable.freeze()
let prefix = immutable.slice(0, 2)
mutable.put_byte(b'!')
ignore(prefix)
~~~

split_to, split_off, slice, freeze, and immutable copies share storage.
Mutation after a freeze or split detaches only the mutated range. copied_bytes
is available for instrumentation. Array/Core Bytes conversions are explicit
copy boundaries.

## Synchronous I/O

~~~moonbit
import { "ZSeanYves/bufferutils/io" @io }

let source = @io.MemoryReader::new(b"header:payload", max_chunk=3)
let reader = @io.BufReader::new(source, capacity=8)
let header = Array::make(7, (0).to_byte())
@io.Read::read_exact(reader, header.mut_view())
let rest : Array[Byte] = []
@io.read_to_end(reader, rest)
~~~

The sync package implements partial progress, read_exact/write_all,
interruption retry, vectored fallback, BufRead, seekable Cursor, and the
Cursor/Empty/Repeat/Take/Chain/LineWriter combinators. BufWriter preserves
unwritten tail bytes through into_parts; finish returns the destination only
after a successful flush. IoError carries portable kind, operation, context,
path, raw code, message, and accumulated progress.

## Native files, TCP, and mmap

~~~moonbit
import {
  "ZSeanYves/bufferutils/io" @io,
  "ZSeanYves/bufferutils/native" @native,
}

let file = @native.NativeFile::create(".tmp/output.bin")
@io.Write::write_all(file, [1, 2, 3, 4][:])
@io.Write::flush(file)
@io.Seek::seek(file, @io.Start(0L))
@io.Close::close(file)

let listener = @native.NativeTcpListener::bind("127.0.0.1", 0)
let port = listener.local_port()
let mapped = @native.MappedBytes::open(".tmp/output.bin")
let first = mapped.read_byte_at(0)
ignore((port, first))
@io.Close::close(mapped)
@io.Close::close(listener)
~~~

Native resources are independent external objects with per-resource state,
mutex protection, idempotent close, and finalizer fallback. POSIX uses
open/read/write/lseek/mmap; Windows uses UTF-8 to UTF-16 file paths,
Win32 mappings, and Winsock TCP. Mmap slices retain their owner; copy_range
is the explicit copy boundary.

## Async

async_io defines AsyncRead, AsyncWrite, AsyncBufRead, AsyncSeek, and
AsyncClose, then delegates event-loop work to moonbitlang/async@0.20.2.
It includes AsyncBufReader, AsyncBufWriter, AsyncFile (independent offset),
memory adapters, fs.File/socket.Tcp adapters, copy, and
copy_bidirectional. Pending buffered writes remain recoverable on errors and
cancellation.

## Verification and performance

~~~bash
moon info && scripts/normalize_interfaces && moon fmt
moon check --target all --deny-warn
moon test --target all --deny-warn
scripts/check_api_surface
mkdir -p .tmp/bufferutils-bench
moon run bench --target native --release > .tmp/bufferutils-bench/results.csv
scripts/check_performance_budget
~~~

The benchmark uses 5 warmups and 30 samples and reports median, p95, min, max,
throughput, and copied bytes. TLS, compression, full codecs, and UDP are
deliberately outside the 1.0 denominator.
