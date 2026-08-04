# BufferUtils

BufferUtils 是面向 MoonBit 的 pre-1.0 字节缓冲区与 I/O 工具库，覆盖共享
字节存储、同步 I/O、异步 I/O 和原生 I/O。0.40 有意直接破坏 0.37 源码 API，
不提供弃用兼容层。

当前源码版本为 `0.40.0-rc.1`。本仓库不会自动执行发布、打 tag 或创建
GitHub Release。

## 包职责

| 包 | 对外职责 | 目标 |
| --- | --- | --- |
| `buffer` | `SharedBytes`、`BytesMut`、`Buf`/`BufMut` 和范围操作 | 全目标 |
| `io` | 可失败的同步 I/O trait、缓冲、seek 和 adapter | 全目标 |
| `async_io` | 支持取消的异步 trait、缓冲、duplex 和 copy | native |
| `native` | 阻塞文件、TCP、mmap 和结构化 socket 地址 | native |

默认使用可移植的 `buffer`/`io`。`native` 是明确的操作系统边界，只能用于
`native` 目标。

## 最小示例

```moonbit
let mutable = @buffer.BytesMut::new(capacity=32)
mutable.put_u16_be(0x1234U.to_uint16())
mutable.put_utf8("MoonBit")
let bytes = mutable.freeze()
let prefix = bytes.slice(0, 2)
```

`SharedBytes::from_fixed_array` 会复制指定范围。只有调用者独占 backing 且
能保证后续不再修改源数组时，才可使用不安全的
`unsafe_adopt_fixed_array`。`clone`、`slice`、`split`、`freeze` 共享存储，
可变别名写入时通过 COW 分离。

同步 `BufReader::lines` 和 `split` 是惰性游标：

```moonbit
let reader = @io.BufReader::new(@io.MemoryReader::new(b"one\ntwo\n"))
let lines = reader.lines()
while lines.next() is Some(line) {
  process(line)
}
```

## API 约定

`pkg.generated.mbti` 是唯一权威的公开接口。命名统一为：方法和字段使用
lower snake case，类型使用 PascalCase，异步对应物使用 `Async` 前缀，操作系统
资源使用 `Native` 前缀。`get_ref`/`get_mut` 借用包装值，`into_inner` 消费
包装器。view 只保证在所属对象的下一次操作前有效。

内存、I/O 和 native 的计数器只是测试与 benchmark 的诊断钩子，不是同步原语或
正确性状态。`examples` 包属于可执行文档，不纳入四个核心包的兼容承诺。

0.40 的稳定范围包括可表达的 8/16/32/64 位整数和浮点 typed helpers、短读写与
错误合同、惰性游标、vectored fallback、buffer 恢复、有界内存 duplex 以及
native close 安全。TLS、压缩、UDP、codec 框架、io_uring、Rust 所有权等价、
u128/i128 和未初始化内存接口不在本版本范围内。

## 验证与证据

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

CI 还要求总体覆盖率至少 95%，四个核心包各至少 90%，并执行 sanitizer 并发
检查、benchmark 结构计数和逐 case MoonBit/Rust 回归门禁。这些门禁不承诺
MoonBit 吞吐绝对追平 Rust。

请先阅读 [`docs/API_SURFACE.md`](docs/API_SURFACE.md) 了解公开边界，升级时阅读
[`docs/MIGRATION_0.37_TO_0.40.md`](docs/MIGRATION_0.37_TO_0.40.md)，发布前按
[`docs/RELEASE_0.40.md`](docs/RELEASE_0.40.md) 手工审查和验证 consumer。

详细语义与验证证据见 [`docs/API_CONTRACT.md`](docs/API_CONTRACT.md)、
[`docs/RUST_PARITY_MATRIX.md`](docs/RUST_PARITY_MATRIX.md)、
[`docs/NATIVE_SAFETY.md`](docs/NATIVE_SAFETY.md) 和
[`docs/BENCHMARK.md`](docs/BENCHMARK.md)。
