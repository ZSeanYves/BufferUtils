# BufferUtils

一个面向 MoonBit 的字节缓冲工具库。

BufferUtils 提供稳定的 pure-MoonBit 字节缓冲 API，用于读取、写入、
转换、分割、内存后端 streaming，以及文件便捷读写工作流。同时它也包含
面向 native target 的 experimental 扩展，用于 C-backed file handle I/O
和基于 mmap 的 `NativeByteView` 研究。

BufferUtils 不宣称 stable zero-copy。`NativeByteView` 是 experimental 的
native-only research API，不是 MoonBit `BytesView`。

[English](https://github.com/ZSeanYves/BufferUtils/blob/main/README.md) | [简体中文](https://github.com/ZSeanYves/BufferUtils/blob/main/README_zh_CN.md)

## Highlights

- 稳定的 root API，覆盖 byte reader、writer、memory source/sink 与 file convenience helper
- 同时支持 fixed-capacity 与 auto-growing writer
- 带边界检查的读写、转换与 split 工具
- memory-backed `BufReader` / `BufWriter`
- 采用 overwrite-materialization flush 语义的 file convenience API
- 面向 native target 的 experimental native C backend
- 基于 mmap 的 experimental `NativeByteView`，用于 C-side zero-copy-style processing 研究
- CI 覆盖 Ubuntu/macOS、root package tests、native package tests 与 benchmark smoke

## 1.0 中什么是稳定的

稳定的 root package 是 pure MoonBit API：

- `BufferReader` / `BufferWriter`
- `MemorySource` / `MemorySink`
- `BufReader` / `BufWriter`
- `FileSource` / `FileSink`
- `FileBufWriter` / `new_file_buf_reader`
- conversion helpers
- split helpers
- `BufferError`

stable root package 对文件语义保持明确：

- `FileSource` 是构造时生成的 memory-backed snapshot
- `FileSink` 是 memory-backed accumulator，并在 `flush()` 时持久化
- `FileSink.flush()` 使用 overwrite-materialization 语义；即使当前累计数据为空，也会创建或覆盖一个空文件

## 什么是 experimental

BufferUtils 故意把下面这些能力放在 stable root API 之外：

- reader/source 侧 `BytesView` inspection API：
  - `BufferReader.peek_slice`
  - `BufferReader.remaining_slice`
  - `MemorySource.peek_remaining`
  - `FileSource.peek_remaining`
- `ZSeanYves/bufferutils/native` 下的 native file-handle API：
  - `NativeFileSource`
  - `NativeFileSink`
  - `NativeBufReader`
  - `NativeBufWriter`
- `ZSeanYves/bufferutils/native` 下的 native zero-copy research API：
  - `NativeByteView`
  - `new_mmap_file_view`
  - `NativeByteView.slice_handle`
  - `NativeByteView` 的 C-side operations

experimental 不等于隐藏能力，而是表示：它们可用、可文档化、可测试，但
不属于 stable 1.0 的兼容承诺。

## Installation

```bash
moon add ZSeanYves/bufferutils
```

或在 `moon.mod.json` 中添加：

```json
{
  "deps": {
    "ZSeanYves/bufferutils": "0.23.0"
  }
}
```

## Quick Start

### In-memory Reading

```moonbit
let reader = new_reader(Bytes::from_array([1, 2, 3, 4]))

let first = reader.read_byte()
let next_two = reader.read_exact(2)
let rest = reader.read_remaining()
```

### Fixed And Growing Writers

```moonbit
let fixed = new_fixed_writer(4)
fixed.write_all([1, 2, 3, 4])
let fixed_bytes = fixed.flush_to_bytes()

let growing = new_growing_writer(2)
growing.write_all([1, 2, 3, 4, 5])
growing.reserve(16)
growing.ensure_capacity(32)
let growing_bytes = growing.flush_to_bytes()
```

`new_writer(capacity)` 仍然保留为 fixed-capacity writer 的兼容入口，但更推荐
面向正式发布的 `new_fixed_writer` 与 `new_growing_writer`。

### Memory-backed Streaming

```moonbit
let source = new_memory_source(Bytes::from_array([1, 2, 3, 4, 5]))
let reader = new_buf_reader(source, 2)
let data = reader.read_to_end()

let sink = new_memory_sink()
let writer = new_buf_writer(sink, 2)
writer.write_all([10, 20, 30, 40])
writer.flush()
let sink = writer.into_inner()
let out = sink.to_bytes()
```

`BufReader` / `BufWriter` 是基于 concrete memory-backed type 的
streaming-style API。BufferUtils 当前并不提供稳定的 trait-based custom
source/sink 抽象。

### File Convenience APIs

```moonbit
let writer = new_file_buf_writer(".tmp/out.bin", 4)
writer.write_all([72, 101, 108, 108, 111])
writer.flush()

let reader = new_file_buf_reader(".tmp/out.bin", 4)
let header = reader.read_exact(2)
let rest = reader.read_to_end()
```

`FileSource` / `FileSink` 是 convenience API，不是 OS-level streaming file
handle。`FileSource` 会先把文件 snapshot 到内存中；`FileSink` /
`FileBufWriter` 会先在内存里累计，再在 `flush()` 时写回磁盘。

### Native File-handle Backend Experimental

```moonbit
import {
  "ZSeanYves/bufferutils/native" @native,
}

let sink = @native.new_native_file_sink(
  ".tmp/native-out.bin",
  @native.NativeFileMode::Overwrite,
)
sink.write_all([1, 2, 3, 4])
sink.flush()
sink.close()

let source = @native.new_native_file_source(".tmp/native-out.bin")
let chunk = source.read_chunk(2)
source.close()
```

native backend 当前是 experimental，并且只支持 native target。它需要
`--target native`、可用的 C toolchain，以及显式 `close()`。它不会替代
stable pure MoonBit 文件便捷层。

### NativeByteView Zero-copy Research Experimental

```moonbit
import {
  "ZSeanYves/bufferutils/native" @native,
}

let view = @native.new_mmap_file_view(".tmp/native-view.bin")
let first = view.read_byte_at(0)
let prefix = view.copy_range(0, 8)
let found = view.find_byte((42).to_byte())
let count = view.count_byte((0).to_byte())
let checksum = view.checksum_u64()
let starts = view.starts_with([1, 2, 3])
view.close()
```

`NativeByteView` 是一个 experimental native-only research handle，用于
Unix-like target 上的只读 mmap-backed access。

这里必须把边界讲得非常明确：

- 它不是 MoonBit `BytesView`
- 它不是 stable zero-copy API
- 它需要显式 `close()`
- 它没有 automatic destructor 契约
- 它没有线程安全保证
- Windows mmap support 当前仍不支持

这条路径的性能优势，不是“把 C 内存变成 MoonBit `BytesView`”。它并没有做到。
真正的优势在于：大块数据可以继续留在 native 或 mmap memory 中，由 C 侧直接
完成查找、计数、校验、前缀判断、相等性判断以及文件转写。MoonBit 只接收小结果，
例如 `Int` 或 `Bool`，或者通过 `copy_range(...)` 显式请求复制。

## Performance Overview

BufferUtils 提供了一个 native benchmark runner，用于本地回归追踪：

```bash
moon run src/bench --target native --release
```

runner 会输出 CSV 风格结果：

```text
name,size,bytes,temp_file,mean_us,throughput_mib_per_s,runs
```

当前 benchmark suite 覆盖：

- pure in-memory buffer operations
- memory-backed streaming APIs
- memory-backed file convenience APIs
- experimental native file-handle APIs
- experimental mmap-backed `NativeByteView` operations

### Benchmark Methodology

当前 benchmark runner 使用：

- 每个 case / size 做 `1` 次 warmup
- 每个 case / size 做 `5` 次 measured runs
- `mean_us` 取 measured runs 的算术平均值
- `.tmp/bufferutils-bench/` 作为 benchmark 临时文件目录

它的目标是做可重复的本地 regression tracking，而不是产出可发布的性能宣传数据。

### Local Benchmark Observations

下面这张表来自当前仓库的一次本地 native-target benchmark run。它们只是本地观测，
不是吞吐保证。

| Case | 10MB 本地观测 | 解释 |
|---|---:|---|
| `native_file_source_read_chunk_experimental` | ~2622 MiB/s | native chunked read path，受 filesystem cache 明显影响 |
| `native_file_sink_write_flush_experimental` | ~178 MiB/s | native file sink write + flush |
| `native_buffered_reader_read_to_end_experimental` | ~215 MiB/s | buffered native reader path |
| `native_buffered_writer_write_flush_experimental` | ~185 MiB/s | buffered native writer path |
| `native_mmap_view_find_byte_experimental` | ~3313 MiB/s | C-side mmap scan，不会物化大块 MoonBit array |
| `native_mmap_view_count_byte_experimental` | ~11446 MiB/s | C-side full scan/count，对 cache 非常敏感 |
| `native_mmap_view_checksum_experimental` | ~835 MiB/s | mmap-backed memory 上的 C-side checksum |
| `native_mmap_view_crc32_experimental` | ~137 MiB/s | C-side CRC32 checksum |
| `native_mmap_view_copy_range_explicit_copy` | ~2540 MiB/s | 从 native view 显式复制到 MoonBit array |
| `native_mmap_view_copy_to_file_experimental` | ~3635 MiB/s | native-side transfer 到另一个文件路径 |

### What The Numbers Mean

这些 benchmark 数字最适合用来：

- 跟踪 release 之间的性能回归
- 对比 memory-backed、native-file、mmap-backed 路径的相对行为
- 观察哪些操作留在 C 侧，哪些操作需要跨回 MoonBit

例如：

- `native_mmap_view_read_byte_scan_experimental` 主要反映 per-byte FFI overhead
- `find_byte`、`count_byte`、`index_of`、`equals`、`crc32`、`checksum_u64` 更能代表 C-side zero-copy-style processing
- `copy_range` 是 explicit-copy baseline
- `copy_to_file` 是 native-side transfer path，避免了在 MoonBit 代码中先物化大数组

### What The Numbers Do Not Mean

这些数字不是性能保证。native file 与 mmap benchmark 会明显受到 page cache、
filesystem cache、CPU、OS、compiler、MoonBit runtime 版本以及 fixture setup 的影响。

不要把这些 benchmark 结果理解成：

- stable zero-copy 证明
- stable mmap 吞吐承诺
- 原始磁盘吞吐测量
- benchmark-proven high-performance guarantee

## API Layers

BufferUtils 当前有四层用户可见能力：

1. Stable root API
   - in-memory readers/writers
   - conversion helpers
   - split helpers
   - memory-backed streaming
   - memory-backed file convenience
2. Experimental root `BytesView` inspection API
   - 对 MoonBit 自身内存的 non-consuming read-only slice
3. Experimental native file-handle API
   - `NativeFileSource`、`NativeFileSink`、`NativeBufReader`、`NativeBufWriter`
4. Experimental native zero-copy research API
   - `NativeByteView` 与 `new_mmap_file_view(...)`

stable 1.0 的边界是 root pure-MoonBit API。experimental 层仍然可用，但不属于
这个稳定承诺的一部分。

## Error Handling

BufferUtils 使用：

- `BufferError`：处理 buffer、capacity、输入校验、flush 与文件 I/O 错误
- `Utf8DecodeError`：处理 UTF-8 解码失败

常见场景包括：

- `Underflow`：读取越过可用字节
- `Overflow`：fixed-capacity writer 无法继续写入
- `InvalidInput`：负长度或整数超出字节范围
- `Io` / `Flush`：文件相关失败

native package 也复用同一套 `BufferError` 家族，而不是把原始平台 errno 直接公开成
正式 API。

## Safety And Limitations

- `FileSource` 仍然是 memory-backed snapshot
- `FileSink` 仍然是 memory-backed accumulator + flush-time overwrite
- experimental reader/source `BytesView` API 会返回 `BytesView`，但 BufferUtils 不保证 runtime-level 的 shared-storage 行为
- native API 需要 `--target native`、C toolchain 与显式 `close()`
- `NativeByteView` 是 native-only research API，不是 MoonBit `BytesView`
- `NativeByteView` 目前只在 Unix-like native target 上验证；Windows mmap support 暂不支持
- native mmap registry 不提供线程安全保证
- BufferUtils 不宣称 stable zero-copy，也不宣称 stable mmap
- stable root package 没有 async I/O

## Documentation

- [docs/API.md](./docs/API.md)：API reference 与 stable / experimental 分层
- [docs/DESIGN.md](./docs/DESIGN.md)：当前架构与设计边界
- [docs/BENCHMARK.md](./docs/BENCHMARK.md)：benchmark guide、methodology 与 caveats
- [docs/VIEW_API.md](./docs/VIEW_API.md)：experimental root `BytesView` 说明
- [docs/NATIVE_BACKEND.md](./docs/NATIVE_BACKEND.md)：experimental native backend 概览
- [docs/NATIVE_SAFETY.md](./docs/NATIVE_SAFETY.md)：native 生命周期与安全说明
- [docs/MMAP_FEASIBILITY.md](./docs/MMAP_FEASIBILITY.md)：mmap feasibility 背景
- [docs/ZERO_COPY_RESEARCH.md](./docs/ZERO_COPY_RESEARCH.md)：`NativeByteView` zero-copy research 设计说明
- [docs/STREAMING_FEASIBILITY.md](./docs/STREAMING_FEASIBILITY.md)：更早的 OS-level streaming feasibility study

## Roadmap

- 稳定 root pure-MoonBit API
- 持续观察 experimental `BytesView` API，再决定是否稳定化
- 继续在更多 target / CI 环境下硬化 experimental native backend
- 在 ownership、portability、concurrency 问题更清楚之前，让 `NativeByteView` 保持明确的 research-only 定位
- 继续做 reduced-copy 与 benchmark regression tracking，同时避免夸大 zero-copy 结论

## License

Apache-2.0
