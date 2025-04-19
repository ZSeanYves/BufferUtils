# 📦 BufferUtils: A High-Performance Buffer Library for MoonBit

[English](https://github.com/ZSeanYves/BufferUtils/blob/main/README.md) | [简体中文](https://github.com/ZSeanYves/BufferUtils/blob/main/README_zh_CN.md)

[![Build Status](https://img.shields.io/github/actions/workflow/status/ZSeanYves/BufferUtils/bufferutils-ci.yml)](https://github.com/ZSeanYves/BufferUtils/actions)
[![License](https://img.shields.io/github/license/ZSeanYves/BufferUtils)](LICENSE)

**BufferUtils** is a high-performance buffer utility library for MoonBit, inspired by Rust's `BufReader` and `BufWriter`. It supports efficient, flexible, and composable buffered reading and writing with full error handling and type interop.

---

## 🚀 Features
- **Buffer Reading & Writing**: Stream-style I/O with peek, skip, rewind, flush, and clear.
- **Multi-Type Interop**: Support for `Bytes`, `Array[Byte]`, `Array[Int]`, and `String`.
- **Dynamic Capacity Management**: Customize buffer capacity.
- **Zero-Copy**: Minimized unnecessary copying.
- **Safe Variants**: All functions have `_safe` versions to handle errors gracefully.
- **Unified Errors**: Clean enum-based error handling (`BufferError`).

---

## 📦 Installation
```bash
moon add ZSeanYves/bufferutils
```
Or manually in `moon.mod.json`:
```json
"import": ["ZSeanYves/bufferutils"]
```

---

## 🔧 Basic Usage

### Write and flush a string
```moonbit
@ZSeanYves/bufferutils.writeStringClear("hello moonbit")
```

### Read from byte array
```moonbit
let data = [72, 105]
@ZSeanYves/bufferutils.readInts(data) // [72, 105]
```

### Safe variant
```moonbit
let res = @ZSeanYves/bufferutils.writeStringClearSafe("moonbit")
inspect!(res.length())
```

---

## 📘 API Overview

### Read Functions
| Function                  | Description                            |
|--------------------------|----------------------------------------|
| `readBytes(Bytes)`       | Read byte buffer                       |
| `readBytesArray([Byte])` | Read from Array[Byte]                  |
| `readInts([Int])`        | Read from Int array                    |
| `readString(String)`     | Read from UTF-8 string                 |
| `_safe` versions          | Return default on error                |

### Write Functions
| Function                  | Description                            |
|--------------------------|----------------------------------------|
| `writeBytes(Bytes)`      | Write then flush                       |
| `writeBytesClear(Bytes)` | Write, flush, then clear               |
| `writeInts([Int])`       | Write Int array                        |
| `writeIntsClear([Int])`  | Write then clear buffer                |
| `writeString(String)`    | Write string                           |
| `writeStringClear(String)` | Write string and clear               |
| `_safe` versions          | Handle errors internally               |

---

## ⚠️ Errors

```moonbit
enum BufferError {
  Overflow(String)
  Underflow(String)
  Flush(String)
  InvalidCapacity(String)
}
```
Use `!`, `?`, or `match` for graceful error handling.

---

## 📂 Project Structure
```
BufferUtils/
├── src/lib/
│   ├── bufferutils.mbt          # High-level interface
│   ├── bufferutils.mbti         # Public type + API
│   ├── reader.mbt               # BufferReader
│   ├── writer.mbt               # BufferWriter
│   ├── error.mbt                # Error types
│   ├── traits.mbt               # Trait interface
│   └── bufferutils_test.mbt     # Tests (black + white box)
└── LICENSE / moon.mod.json / README.md
```

---

## 🧪 Testing
Run full test suite:
```bash
moon test -p ZSeanYves/bufferutils
```
Run external simulation:
```bash
moon run ZSeanYves/bufferutils_test
```

---

## 📜 License
Apache-2.0 License. See [LICENSE](./LICENSE) for full details.

---


