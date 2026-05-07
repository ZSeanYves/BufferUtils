# BufferUtils

BufferUtils 是一个面向 MoonBit 的字节缓冲工具库。

它提供：

- 低层内存字节读写 API
- 固定容量与自动扩容 writer
- 内存后端的 streaming-style 读写 API
- 面向文件的便捷读写层
- UTF-8 转换与按定界符分割工具

BufferUtils 对能力边界保持明确：

- 当前不是 zero-copy
- 当前不是 OS 级流式文件句柄
- 当前不宣称有 benchmark 证明的性能结论

[English](https://github.com/ZSeanYves/BufferUtils/blob/main/README.md) | [简体中文](https://github.com/ZSeanYves/BufferUtils/blob/main/README_zh_CN.md)

## Overview

BufferUtils 目前分成四层：

1. `BufferReader` / `BufferWriter`：直接面向内存字节缓冲。
2. 基于低层 writer 的动态扩容能力。
3. `MemorySource`、`MemorySink`、`BufReader`、`BufWriter`：streaming-style 内存 API。
4. `FileSource`、`FileSink`、`new_file_buf_reader`、`FileBufWriter`：文件便捷层。

从 `v0.10.0` 开始，独立 `examples/` 目录被移除，示例代码直接维护在 README 中，避免文档和实际 API 长期漂移。

## Installation

```bash
moon add ZSeanYves/bufferutils
```

或在 `moon.mod.json` 中添加：

```json
{
  "deps": {
    "ZSeanYves/bufferutils": "0.10.0"
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

`BufReader` 和 `BufWriter` 当前是基于 concrete type 的 streaming-style API。`v0.10.0` 还没有把自定义 source/sink trait 抽象作为正式公开能力。

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

### Convert and Split Utilities

```moonbit
let text = "MoonBit"
let utf8 = string_to_utf8_bytes(text)
let decoded = utf8_bytes_to_string(utf8)

let bytes = ints_to_bytes([65, 66, 67])
let parts = split_bytes(Bytes::from_array([1, 0, 0, 2]), (0).to_byte())
```

`ints_to_bytes` 会校验 `0..255` 范围。`utf8_bytes_to_string` 在无效 UTF-8 输入上会抛出 `Utf8DecodeError`。

## Public API Surface

当前稳定公开面刻意保持较小：

- 低层 API：`BufferReader`、`BufferWriter`、`new_fixed_writer`、`new_growing_writer`
- 内存流式 API：`MemorySource`、`MemorySink`、`BufReader`、`BufWriter`
- 文件便捷层：`FileSource`、`FileSink`、`new_file_buf_reader`、`FileBufWriter`
- 工具函数：`bytes_to_array`、`array_to_bytes`、`ints_to_bytes`、`string_to_utf8_bytes`、`utf8_bytes_to_string`、`split_bytes`、`split_array_bytes`

完整接口参考见 [docs/API.md](./docs/API.md)。

## API Stability

BufferUtils 正在接近 `1.0`。 [docs/API.md](./docs/API.md) 中记录的 snake_case API 是计划进入 `1.0` 的主要稳定公开接口。

`new_writer(capacity)` 仍保留为 fixed writer 的兼容构造函数。更早版本里的大量兼容 wrapper 已在 `v0.10.0` 删除，以降低 1.0 之后的维护负担。

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

更多设计说明见 [docs/DESIGN.md](./docs/DESIGN.md)。

## Current Limitations

- 不是 zero-copy
- 没有 OS 级流式文件句柄
- `FileSource` 会在构造时把整个文件读入内存
- `FileSink` 会在内存中累计数据并在 flush 时覆盖写回文件
- 没有 async I/O
- 还没有 benchmark 结论

## Roadmap

- trait-based custom source/sink abstraction
- OS-level streaming file handles
- `FileSink` append mode
- reduced-copy APIs
- benchmarks

## License

Apache-2.0
