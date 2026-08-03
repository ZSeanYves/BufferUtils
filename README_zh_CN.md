# BufferUtils

BufferUtils 0.40 是 MoonBit 的共享字节缓冲区、同步 I/O、异步 I/O 与原生
I/O 工具库。本版本仍为 pre-1.0，并且有意直接破坏 0.37 API，不提供弃用
兼容层。

当前源码版本为 `0.40.0-rc.1`。在人工审查、发布和全新 consumer 安装验证
完成前，不应将其视为已发布版本。

| 包 | 职责 | 目标 |
| --- | --- | --- |
| `buffer` | `SharedBytes`、`BytesMut`、typed `Buf`/`BufMut`、chain/take | 全目标 |
| `io` | 同步 trait、缓冲、seek、惰性游标、adapter | 全目标 |
| `async_io` | 异步缓冲、惰性游标、duplex、copy | native |
| `native` | 文件、TCP、mmap、结构化地址和系统错误 | native |

升级前请阅读
[`docs/MIGRATION_0.37_TO_0.40.md`](docs/MIGRATION_0.37_TO_0.40.md)。

## 共享缓冲区

`SharedBytes::from_fixed_array` 现在安全复制指定范围。只有库内部能证明 backing
未外泄且之后绝不再修改时，才应使用 `unsafe_adopt_fixed_array`。clone、slice、
split 和 freeze 共享存储；别名后的可变写入通过 COW 分离。

```moonbit
let mutable = @buffer.BytesMut::new(capacity=32)
mutable.put_u16_be(0x1234U.to_uint16())
mutable.put_utf8("MoonBit")
let immutable = mutable.freeze()
let prefix = immutable.slice(0, 2)
```

typed helpers 覆盖 MoonBit 可表达的 8/16/32/64 位有符号、无符号、浮点及
大小端操作。越界失败不会推进游标。

## 同步、异步与原生 I/O

同步 `Read`/`Write` 保持短进度、`Interrupted`、EOF 与 `WriteZero` 合同。
`BufReader::lines` 和 `split` 返回惰性游标，不再一次性分配数组。

```moonbit
let reader = @io.BufReader::new(@io.MemoryReader::new(b"one\ntwo\n"))
let lines = reader.lines()
while lines.next() is Some(line) {
  process(line)
}
```

异步包提供 lazy lines/split、chain/take、buffered stream、有界内存 duplex、
typed helpers 和双向 copy。取消只暴露已经提交的进度，并保留尚未消费的
duplex 数据。

原生文件、socket 与 mmap 使用同步的外部状态和幂等 close。TCP 同时提供
结构化本地/对端地址与 timeout getter。文件、socket、mmap 的并发
read/write/close 合同由 ASan/UBSan/TSan 门禁验证。

TLS、压缩、UDP、codec 框架、io_uring、Rust 所有权等价、u128 与未初始化
内存接口不属于 0.40 范围。

## 验证

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

CI 还要求总体覆盖率至少 95%，`buffer`、`io`、`async_io`、`native` 各至少
90%；验证 benchmark 结构计数与逐 case MoonBit/Rust 比率；peak RSS 只作为
独立诊断数据。本项目不宣称绝对吞吐已经追平 Rust。

详细合同与证据见
[`docs/API_CONTRACT.md`](docs/API_CONTRACT.md)、
[`docs/RUST_PARITY_MATRIX.md`](docs/RUST_PARITY_MATRIX.md)、
[`docs/BENCHMARK.md`](docs/BENCHMARK.md) 和
[`docs/NATIVE_SAFETY.md`](docs/NATIVE_SAFETY.md)。
