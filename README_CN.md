# 📦 BufferUtils：一个为 MoonBit 构建的高性能缓冲库

[English](https://github.com/ZSeanYves/BufferUtils/blob/main/README.md) | [简体中文](https://github.com/ZSeanYves/BufferUtils/blob/main/README_zh_CN.md)

[![构建状态](https://img.shields.io/github/actions/workflow/status/ZSeanYves/BufferUtils/bufferutils-ci.yml)](https://github.com/ZSeanYves/BufferUtils/actions)
[![许可证](https://img.shields.io/github/license/ZSeanYves/BufferUtils)](LICENSE)

**BufferUtils** 是为 MoonBit 设计的高性能缓冲区工具库，灵感来自 Rust 的 `BufReader` 和 `BufWriter`。它支持高效、灵活、可组合的缓冲读取与写入，并具备完整的错误处理与多类型交互能力。

---

## 🚀 功能亮点
- **缓冲读写**：流式 I/O，支持预览、跳过、重置、刷新和清空
- **多类型交互**：支持 `Bytes`、`Array[Byte]`、`Array[Int]` 和 `String`
- **动态容量管理**：自定义缓冲区容量
- **零拷贝设计**：最大限度减少复制操作
- **安全封装版本**：所有函数都有 `_safe` 版本以防止抛出异常
- **统一错误处理**：通过 `BufferError` 枚举实现清晰的错误报告

---

## 📦 安装方式
```bash
moon add ZSeanYves/bufferutils
```
或手动在 `moon.mod.json` 中添加：
```json
"import": ["ZSeanYves/bufferutils"]
```

---

## 🔧 快速使用

### 写入字符串并刷新、清空
```moonbit
@ZSeanYves/bufferutils.writeStringClear("hello moonbit")
```

### 从字节数组读取
```moonbit
let data = [72, 105]
@ZSeanYves/bufferutils.readInts(data) // [72, 105]
```

### 安全版本调用
```moonbit
let res = @ZSeanYves/bufferutils.writeStringClearSafe("moonbit")
inspect!(res.length())
```

---

## 📘 API 一览

### 读取接口
| 函数                         | 功能说明                         |
|------------------------------|----------------------------------|
| `readBytes(Bytes)`           | 从 `Bytes` 读取所有字节          |
| `readBytesArray([Byte])`     | 从字节数组读取                   |
| `readInts([Int])`            | 从整型数组读取                   |
| `readString(String)`         | 从字符串读取                     |
| 所有 `_safe` 版本             | 错误时返回空数组，无异常抛出     |

### 写入接口
| 函数                            | 功能说明                          |
|---------------------------------|-----------------------------------|
| `writeBytes(Bytes)`             | 写入并刷新                        |
| `writeBytesClear(Bytes)`        | 写入、刷新并清空缓冲区            |
| `writeInts([Int])`              | 写入整型数组                      |
| `writeIntsClear([Int])`         | 写入整型数组并清空缓冲区          |
| `writeString(String)`           | 写入字符串                        |
| `writeStringClear(String)`      | 写入字符串并清空缓冲区            |
| 所有 `_safe` 版本               | 错误时返回空数组，无异常抛出      |

---

## ⚠️ 错误类型

所有错误统一封装在 `BufferError` 枚举中：
```moonbit
enum BufferError {
  Overflow(String)
  Underflow(String)
  Flush(String)
  InvalidCapacity(String)
}
```
支持使用 `!`、`?` 或 `match` 进行错误传播或处理。

---

## 📂 项目结构
```
BufferUtils/
├── src/lib/
│   ├── bufferutils.mbt          # 高级功能封装
│   ├── bufferutils.mbti         # 公共接口定义
│   ├── reader.mbt               # 读取器模块
│   ├── writer.mbt               # 写入器模块
│   ├── error.mbt                # 错误定义模块
│   ├── traits.mbt               # Trait 接口定义
│   └── bufferutils_test.mbt     # 测试模块（黑盒 + 白盒）
├── moon.mod.json
├── LICENSE
└── README.md
```

---

## 🧪 测试方式
运行完整测试用例：
```bash
moon test -p ZSeanYves/bufferutils
```
运行模拟外部调用：
```bash
moon run ZSeanYves/bufferutils_test
```

---

## 📜 开源协议
Apache-2.0 许可协议。详见 [LICENSE](./LICENSE)。

---
