# BufferUtils

一个面向 MoonBit 的字节缓冲区工具库。

BufferUtils 提供稳定的纯 MoonBit 字节缓冲区 API，覆盖读取、写入、转换、
分割、memory-backed streaming 和文件便捷操作。

同时，它也提供 experimental native 扩展，用于 C-backed file handles 以及
基于 mmap 的 `NativeByteView` 零拷贝风格处理研究。

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
- 基于 mmap 的 experimental `NativeByteView`，采用 MoonBit-managed external owner 模型
- 在 mmap/native memory 上执行查找、计数、校验、比较和文件转写等 C-side operations
- CI 覆盖 Ubuntu/macOS、root package tests、native package tests 与 benchmark smoke

## 状态总览

| Area | Status | Notes |
|---|---|---|
| Root byte-buffer API | Stable | Pure MoonBit |
| Memory streaming | Stable | Memory-backed concrete types |
| File convenience APIs | Stable | Memory-backed snapshot/accumulator |
| Reader/source `BytesView` inspection | Experimental | 仅限 MoonBit-managed memory |
| Native C file handles | Experimental | 仅 `--target native` |
| NativeByteView mmap research | Experimental | Unix-like verified, explicit close |
| Stable zero-copy | Not claimed | 没有稳定的 C-memory-backed MoonBit `BytesView` |
| Windows mmap | Not supported | Future work |
| Thread-safe mmap owner model | Not guaranteed | Single-thread assumption |

## 什么是稳定的

稳定的 root package 是纯 MoonBit API：

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

BufferUtils 1.x 稳定的是这个 root API 边界，不是 experimental native
扩展。

## 什么是 experimental

BufferUtils 有意把以下能力放在 stable root API 之外：

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

experimental 不等于隐藏，而是表示：这些能力可用、可文档化、可测试，但不属于
stable root API 的兼容承诺。

## Installation

```bash
moon add ZSeanYves/bufferutils
```

或在 `moon.mod.json` 中添加：

