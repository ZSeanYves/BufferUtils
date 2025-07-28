# 📦 BufferUtils: MoonBit 高性能缓冲 I/O 工具库

[English](https://github.com/ZSeanYves/BufferUtils/blob/main/README.md) | [简体中文](https://github.com/ZSeanYves/BufferUtils/blob/main/README_zh_CN.md)

[![构建状态](https://img.shields.io/github/actions/workflow/status/ZSeanYves/BufferUtils/bufferutils-ci.yml)](https://github.com/ZSeanYves/BufferUtils/actions)
[![协议](https://img.shields.io/github/license/ZSeanYves/BufferUtils)](LICENSE)

**BufferUtils** 是一个面向 MoonBit 的性能高效缓冲工具库，方便对字节流进行阅读、写入和转换操作。受 Rust 中 `BufReader`/》BufWriter\` 含置启发，支持安全的 I/O 处理、多类型互操、接口组合以及常用操作的拓展工具。

---

## 🚀 功能特性

* 支持缓冲阅读/写入（peek、skip、rewind、flush、clear）
* 多类型互操：`Bytes`、`Array[Byte]`、`Array[Int]`、`String`
* UTF-8 编解码支持
* 自定义缓冲区容量
* 文件写入支持
* 统一的错误处理系统
* 零拷贝设计（zero-copy）
* 安全套装版本接口
* `expand.mbt`中附加工具：分割,utf8 转换、错误性处理

---

## 📦 安装

```bash
moon add ZSeanYves/bufferutils
```

或手动添加至 `moon.mod.json`：

```json
"import": ["ZSeanYves/bufferutils"]
```

---

## 🔧 快速上手

### ✍️ 文件写入

```moonbit
@ZSeanYves/bufferutils.writeString("output.txt", "hello moonbit")
@ZSeanYves/bufferutils.writeBytes("data.bin", Bytes::from_array([72, 105]))
@ZSeanYves/bufferutils.writeInt("data.int", [1, 2, 3])
```

### 🧠 缓冲操作

```moonbit
let arr = [104, 101, 108, 108, 111]  # "hello"
let writer = new_writer(128)
let _ = write_bytes(writer, arr)
let flushed = writer.flush()
let reader = new_reader(Bytes::from_array(flushed))
let data = read_bytes(reader)  # 返回 Array[Byte]
```

### 🔍 多类型读取

```moonbit
readBytes(Bytes::from_array([72, 105]))     # → [72, 105]
readABytes([97, 98, 99])                    # → [97, 98, 99]
readInts([104, 101, 108])                   # → [104, 101, 108]
readString("moon")                          # → [109, 111, 111, 110]
```

---

## 🧰 API 概览

### 🔵 读取接口

| 函数                   | 描述                 |
| -------------------- | ------------------ |
| `readBytes(Bytes)`   | 从 `Bytes` 读取数据     |
| `readABytes([Byte])` | 从 `Array[Byte]` 读取 |
| `readInts([Int])`    | 把 `Int` 转换为字节      |
| `readString(String)` | UTF-8 字符串转字节       |
| `read_from(reader)`  | trait 通用读取接口       |

### 🕠 写入接口

| 函数                                    | 描述              |
| ------------------------------------- | --------------- |
| `writeBytes(path, Bytes)`             | 将原始字节写入文件       |
| `writeInt(path, [Int])`               | 将整数组写入文件        |
| `writeString(path, str)`              | 写入 UTF-8 字符串    |
| `write_bytes(writer, AByte)`          | 通过缓冲写入字节数组      |
| `write_string_and_clear(writer, str)` | 写入字符串并 flush 释放 |

### 🚣 缓冲结构体 BufferReader/Writer

| 类型或方法                   | 描述           |
| ----------------------- | ------------ |
| `BufferReader`          | 缓冲阅读结构体      |
| `peek`, `skip`          | 缓冲结构操作方法     |
| `rewind`                | 重置阅读位置       |
| `is_empty`, `remaining` | 检查缓冲区状态      |
| `buffer()`              | 获取内部缓冲数据映射   |
| `BufferWriter`          | 缓冲写入结构体      |
| `flush()`, `clear()`    | 把缓冲数据写入并释放重置 |
| `remaining_space()`     | 查看剩余空间       |

---

## 🌱 `expand.mbt`：展开工具

| 函数                                           | 描述                       |
| -------------------------------------------- | ------------------------ |
| `string_to_utf8_bytes(str)`                  | 字符串转成 UTF-8 编码字节         |
| `split_bytes(buf: Bytes, a: Byte)`           | 按指定字节分割 `Bytes`          |
| `utf8_bytes_to_string(b: Bytes)`             | UTF-8 字节转成字符串            |
| `split_array_bytes(a: Array[Byte], b: Byte)` | 按分割符分割字节数组 `Array[Byte]` |

---

## ⚠️ 错误处理

缓冲读写操作使用统一的错误类型：

```moonbit
suberror BufferError {
  Overflow(String)
  Underflow(String)
  Flush(String)
  InvalidCapacity(String)
}
```

支持 `?` / `!` / `match` 进行应急或软处理。

---

## 🧪 温柔测试

运行全部测试用例：

```bash
moon test -p ZSeanYves/bufferutils
```

或手动调用:

```bash
moon run ZSeanYves/bufferutils_test
```

测试包括：

* 一般/边界读写操作
* 空缓冲区操作
* 限制容量的写入操作
* unicode/二进制字符
* 工具函数精度

---

## 🗂 项目结构

```
BufferUtils/
├── src/
│   ├── bufferutils.mbt          # 高级套声函数
│   ├── bufferutils.mbti         # 接口和类型定义
│   ├── reader.mbt               # 阅读功能添加
│   ├── writer.mbt               # 写入功能添加
│   ├── error.mbt                # 错误类型定义
│   ├── expand.mbt               # 拓展工具：utf8/分割/打印
│   └── bufferutils_test.mbt     # 测试文件
├── examples/                    # 示例输入/输出
├── moon.mod.json                # MoonBit 模块描述文件
└── LICENSE
```

---

## 📜 协议

Apache-2.0 License
请参阅 [LICENSE](./LICENSE) 获取详情。
