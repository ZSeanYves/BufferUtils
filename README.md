# 📦 BufferUtils: A High-Performance Buffer Library for MoonBit

[English](https://github.com/ZSeanYves/BufferUtils/blob/main/README.md) | [简体中文](https://github.com/ZSeanYves/BufferUtils/blob/main/README_zh_CN.md)

[![Build Status](https://img.shields.io/github/actions/workflow/status/ZSeanYves/BufferUtils/bufferutils-ci.yml)](https://github.com/ZSeanYves/BufferUtils/actions)
[![License](https://img.shields.io/github/license/ZSeanYves/BufferUtils)](LICENSE)

**BufferUtils** is a high-performance buffer utility library for MoonBit, inspired by Rust's `BufReader` and `BufWriter`. It supports efficient, flexible, and composable buffered reading and writing with full error handling, file I/O support, UTF-8 encoding, and type interop.

---

## 🚀 Features

* **Buffer Reading & Writing**: Stream-style I/O with `peek`, `skip`, `rewind`, `flush`, `clear`.
* **Multi-Type Interop**: Supports `Bytes`, `Array[Byte]`, `Array[Int]`, and `String`.
* **UTF-8 Encoding**: Converts `String` to UTF-8 `Bytes` via `string_to_utf8_bytes`.
* **File I/O Integration**: Write buffers directly to files using `writeBytes`, `writeString`, `writeInt`.
* **Custom Capacity**: Define buffer capacity; check remaining space dynamically.
* **Zero-Copy**: Avoid unnecessary copying.
* **Unified Error System**: All read/write operations raise `BufferError` enums.

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

### ✍️ Write Data to File

```moonbit
@ZSeanYves/bufferutils.writeString("output.txt", "hello moonbit")
@ZSeanYves/bufferutils.writeBytes("out.bin", Bytes::from_array([72, 101, 108, 108, 111]))
@ZSeanYves/bufferutils.writeInt("out_int.dat", [10, 20, 30])
```

### 🧠 Handling Large Data Writes

```moonbit
let size = 1024 * 1024 * 100 #100MB
let arr : Array[Byte] = []
for i in 0..<size {
  arr.push((i % 256).to_byte())
}
let path4 = "./src/examples/LargeBytes4.txt"
let data = Bytes::from_array(arr)
writeBytes(path4, data)
# create BufferWriter
let writer = new_writer(size + 1024)
let written = write_bytes(writer, arr)
# close the BufferWriter
writer.clear()
let read = readBytes(Bytes::from_array(written))
assert_eq(read.length(), size)
```

> new_writer(size). You choose a suitable size for your need

### 🔍 Read from Input Buffer

```moonbit
@ZSeanYves/bufferutils.readBytes(Bytes::from_array([72, 101, 108, 108, 111]))
@ZSeanYves/bufferutils.readInts([72, 105])
@ZSeanYves/bufferutils.readString("hello")
```

---

## 📘 API Overview

### Read Functions

| Function                    | Description                   |
| --------------------------- | ----------------------------- |
| `readBytes(Bytes)`          | Read byte buffer              |
| `readABytes([Byte])`        | Read from Array\[Byte]        |
| `readInts([Int])`           | Read from Int array           |
| `readString(String)`        | Read from UTF-8 string        |
| `string_to_utf8_bytes(str)` | Convert String to UTF-8 Bytes |

### Write Functions

| Function                    | Description                    |
| --------------------------- | ------------------------------ |
| `writeBytes(path, Bytes)`   | Write and flush to file        |
| `writeInt(path, [Int])`     | Encode then write              |
| `writeString(path, str)`    | Write UTF-8 string             |
| `writeAbytes(path, AByte)`  | Write bytes into writer        |
| `writer.clear()`            | close the BufferReader         |

---

## ⚠️ Error Handling

```moonbit
suberror BufferError {
  Overflow(String)
  Underflow(String)
  Flush(String)
  InvalidCapacity(String)
}
```

Use `!`, `?`, or `match` for graceful propagation.

---

## 📂 Project Structure

```
BufferUtils/
├── src/lib/
│   ├── bufferutils.mbt          # High-level wrapper functions
│   ├── bufferutils.mbti         # Interface and type declarations
│   ├── reader.mbt               # BufferReader methods
│   ├── writer.mbt               # BufferWriter methods
│   ├── error.mbt                # Unified error types
│   ├── expand.mbt               # Expand functions
│   └── bufferutils_test.mbt     # Black-box & white-box tests
├── moon.mod.json                # Module definition
├── LICENSE
└── README.md
```

---

## 🧪 Testing

Run all tests:

```bash
moon test -p ZSeanYves/bufferutils
```

Or invoke simulation:

```bash
moon run ZSeanYves/bufferutils_test
```

---

## 📜 License

Apache-2.0 License. See [LICENSE](./LICENSE) for full details.

---
