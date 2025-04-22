# 📦 BufferUtils: A High-Performance Buffer Library for MoonBit

[English](https://github.com/ZSeanYves/BufferUtils/blob/main/README.md) | [简体中文](https://github.com/ZSeanYves/BufferUtils/blob/main/README_zh_CN.md)

[![Build Status](https://img.shields.io/github/actions/workflow/status/ZSeanYves/BufferUtils/bufferutils-ci.yml)](https://github.com/ZSeanYves/BufferUtils/actions)
[![License](https://img.shields.io/github/license/ZSeanYves/BufferUtils)](LICENSE)

**BufferUtils** is a high-performance buffer utility library for MoonBit, inspired by Rust's `BufReader` and `BufWriter`. It supports efficient, flexible, and composable buffered reading and writing with full error handling and type interop.

---

## 🚀 Features
- **Buffer Reading & Writing**: Stream-style I/O with peek, skip, rewind, flush, and clear.
- **Multi-Type Interop**: Support for Binary data ,Text data,`Bytes`, `Array[Byte]`, `Array[Int]`, and `String`.
- **Dynamic Capacity Management**: Customize buffer capacity.
- **Zero-Copy**: Minimized unnecessary copying.
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

### read ,Write and flush 
```moonbit
@ZSeanYves/bufferutils.writeStringClear("hello moonbit") 
// Optional parameter cap allows setting buffer size (default: 128)
/// Currently, Moonbit does not support converting the `Bytes` type back to `String`,  
/// so the return type remains as `Array[Byte]`.  
/// Other `write` functions can return values in their original input types.
@ZSeanYves/bufferutils.writeBytesClear(Bytes::from_array([72, 101, 108, 108, 111]))
@ZSeanYves/bufferutils.writeIntsClear([10,20,30])
```

### read ,Write
```moonbit
@ZSeanYves/bufferutils.writeString("hello moonbit") 
@ZSeanYves/bufferutils.writeBytes(Bytes::from_array([72, 101, 108, 108, 111]))
@ZSeanYves/bufferutils.writeInts([10,20,30])
///You need to manually call clear() to reset the buffer.

### Read from byte array
```moonbit
@ZSeanYves/bufferutils.readBytes(Bytes::from_array([72, 101, 108, 108, 111]))
@ZSeanYves/bufferutils.readInts([72,105]) 
@ZSeanYves/bufferutils.readString("hello")
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

### Write Functions
| Function                  | Description                            |
|--------------------------|----------------------------------------|
| `writeBytes(Bytes)`      | Write then flush                       |
| `writeBytesClear(Bytes)` | Write, flush, then clear               |
| `writeInts([Int])`       | Write Int array                        |
| `writeIntsClear([Int])`  | Write then clear buffer                |
| `writeString(String)`    | Write string                           |
| `writeStringClear(String)` | Write string and clear               |

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
│   └── bufferutils_test.mbt     # Tests (black + white box)
|── moon.mod.json 
├── LICENSE
└── README.md
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


