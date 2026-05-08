# BufferUtils

BufferUtils 是一个面向 MoonBit 的字节缓冲工具库。

它提供：

- 低层内存字节读写 API
- 固定容量与自动扩容 writer
- 内存后端的 streaming-style 读写 API
- 面向文件的便捷读写层
- 一个面向 native target 的 experimental C backend package
- 一个面向 native-only 的 experimental zero-copy research handle
- UTF-8 转换与按定界符分割工具

BufferUtils 对能力边界保持明确：

- 当前不是 zero-copy
- stable 默认包里的文件能力仍然是 memory-backed convenience layer
- 当前不宣称有 benchmark 证明的性能结论

[English](https://github.com/ZSeanYves/BufferUtils/blob/main/README.md) | [简体中文](https://github.com/ZSeanYves/BufferUtils/blob/main/README_zh_CN.md)

## Overview

BufferUtils 目前分成五层：

1. `BufferReader` / `BufferWriter`：直接面向内存字节缓冲。
2. 基于低层 writer 的动态扩容能力。
3. `MemorySource`、`MemorySink`、`BufReader`、`BufWriter`：streaming-style 内存 API。
4. `FileSource`、`FileSink`、`new_file_buf_reader`、`FileBufWriter`：文件便捷层。
5. `ZSeanYves/bufferutils/native`：native-only 的 experimental C backend。

从 `v0.10.0` 开始，独立 `examples/` 目录被移除，示例代码直接维护在 README 中，避免文档和实际 API 长期漂移。

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

### Basic Buffer Reading

```moonbit
let reader = new_reader(Bytes::from_array([1, 2, 3, 4]))

let first = reader.read_byte()
let next_two = reader.read_exact(2)
let rest = reader.read_remaining()
```

### Fixed and Growing Writers

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

`new_writer(capacity)` 仍然保留为固定容量 writer 的兼容入口，但面向 1.0 的推荐构造函数是 `new_fixed_writer` 和 `new_growing_writer`。

### Memory Streaming

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

`BufReader` 和 `BufWriter` 当前是基于 concrete type 的 streaming-style API。stable 默认包仍然没有把自定义 source/sink trait 抽象作为正式公开能力。

### File Writing

```moonbit
let writer = new_file_buf_writer(".tmp/out.bin", 4)
writer.write_all([72, 101, 108, 108, 111])
writer.flush()
```

`FileSink` / `FileBufWriter` 当前是在内存中累计数据，并在 `flush()` 时覆盖写入文件，不是 append 模式，也不是 OS 级流式文件句柄。

### File Reading

```moonbit
let reader = new_file_buf_reader(".tmp/input.bin", 4)
let header = reader.read_exact(2)
let rest = reader.read_to_end()
```

`FileSource` 是内存快照模型。文件内容会在构造时一次性读入内存，之后外部对文件的修改不会反映到已创建的 source 实例上。

### File Roundtrip

```moonbit
let writer = new_file_buf_writer(".tmp/roundtrip.bin", 4)
writer.write_all([1, 2, 3, 4, 5])
writer.flush()

let reader = new_file_buf_reader(".tmp/roundtrip.bin", 2)
let out = reader.read_to_end()
```

### Experimental Native C Backend

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
let first_chunk = source.read_chunk(2)
source.close()

let writer = @native.new_native_buf_writer(
  ".tmp/native-buffered.bin",
  4,
  @native.NativeFileMode::Overwrite,
)
writer.write_all([10, 20, 30, 40, 50])
writer.close()

let reader = @native.new_native_buf_reader(".tmp/native-buffered.bin", 2)
let head = reader.read_exact(2)
let tail = reader.read_to_end()
reader.close()
```

native backend 当前是 experimental，而且只面向 native target。它通过 C `FILE*`
实现 chunk read / direct write，但不会替代现有 stable 的 pure MoonBit 文件便捷层。
使用时需要显式 `close()`。对 sink 来说，`close()` 会尝试做一次最终 `flush()`，
但如果调用方希望把 flush 错误和 close 错误分开处理，仍然应该显式调用 `flush()`。
`NativeBufReader` / `NativeBufWriter` 则是在这些 native file handle 之上继续提供
buffered refill / flush 行为，但不会把 stable root package 变成 native-only API。

### Experimental Native Zero-copy Research

```moonbit
import {
  "ZSeanYves/bufferutils/native" @native,
}

let view = @native.new_mmap_file_view(".tmp/native-view.bin")
let first = view.read_byte_at(0)
let prefix = view.copy_range(0, 8)
let found = view.find_byte((42).to_byte())
let checksum = view.checksum_u64()
let starts = view.starts_with([1, 2, 3])
view.close()
```

`NativeByteView` 是一个 native-only 的研究型 API，用来探索只读 mmap
场景下的 borrowed native memory access。它**不是**稳定的 MoonBit
`BytesView` bridge，也**不是** zero-copy 保证。

这一层故意把边界写得很明确：

- `read_byte_at(...)` 是按索引读取 native memory
- `slice_handle(...)` 提供基于共享 owner 的子视图句柄
- `copy_range(...)` 是显式 copy 边界
- `find_byte` / `count_byte` / `index_of` / `equals` / `crc32` / `checksum_u64` / `starts_with` / `copy_to_file(...)` 是更接近 C-side zero-copy processing 的实验接口

`slice_handle(...)` 仍然只是 research-only API。它通过 native shared
owner / ref-count 模型避免 parent 关闭后 child 直接悬挂，但仍然需要
显式 `close()`，也不会变成 MoonBit `BytesView`。

`owner_ref_count()` 只保留为 research/debug helper，故意不放进常规用法示例。

它属于 research API，而不是 stable root package 的正式能力。

### Experimental View / Slice API

```moonbit
let reader = new_reader(Bytes::from_array([1, 2, 3, 4]))
let head = reader.peek_slice(2)
let rest = reader.remaining_slice()

let source = new_memory_source(Bytes::from_array([1, 2, 3, 4]))
let snapshot = source.peek_remaining()
```

这些 API 是实验性的、非消费式接口，返回值类型是 `BytesView`。但 BufferUtils 目前不承诺 MoonBit 运行时一定会把它们实现成共享底层存储的不复制 view，所以应把它们理解为“只读的 slice/view 结果”，而不是 zero-copy 保证。

这些 API 当前属于 `1.0` 前的 experimental public API：

- 不推进 reader/source 的 position
- 返回只读 `BytesView`
- 边界检查和错误语义会保持清晰稳定
- 但它们不属于稳定的 copy-returning API 家族

BufferUtils 故意不在 writer/sink 侧暴露 view，因为可变缓冲、扩容、`clear()` 以及 flush 时的状态变化，会让生命周期和失效规则变得更危险。

### Convert and Split Utilities

```moonbit
let text = "MoonBit"
let utf8 = string_to_utf8_bytes(text)
let decoded = utf8_bytes_to_string(utf8)

let bytes = ints_to_bytes([65, 66, 67])
let parts = split_bytes(Bytes::from_array([1, 0, 0, 2]), (0).to_byte())
```

`ints_to_bytes` 会校验 `0..255` 范围。`utf8_bytes_to_string` 在无效 UTF-8 输入上会抛出 `Utf8DecodeError`。

## Reduced-Copy Notes

`v0.12.0`、`v0.13.0`、`v0.14.0` 和 `v0.15.0` 的重点都是 reduced-copy，而不是 zero-copy。

- `BufferWriter.flush_to_bytes()` 仍然返回 copy，不会清空 writer。
- `MemorySink.to_bytes()` 和 `FileSink.to_bytes()` 仍然返回 copy。
- `FileSource` 仍然是构造时整文件读入内存的 snapshot 模型。
- `FileSink` 仍然是先在内存中累计、再在 `flush()` 时持久化的模型。

这一轮主要把若干内部路径从逐 byte `push` 调整为按 chunk 复制或追加，但这不意味着 BufferUtils 已经具备 zero-copy 语义。

`v0.14.0` 另外增加了 reader/source 侧的 experimental view/slice 探索，`v0.15.0` 则补强了这部分的边界测试和文档说明。但它不会改变既有 copy-returning API 的语义，也不应被理解为稳定的 no-copy 契约。

## Public API Surface

当前稳定公开面刻意保持较小：

- 低层 API：`BufferReader`、`BufferWriter`、`new_fixed_writer`、`new_growing_writer`
- 内存流式 API：`MemorySource`、`MemorySink`、`BufReader`、`BufWriter`
- 文件便捷层：`FileSource`、`FileSink`、`new_file_buf_reader`、`FileBufWriter`
- 工具函数：`bytes_to_array`、`array_to_bytes`、`ints_to_bytes`、`string_to_utf8_bytes`、`utf8_bytes_to_string`、`split_bytes`、`split_array_bytes`

完整接口参考见 [docs/API.md](./docs/API.md)。

view/slice 实验说明见 [docs/VIEW_API.md](./docs/VIEW_API.md)。
experimental native backend 说明见 [docs/NATIVE_BACKEND.md](./docs/NATIVE_BACKEND.md) 和 [docs/NATIVE_SAFETY.md](./docs/NATIVE_SAFETY.md)。
read-only mmap feasibility 说明见 [docs/MMAP_FEASIBILITY.md](./docs/MMAP_FEASIBILITY.md)。
zero-copy research 说明见 [docs/ZERO_COPY_RESEARCH.md](./docs/ZERO_COPY_RESEARCH.md)。

## API Stability

BufferUtils 正在接近 `1.0`。 [docs/API.md](./docs/API.md) 中记录的 snake_case API 是计划进入 `1.0` 的主要稳定公开接口。

`new_writer(capacity)` 仍保留为 fixed writer 的兼容构造函数。更早版本里的大量兼容 wrapper 已在 `v0.10.0` 删除，以降低 1.0 之后的维护负担。

`BytesView` 相关 API 目前虽然是公开可用的，但在 `1.0` 前仍明确属于 experimental，不应被理解为稳定的 zero-copy 契约。

## Error Handling

BufferUtils 主要使用：

- `BufferError`：处理缓冲、容量、输入校验、flush 和文件 I/O 错误
- `Utf8DecodeError`：处理 UTF-8 解码失败

常见场景包括：

- `Underflow`：读取越过可用字节
- `Overflow`：固定容量 writer 无法继续写入
- `InvalidInput`：负长度或整数不在字节范围内
- `Io` / `Flush`：文件相关失败

## Design Notes

当前设计以 concrete type 为主：

- 构造函数统一使用 `new_*`
- 行为方法挂在具体类型上
- conversion / split 保留为独立 helper
- 自定义 trait-based source/sink 抽象暂缓

更多设计说明见 [docs/DESIGN.md](./docs/DESIGN.md)、[docs/VIEW_API.md](./docs/VIEW_API.md)、[docs/NATIVE_BACKEND.md](./docs/NATIVE_BACKEND.md)、[docs/NATIVE_SAFETY.md](./docs/NATIVE_SAFETY.md) 和 [docs/MMAP_FEASIBILITY.md](./docs/MMAP_FEASIBILITY.md)。

## Benchmark Baseline

`v0.11.0` 新增了一套实验性的 benchmark 基线，用于做可重复的本地性能测量；`v0.12.0` 在保持输出格式不变的前提下继续跟踪 reduced-copy 优化，`v0.13.0` 补充了 reduced-copy 回归审计和本地对比说明，`v0.14.0` 加入了 view/slice 实验对比项，`v0.15.0` 继续把这些 case 保持在 experimental 口径下，`v0.16.0` 记录了 pure-MoonBit 的 streaming feasibility study，`v0.17.0` 新增了 experimental native backend benchmark case，`v0.18.0` 继续把 native lifecycle 和错误路径说明硬化下来，`v0.19.0` 补上了 experimental native buffered benchmark case，`v0.20.0` 则继续把 benchmark 名称和文档整理成更清楚的 memory-backed / native file / native buffered 分组，`v0.21.0` 记录了为什么 experimental mmap 仍停留在 feasibility study，而不是仓促导出一个会误导使用者的公开 API，`v0.22.0` 则完成了 1.0 release-candidate audit，而 `v0.23.0` 在 research branch 上继续探索 `NativeByteView`、read-only mmap prototype 和 C-side zero-copy-style processing。

运行方式：

```bash
moon run src/bench --target native --release
```

benchmark runner 会输出 CSV 风格结果，包含耗时微秒数、数据长度、简单 throughput 估算，以及该测试是否会触碰 `.tmp/bufferutils-bench/` 下的临时文件。native backend benchmark 需要 native target 和可用的 C toolchain；当前 runner 会先做轻量 warmup，再统计重复 runs 的 `mean_us`。重复读取时文件系统缓存会明显影响结果，而小文件 case 也更容易被 fixture 分配和调用开销放大。

完整说明见 [docs/BENCHMARK.md](./docs/BENCHMARK.md)。

当前 benchmark 说明仍然只是实验性、本地性的观察，不代表固定吞吐承诺。

## Current Limitations

- 不是 zero-copy
- `FileSource` 会在构造时把整个文件读入内存
- `FileSink` 会在内存中累计数据并在 flush 时覆盖写回文件
- experimental view/slice API 可能仍然发生复制，具体取决于 MoonBit 运行时行为
- experimental native backend 目前只支持 native target
- experimental native backend 需要显式 `close()`，而 read-only mmap 当前只通过 experimental `NativeByteView` handle 暴露
- experimental native backend 当前把 handle 级读写/flush/close 失败统一映射为 `BufferError::Io`
- experimental native zero-copy research path 目前仍然没有稳定的 C memory -> MoonBit `BytesView` bridge
- 没有 async I/O
- 还没有 benchmark 结论

## Roadmap

- native backend 在更多 target / CI 环境下的硬化
- 面向 native read-only 文件 view 的 mmap feasibility study，等待更安全的 MoonBit borrowed-byte FFI 能力
- trait-based custom source/sink abstraction
- borrowed byte views
- read-only slice API stabilization
- true zero-copy investigation
- reduced-copy APIs
- benchmark baseline refinement and historical comparison tooling

## License

Apache-2.0
