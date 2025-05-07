# 🎞 BufferUtils：MoonBit 的高性能缓冲库

[English](https://github.com/ZSeanYves/BufferUtils/blob/main/README.md) | [简体中文](https://github.com/ZSeanYves/BufferUtils/blob/main/README_zh_CN.md)

[![构建状态](https://img.shields.io/github/actions/workflow/status/ZSeanYves/BufferUtils/bufferutils-ci.yml)](https://github.com/ZSeanYves/BufferUtils/actions)  
[![许可证](https://img.shields.io/github/license/ZSeanYves/BufferUtils)](LICENSE)

**BufferUtils** 是一个为 [MoonBit](https://moonbitlang.com/) 构建的高性能缓冲工具库，灵感来自 Rust 的 `BufReader` 和 `BufWriter`，支持高效、灵活、可组合的缓冲读取和写入，并具备完整的错误处理和多类型兼容性。

---

## 🚀 功能特色

- **缓冲读写**：支持流式读取/写入，peek，skip，rewind，flush 和 clear 等操作
- **多类型兼容**：支持二进制数据、文本数据，兼容 `Bytes`，`Array[Byte]`，`Array[Int]`，`String`
- **动态容量管理**：可自定义缓冲区容量
- **零拷贝优化**：尽可能减少不必要的数据复制
- **统一错误管理**：使用枚举类 `BufferError` 实现清晰的错误处理机制

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

## 🔧 基本用法示例

### 写入、刷新

```moonbit
@ZSeanYves/bufferutils.writeStringClear("hello moonbit")
// 可选参 cap 用于设置缓冲容量，默认为 128

/// 当前 MoonBit 未支持将 `Bytes` 类型转换为 `String`，
/// 因此返回类型为 `Array[Byte]`。
/// 其他 write 函数可返回其输入时的类型值
@ZSeanYves/bufferutils.writeBytesClear(Bytes::from_array([72, 101, 108, 108, 111]))
@ZSeanYves/bufferutils.writeIntsClear([10, 20, 30])
```

### 写入不清空

```moonbit
@ZSeanYves/bufferutils.writeString("hello moonbit")
@ZSeanYves/bufferutils.writeBytes(Bytes::from_array([72, 101, 108, 108, 111]))
@ZSeanYves/bufferutils.writeInts([10, 20, 30])
// 你需要手动调用 clear() 来清空缓冲区
当使用 `writeBytes` 写入大数据时（如 1MB 或以上），**强烈建议你手动指定 cap\~ 缓冲区容量参数**，否则会触发 `BufferOverflowError` 或出现数据截断：

```moonbit
let size = 1024 * 1024  # 1MB
let data: Array[Byte] = []
for i in 0..<size {
  data.push((i % 256).to_byte())
}
let bytes = Bytes::from_array(data)

# ✅ 推荐用法：自行设置合理的 cap~ 容量
let result = @ZSeanYves/bufferutils.writeBytes(bytes, cap~ = size + 128)
```

你也可以通过读取已有数据长度自动设置缓冲区大小，例如：

```moonbit
let read_data = @ZSeanYves/bufferutils.readBytes(file_input)
let result = @ZSeanYves/bufferutils.writeBytes(read_data, cap~ = read_data.length() + 128)
```

默认容量仅为 `128`，无法完整存储大块数据。
```

### 读取字节数据

```moonbit
@ZSeanYves/bufferutils.readBytes(Bytes::from_array([72, 101, 108, 108, 111]))
@ZSeanYves/bufferutils.readInts([72, 105])
@ZSeanYves/bufferutils.readString("hello")
```

---

## 📘 API 总览

### 读取函数

| 函数名称                  | 描述                         |
|--------------------------|------------------------------|
| `readBytes(Bytes)`       | 从 Bytes 中读取              |
| `readBytesArray([Byte])` | 从 Array[Byte] 中读取        |
| `readInts([Int])`        | 从 Int 数组中读取        |
| `readString(String)`     | 从 UTF-8 字符串中读取    |

### 写入函数

| 函数名称                     | 描述                           |
|-----------------------------|--------------------------------|
| `writeBytes(Bytes)`         | 写入后 flush                    |
| `writeBytesClear(Bytes)`    | 写入，flush 后再清空     |
| `writeInts([Int])`          | 写入 Int 数组               |
| `writeIntsClear([Int])`     | 写入后清空缓冲          |
| `writeString(String)`       | 写入字符串                |
| `writeStringClear(String)`  | 写入字符串并清空     |

---

## ⚠️ 错误处理机制

```moonbit
enum BufferError {
  Overflow(String)
  Underflow(String)
  Flush(String)
  InvalidCapacity(String)
}
```

可使用 `!`，`?`，或 `match` 进行优雅的错误处理。

---

## 📂 项目结构

```
BufferUtils/
├── src/lib/
│   ├── bufferutils.mbt          # 高级封装接口
│   ├── bufferutils.mbti         # 类型定义与导出接口
│   ├── reader.mbt               # 缓冲读取器模块
│   ├── writer.mbt               # 缓冲写入器模块
│   ├── error.mbt                # 错误类型定义
│   └── bufferutils_test.mbt     # 测试模块（黑盒 + 白盒）
├── moon.mod.json 
├── LICENSE
└── README.md
```

---

## 🧪 测试方法

运行全量测试套件：

```bash
moon test -p ZSeanYves/bufferutils
```

模拟用户外部调用场景测试：

```bash
moon run ZSeanYves/bufferutils_test
```

---

## 📜 许可证

本项目采用 Apache-2.0 开源许可协议，详见 [LICENSE](./LICENSE)。