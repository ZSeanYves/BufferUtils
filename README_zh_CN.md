# BufferUtils

BufferUtils 0.36 是 MoonBit 的零拷贝共享字节缓冲区与 I/O 工具库。核心路径
使用 `FixedArray[Byte]` 加逻辑范围保存数据，slice、split、freeze 和缓冲
尾部都共享存储；只有明确调用复制适配器时才物化新的 `Array` 或 Core
`Bytes`。

## 包结构

| 包 | 职责 | 目标 |
| --- | --- | --- |
| `buffer` | `SharedBytes`、`BytesMut`、`Buf`/`BufMut`、大小端 typed API | 全目标 |
| `io` | 可失败同步读写、缓冲、seek 与组合器 | 全目标 |
| `async_io` | 异步 trait、缓冲包装器、copy 与 stream adapter | native |
| `native` | 文件、TCP、mmap、操作系统错误映射 | native |

0.36 有意破坏 0.35 源码兼容性，升级前请阅读
[`docs/MIGRATION_0.35_TO_0.36.md`](docs/MIGRATION_0.35_TO_0.36.md)。

## 零拷贝与缓冲区

`SharedBytes` 的 clone、slice、split_to、split_off 和 `BytesMut::freeze`
共享 backing allocation。对冻结或别名范围写入时只对需要修改的范围执行
COW。`SharedBytes::as_bytes_view()` 返回固定存储上的借用 Core view，不分配；
`to_array`、`to_bytes`、`read_array`、`write_array` 明确表示复制边界。

支持有符号/无符号整数、`f32`/`f64`、大小端、UTF-8、自动扩容、spare
capacity、reclaim、split/unsplit。underflow、overflow、非法 UTF-8 和非法
范围都会返回 `BufferError`，并保持游标不变。

## 同步、native 与异步 I/O

`Read` 主接口借用 `FixedArray[Byte]` 范围，`Write` 主接口借用 `Bytes` 范围；
Array 便利接口会显式复制。`read_exact`/`write_all` 处理短读短写、
`Interrupted`、EOF 与 `WriteZero`。

`BufReader` 提供 `buffer`、`peek`、`seek_relative`、`skip_until`、`lines`、
`split`；`BufWriter` 使用 start/end 游标，只在必要时 compact，并通过
`into_parts` 保留零拷贝 pending tail。还包含 Cursor、Empty、Repeat、Take、
Chain、LineWriter、BufStream 和内存 duplex。

native 资源独立管理，带锁、幂等 close 和 finalizer 兜底；文件支持
OpenOptions、seek、flush、`sync_all`/`sync_data` 和 mmap，TCP 支持半关闭、
timeout 与地址元数据。async_io 复用同一范围校验和错误分类，copy 复用单一
固定缓冲并保留取消时的进度。

TLS、压缩、UDP、完整 codec、io_uring 和 Rust 所有权类型系统等价性不在范围内。

## 验证

```bash
moon info && scripts/normalize_interfaces && moon fmt
moon check --target all --deny-warn
moon test --target all --deny-warn
scripts/check_api_surface
moon check examples --target native --deny-warn
moon run bench --target native --release > .tmp/bufferutils-bench/results.csv
scripts/check_performance_budget
```

详细合同、对齐矩阵、性能方法和 native 安全说明见 `docs/`。
