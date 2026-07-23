# BufferUtils

BufferUtils 1.0 是面向 MoonBit 的 Rust 风格字节缓冲区与 I/O 库。公共
API 分为纯核心包和 native 平台包。

| 包 | 范围 | 目标 |
|---|---|---|
| ZSeanYves/bufferutils/buffer | SharedBytes、BytesMut、Buf、BufMut | wasm、wasm-gc、js、native |
| ZSeanYves/bufferutils/io | Read、Write、BufRead、Seek、Close、组合器 | wasm、wasm-gc、js、native |
| ZSeanYves/bufferutils/async_io | 异步 traits、缓冲包装器、文件/socket adapter | native |
| ZSeanYves/bufferutils/native | 文件、TCP、mmap 的 MappedBytes | native |

旧 root 包只保留为空的模块入口。Buffer/BufferMut、source/sink 快照和
旧 native 句柄 API 已在 1.0 删除，迁移表见
docs/MIGRATION_0.26_TO_1.0.md。

## 共享字节

MoonBit 已经占用内置标识符 Bytes，因此本库不可变共享句柄命名为
SharedBytes。它不表示转换为 Core Bytes 一定是零成本。

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

split_to、split_off、slice、freeze 和 immutable clone 共享存储；冻结或
拆分后的修改只在修改边界发生 COW。copied_bytes 可用于性能计数。
转换为 Array/Core Bytes 是明确的复制边界。

## 同步 I/O

io 包提供短读短写、read_exact/write_all、Interrupted 重试、vectored
fallback、BufRead、Seekable Cursor 以及 Empty/Repeat/Take/Chain/LineWriter。
BufWriter::into_parts 在 flush 错误后保留未写 tail，finish 只在 flush
成功后返回底层对象。IoError 统一携带可移植 kind、operation、context、
path、raw code、message 和累计 progress。

## Native 与异步

native 的每个文件、TCP、mmap view 都是独立 external object，带有资源状态、
mutex、幂等 close 和 finalizer 兜底。POSIX 使用 fd/mmap，Windows 使用
UTF-8 到 UTF-16 路径转换、Win32 mapping 和 Winsock。

async_io 定义自己的 AsyncRead、AsyncWrite、AsyncBufRead、AsyncSeek、
AsyncClose，复用 moonbitlang/async@0.20.2 的 event loop，提供
AsyncBufReader、AsyncBufWriter、独立 offset 的 AsyncFile、内存/file/socket
adapter 以及 copy_bidirectional。

## 验证

~~~bash
moon info && scripts/normalize_interfaces && moon fmt
moon check --target all --deny-warn
moon test --target all --deny-warn
scripts/check_api_surface
mkdir -p .tmp/bufferutils-bench
moon run bench --target native --release > .tmp/bufferutils-bench/results.csv
scripts/check_performance_budget
~~~

TLS、压缩、完整 codec 和 UDP 不纳入 1.0 的能力矩阵分母。
