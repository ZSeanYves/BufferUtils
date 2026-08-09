# BufferUtils

BufferUtils 是面向 MoonBit 的 pre-1.0 共享不可变字节范围、COW 可变缓冲区和
可组合同步/异步流式 I/O 基础库。0.40 有意直接破坏 0.37 源码 API，不提供弃用
兼容层。

当前源码版本为 `0.40.0-rc.2`。本仓库不会自动执行发布、打 tag 或创建
GitHub Release。

## 包职责

| 包 | 对外职责 | 目标 |
| --- | --- | --- |
| `buffer` | `SharedBytes`、`BytesMut`、`Buf`/`BufMut` 和范围操作 | 全目标 |
| `io` | 可失败的同步 I/O trait、缓冲、seek 和 adapter | 全目标 |
| `async_io` | 支持取消的异步 trait、缓冲、duplex 和 copy | native |
| `native` | 阻塞文件、TCP、mmap 和结构化 socket 地址 | native |

正式维护的 MoonBit 包全部位于 `src/`；由于 `moon.mod` 将 `src` 设为模块源根，
对外导入名仍保持为 `ZSeanYves/bufferutils/{buffer,io,async_io,native}`。根目录
`bench/` 只保留 Rust 对照工程和已提交的基线数据；MoonBit benchmark 入口为
`src/bench` 和 `src/bench_async`。

默认使用可移植的 `buffer`/`io`。`native` 是明确的操作系统边界，只能用于
`native` 目标。

## 最小示例

```moonbit
let mutable = @buffer.BytesMut::new(capacity=32)
mutable.put_u16_be(0x1234U.to_uint16())
mutable.put_utf8("MoonBit")
let bytes = mutable.freeze()
let prefix = bytes.slice(0, 2)
let cursor = bytes.cursor()
let value = cursor.get_u16_be()
```

`SharedBytes::from_fixed_array` 会复制指定范围。只有调用者独占 backing 且
能保证后续不再修改源数组时，才可使用不安全的
`unsafe_adopt_fixed_array`。`SharedBytes` 本身不可变；`clone`、`slice`、
`split_at` 和 `freeze` 共享存储，消费式读取请显式调用 `bytes.cursor()`。
`SharedBytesSplit::prefix` 和 `suffix` 返回分割范围，不会为了返回二元组而分配。
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

请先阅读[文档索引](docs/README.md)。其中依次包含[架构与合同](docs/ARCHITECTURE.md)、
[分阶段维护计划](docs/MAINTENANCE_PLAN_0.40.md)、[可复现性能证据](docs/PERFORMANCE.md)、
[合并迁移指南](docs/MIGRATION.md)以及[人工发布流程](docs/RELEASE.md)。
