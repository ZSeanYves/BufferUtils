# 📦 BufferUtils: A High-Performance Buffered I/O Utility for MoonBit

[English](https://github.com/ZSeanYves/BufferUtils/blob/main/README.md) | [简体中文](https://github.com/ZSeanYves/BufferUtils/blob/main/README_zh_CN.md)

[![Build Status](https://img.shields.io/github/actions/workflow/status/ZSeanYves/BufferUtils/bufferutils-ci.yml)](https://github.com/ZSeanYves/BufferUtils/actions)
[![License](https://img.shields.io/github/license/ZSeanYves/BufferUtils)](LICENSE)

**BufferUtils** is a fast, lightweight buffer utility library for MoonBit, designed to simplify buffered reading, writing, and transformation of byte streams. Inspired by Rust’s `BufReader`/`BufWriter` and MoonBit's strong type system, it supports safe I/O, composable interfaces, multi-type input/output, and utility expansion for common tasks.

---

## 🚀 Features

* **Buffered Read/Write** with peek, skip, rewind, flush, clear
* **Multi-Type Interop**: Works with `Bytes`, `Array[Byte]`, `Array[Int]`, `String`
* **UTF-8 Encoding/Decoding**
* **Customizable Buffer Capacity**
* **File Output Support**
* **Unified Error System**
* **Zero-Copy Design**
* **Safe Wrapper Variants**
* **Utility Tools in `expand.mbt`** for Split, utf8 conversion, error handling

---

## 📦 Installation

```bash
moon add ZSeanYves/bufferutils
```

or edit `moon.mod.json`:

```json
"import": ["ZSeanYves/bufferutils"]
```

---

## 🔧 Quick Start

### ✍️ Writing Data to File

```moonbit
@ZSeanYves/bufferutils.writeString("output.txt", "hello moonbit")
@ZSeanYves/bufferutils.writeBytes("data.bin", Bytes::from_array([72, 105]))
@ZSeanYves/bufferutils.writeInt("data.int", [1, 2, 3])
```

### 🧠 Buffered Processing

```moonbit
let arr = [104, 101, 108, 108, 111]  # "hello"
let writer = new_writer(128)
let _ = write_bytes(writer, arr)
let flushed = writer.flush()
let reader = new_reader(Bytes::from_array(flushed))
let data = read_bytes(reader)  # returns Array[Byte]
```

### 🔍 Reading with Type Conversion

```moonbit
readBytes(Bytes::from_array([72, 105]))     # → [72, 105]
readABytes([97, 98, 99])                    # → [97, 98, 99]
readInts([104, 101, 108])                   # → [104, 101, 108]
readString("moon")                          # → [109, 111, 111, 110]
```

---

## 🧰 API Overview

### 🔵 Reading Functions

| Function             | Description                       |
| -------------------- | --------------------------------- |
| `readBytes(Bytes)`   | Read from MoonBit `Bytes`         |
| `readABytes([Byte])` | Read from `Array[Byte]`           |
| `readInts([Int])`    | Read and convert `Int` to `Byte`  |
| `readString(String)` | Convert UTF-8 string to bytes     |
| `read_from(reader)`  | Generalized interface using trait |

### 🕠 Writing Functions

| Function                              | Description                        |
| ------------------------------------- | ---------------------------------- |
| `writeBytes(path, Bytes)`             | Write raw bytes to file            |
| `writeInt(path, [Int])`               | Write array of integers            |
| `writeString(path, str)`              | Write UTF-8 encoded string         |
| `write_bytes(writer, AByte)`          | Write byte array via buffer writer |
| `write_string_and_clear(writer, str)` | Write string then flush and clear  |

### 🚣 Buffer Utilities (Reader/Writer)

| Type / Method            | Description                     |
| ------------------------ | ------------------------------- |
| `BufferReader`           | Buffered reader struct          |
| `peek`, `skip`, `rewind` | Inspect or navigate buffer      |
| `is_empty`, `remaining`  | Check buffer state              |
| `buffer()`               | Access internal buffer snapshot |
| `BufferWriter`           | Buffered writer struct          |
| `flush()`, `clear()`     | Finalize and reset buffer       |
| `remaining_space()`      | Get available capacity          |

---

## 🌱 `expand.mbt`: Utility Tools

| Function                                     | Description                                         |
| ---------------------------------------------| --------------------------------------------------- |
| `string_to_utf8_bytes(str)`                  | Convert string to UTF-8 encoded bytes               |
| `split_bytes(buf: Bytes, a: Byte)`           | byte is divided  by a specific byte delimiter.      |
| `utf8_bytes_to_string(b: Bytes)`             | Convert the UTF-8 encoded bytes to string           |
| `split_array_bytes(a: Array[Byte], b: Byte)` | Divide the array [byte]` by delimiter.              |

---

## ⚠️ Error Handling

All operations use a unified error enum:

```moonbit
suberror BufferError {
  Overflow(String)
  Underflow(String)
  Flush(String)
  InvalidCapacity(String)
}
```

Use `?`, `!`, or `match` to propagate or handle errors gracefully.

---

## 🧪 Testing

Run full test suite:

```bash
moon test -p ZSeanYves/bufferutils
```

Or run manually:

```bash
moon run ZSeanYves/bufferutils_test
```

Tests cover:

* Normal/boundary read-write
* Empty buffer behavior
* Capacity-limited writing
* Unicode and binary strings
* Utility function correctness

---

## 🗂 Project Structure

```
BufferUtils/
├── src/
│   ├── bufferutils.mbt          # Main wrapper functions
│   ├── bufferutils.mbti         # Interface/type declarations
│   ├── reader.mbt               # BufferReader methods
│   ├── writer.mbt               # BufferWriter methods
│   ├── error.mbt                # Unified error definitions
│   ├── expand.mbt               # Extra utilities: print, safe wrappers, utf8
│   └── bufferutils_test.mbt     # All tests (black-box & white-box)
├── examples/                    # Sample input/output
├── moon.mod.json                # MoonBit module manifest
└── LICENSE
```

---

## 📜 License

Apache-2.0 License
See [LICENSE](./LICENSE) for full terms.