```json
{
  "deps": {
    "ZSeanYves/bufferutils": "0.24.0"
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

### Experimental Native File-handle Backend

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

### Experimental NativeByteView Zero-copy Research

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

它的 owner 是通过 MoonBit documented external-object FFI 路径创建的
MoonBit-managed external object。这改进了 owner 生命周期管理，但仍然
没有把底层 C memory 变成稳定的 MoonBit `BytesView` bridge。

这里必须把边界讲得非常明确：

- `NativeByteView` 不是 MoonBit `BytesView`
- 它不是 stable zero-copy API
- 仍然推荐显式 `close()`
- finalizer 只是兜底，不是 prompt-release guarantee
- 不保证线程安全
- Windows mmap 当前仍不支持

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

### Local Observations

下面这张表总结了当前仓库最近几次本地 native-target benchmark run 的代表性观测。
它们只是本地观测，不是吞吐保证。

| Case | 10MB 本地观测 | 含义 |
|---|---:|---|
| `native_file_source_read_chunk_experimental` | ~2200-2600 MiB/s | native chunked read，受 cache 明显影响 |
| `native_file_sink_write_flush_experimental` | ~175-190 MiB/s | native write + flush path |
| `native_buffered_reader_read_to_end_experimental` | ~205-215 MiB/s | native buffered reader |
| `native_buffered_writer_write_flush_experimental` | ~170-190 MiB/s | native buffered writer |
| `native_mmap_view_find_byte_experimental` | ~3200-3400 MiB/s | C-side mmap scan |
| `native_mmap_view_count_byte_experimental` | ~10800-11900 MiB/s | C-side full scan/count |
| `native_mmap_view_checksum_experimental` | ~920 MiB/s | C-side checksum |
| `native_mmap_view_crc32_experimental` | ~150 MiB/s | C-side CRC32 |
| `native_mmap_view_copy_range_explicit_copy` | ~2650-2860 MiB/s | 显式复制到 MoonBit array |
| `native_mmap_view_copy_to_file_experimental` | ~3940-4040 MiB/s | native-side transfer |
| `native_mmap_view_slice_count_byte_experimental` | ~16500-16700 MiB/s | slice view 上的 C-side count |

### 性能优势来自哪里

Native zero-copy research path 的优势，不是“把 C memory 变成 MoonBit
`BytesView`”。它并没有做到。

真正的优势在于：大块数据继续保留在 mmap/native memory 中，由 C 侧直接完成
查找、计数、相等性判断、校验和文件转写。MoonBit 只接收 `Int` / `Bool` 等小结果，
或者通过 `copy_range(...)` 显式请求复制。

### 这些数字不代表什么

这些 benchmark 数字不是性能保证。native file 与 mmap benchmark 会明显受到
page cache、filesystem cache、CPU、OS、compiler、MoonBit runtime 版本以及
fixture setup 的影响。

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
   - 面向 MoonBit-managed memory 的 non-consuming read-only slice
3. Experimental native file-handle API
   - `NativeFileSource`、`NativeFileSink`、`NativeBufReader`、`NativeBufWriter`
4. Experimental native zero-copy research API
   - `NativeByteView` 与 `new_mmap_file_view(...)`

stable 1.x 的边界是 root pure-MoonBit API。experimental 层仍然可用，但不属于
这个稳定承诺的一部分。

## Safety and Limitations

- `FileSource` 仍然是 memory-backed snapshot
- `FileSink` 仍然是 memory-backed accumulator + flush-time overwrite
- experimental reader/source `BytesView` API 会返回 `BytesView`，但 BufferUtils 不保证 runtime-level 的 shared-storage 行为
- native API 需要 `--target native`、C toolchain 与显式 `close()`
- `NativeByteView` 是 native-only research API，不是 MoonBit `BytesView`
- `NativeByteView` 使用 MoonBit-managed external owner，并带有 finalizer 兜底，但仍然没有可预测的 automatic destructor 契约
- `NativeByteView` 目前只在 Unix-like native target 上验证；Windows mmap support 仍不支持
- native shared-owner bookkeeping 不提供线程安全保证
- BufferUtils 不宣称 stable zero-copy，也不宣称 stable mmap
- stable root package 不提供 async I/O

## Documentation Map

- [docs/API.md](./docs/API.md)：API reference 与 stable / experimental 分层
- [docs/DESIGN.md](./docs/DESIGN.md)：当前架构与设计边界
- [docs/BENCHMARK.md](./docs/BENCHMARK.md)：benchmark guide、methodology 与 caveats
- [docs/VIEW_API.md](./docs/VIEW_API.md)：experimental root `BytesView` inspection 说明
- [docs/NATIVE_BACKEND.md](./docs/NATIVE_BACKEND.md)：experimental native file-handle backend 概览
- [docs/NATIVE_SAFETY.md](./docs/NATIVE_SAFETY.md)：native 生命周期与安全说明
- [docs/MMAP_FEASIBILITY.md](./docs/MMAP_FEASIBILITY.md)：mmap feasibility 与当前状态
- [docs/ZERO_COPY_RESEARCH.md](./docs/ZERO_COPY_RESEARCH.md)：`NativeByteView` 研究设计说明
- [docs/STREAMING_FEASIBILITY.md](./docs/STREAMING_FEASIBILITY.md)：pure-MoonBit streaming feasibility 背景

## Roadmap

- 继续保持 stable root pure-MoonBit API 小而清晰
- 持续观察 experimental `BytesView` API，再决定是否稳定化
- 继续在更多 target / CI 环境下硬化 native backend
- 在 ownership、portability、concurrency 问题更清楚之前，让 `NativeByteView` 继续保持明确的 experimental 定位
- 继续做 reduced-copy 与 benchmark regression tracking，同时避免夸大 zero-copy 结论

## License

Apache-2.0
