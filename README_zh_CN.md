# 📦 BufferUtils：MoonBit 的高性能缓冲库

[English](https://github.com/ZSeanYves/BufferUtils/blob/main/README.md) | [简体中文](https://github.com/ZSeanYves/BufferUtils/blob/main/README_zh_CN.md)

[![Build Status](https://img.shields.io/github/actions/workflow/status/ZSeanYves/BufferUtils/bufferutils-ci.yml)](https://github.com/ZSeanYves/BufferUtils/actions)
[![License](https://img.shields.io/github/license/ZSeanYves/BufferUtils)](LICENSE)

**BufferUtils** 是一款为 MoonBit 打造的高性能缓冲区工具库，灵感来自 Rust 的 `BufReader` 和 `BufWriter`。该库支持高效、灵活、可组合的缓冲读写操作，具备完整错误处理、文件 I/O 支持、UTF-8 编码和类型兼容性等能力。

---

## 🚀 特性

* **缓冲读写功能**：支持 `peek`、`skip`、`rewind`、`flush`、`clear` 等流式操作。
* **多类型兼容**：支持 `Bytes`、`Array[Byte]`、`Array[Int]` 和 `String`。
* **UTF-8 编码**：通过 `string_to_utf8_bytes` 将字符串转换为 UTF-8 编码的 `Bytes`。
* **文件 I/O 集成**：通过 `writeBytes`、`writeString`、`writeInt` 等方法直接写入文件。
* **自定义容量管理**：允许设定缓冲区容量，并可动态检查剩余空间。
* **零拷贝优化**：最大限度减少不必要的复制操作。
* **统一错误体系**：所有读写操作统一抛出 `BufferError` 枚举。

---

## 📦 安装方式

```bash
moon add ZSeanYves/bufferutils
```

或在 `moon.mod.json` 中手动添加：

```json
"import": ["ZSeanYves/bufferutils"]
```

---

## 🔧 基本用法

### ✍️ 写入数据到文件

```moonbit
@ZSeanYves/bufferutils.writeString("output.txt", "hello moonbit")
@ZSeanYves/bufferutils.writeBytes("out.bin", Bytes::from_array([72, 101, 108, 108, 111]))
@ZSeanYves/bufferutils.writeInt("out_int.dat", [10, 20, 30])
```

### 🧠 大数据写入建议

```moonbit
let size = 1024 * 1024 * 100 # 100MB
let arr : Array[Byte] = []
for i in 0..<size {
  arr.push((i % 256).to_byte())
}
let path4 = "./src/examples/LargeBytes4.txt"
let data = Bytes::from_array(arr)
writeBytes(path4, data)
# 创建 BufferWriter
let writer = new_writer(size + 1024)
let written = write_bytes(writer, arr)
# 关闭 BufferWriter
writer.clear()
let read = readBytes(Bytes::from_array(written))
assert_eq(read.length(), size)
```

> new_writer(size). 你可以根据自己的需求调节size

### 🔍 从输入缓冲读取数据

```moonbit
@ZSeanYves/bufferutils.readBytes(Bytes::from_array([72, 101, 108, 108, 111]))
@ZSeanYves/bufferutils.readInts([72, 105])
@ZSeanYves/bufferutils.readString("hello")
```

---

## 📘 API 总览

### 读取函数

| 函数名                         | 功能说明            |
| --------------------------- | --------------- |
| `readBytes(Bytes)`          | 从字节流读取          |
| `readABytes([Byte])`        | 从字节数组读取         |
| `readInts([Int])`           | 从整数数组读取         |
| `readString(String)`        | 从字符串中读取内容       |
| `string_to_utf8_bytes(str)` | 将字符串转为 UTF-8 字节 |

### 写入函数

| 函数名                        | 功能说明             |
| -------------------------- | ---------------- |
| `writeBytes(path, Bytes)`  | 写入字节并刷新到文件       |
| `writeInt(path, [Int])`    | 编码后写入整数数组        |
| `writeString(path, str)`   | 写入 UTF-8 字符串     |
| `writeAbytes(path, AByte)` | 写入字节到 writer 中   |
| `writer.clear()`           | 清空并关闭 writer 缓冲区 |

---

## ⚠️ 错误处理

```moonbit
suberror BufferError {
  Overflow(String)
  Underflow(String)
  Flush(String)
  InvalidCapacity(String)
}
```

使用 `!`、`?` 或 `match` 进行优雅的错误传播。

---

## 📂 项目结构

```
BufferUtils/
├── src/lib/
│   ├── bufferutils.mbt          # 高级封装接口
│   ├── bufferutils.mbti         # 类型与函数声明
│   ├── reader.mbt               # BufferReader 方法
│   ├── writer.mbt               # BufferWriter 方法
│   ├── error.mbt                # 错误类型定义
│   ├── expand.mbt               # 辅助扩展模块
│   └── bufferutils_test.mbt     # 黑盒+白盒测试
├── moon.mod.json                # 模块定义
├── LICENSE
└── README.md
```

---

## 🧪 测试方式

运行全部测试：

```bash
moon test -p ZSeanYves/bufferutils
```

运行模拟示例：

```bash
moon run ZSeanYves/bufferutils_test
```

---

## 📜 许可证

采用 Apache-2.0 开源协议，详见 [LICENSE](./LICENSE)。
