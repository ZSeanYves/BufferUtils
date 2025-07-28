///| Core wrapper functions
/// These functions encapsulate buffered reading and writing logic.
/// They simplify usage by abstracting away direct buffer manipulation.
/// All write operations support an optional `cap` parameter to specify buffer capacity (default: 128).
/// Errors are automatically caught and handled.
/// ======================
/// Unified Reading Interface Functions
/// 
/// This section provides a unified reading interface based on the `BufReadable` trait,
/// enabling flexible reading operations from different input types.
/// 
/// - `read_from` is a generic function that operates on any object implementing `BufReadable`.
/// - Specialized helper functions are provided for common input types, including `Bytes`, `Array[Byte]`, `Array[Int]`, and `String`.
/// 
/// Each specialized function internally standardizes the input and delegates the reading to `read_from`.
/// Error handling is consistent across all functions.
/// ======================
/// unified function based on trait：BufReadable
fn read_from(reader : BufferReader) -> Array[Byte] raise BufferError {
  let result = []
  while not(reader.is_empty()) {
    let b = reader.read_byte()
    result.push(b)
  }
  result
}

///| Read all content from the given Bytes buffer and return as Array[Byte].
/// Raises BufferError::Underflow if input is empty.
pub fn read_bytes(
  reader : BufferReader,
) -> Array[Byte] raise BufferError {
  if reader.buf.length() == 0 {
    raise BufferError::Underflow("读取失败：到达缓冲区末尾")
  }
  read_from(reader)
}

///| Convert an Array[Byte] to Bytes and read using read_bytes
pub fn read_abytes(
  data : Array[Byte],
) -> BufferReader {
  let bytes = Bytes::from_array(data)
  let reader = new_reader(bytes)
  reader
}

///| Convert an Array[Int] to Byte array and read using read_bytes
pub fn read_ints(
  data : Array[Int],
) -> BufferReader {
  let bytes = Bytes::from_array(data.map(fn(i) { i.to_byte() }))
  let reader = new_reader(bytes)
  reader
}

///| Convert a String to Bytes and read using read_bytes
pub fn read_string(
  data : String,
) -> BufferReader {
  let bytes = string_to_utf8_bytes(data)
  let reader = new_reader(bytes)
  reader
}

///| ======================
/// Unified Writing Interface Functions
/// 
/// This section provides a unified writing interface based on the `BufWritable` trait,
/// enabling flexible writing operations to different buffer types.
/// 
/// - `write_to` is a generic function that operates on any object implementing `BufWritable`.
/// - Specialized helper functions can be provided for common scenarios if needed.
/// 
/// Each writing function ensures data integrity and consistent error handling.
/// ======================
/// Unified function(1) based on trait `BufWritable`
fn write_to(
  writer : BufferWriter,
  data : Array[Byte]
) -> Array[Byte] raise BufferError {
  writer.write_all(data)
  writer.flush()
}



///| Write bytes to buffer and flush (does not clear buffer)
pub fn write_Abyte(
  writer : BufferWriter,
  data : Array[Byte],
) -> Array[Byte] raise BufferError {
  write_to(writer, data)
}


///| Full pipeline: read from Bytes and write back to buffer
pub fn write_bytes(writer:BufferWriter,bytes : Array[Byte]) -> Array[Byte] raise BufferError {
  write_Abyte(writer,bytes)
}



///| Read from Int array and write with flush
pub fn write_int(writer:BufferWriter,bytes : Array[Byte]) -> Array[Byte] raise BufferError {
  write_Abyte(writer,bytes)
}

/// Read from String and write with flush
pub fn write_string(writer:BufferWriter,bytes : Array[Byte]) -> Array[Byte] raise BufferError {
  write_Abyte(writer,bytes)
}

///| Clear the buffer and reset the write position to 0.
pub fn clear(self : BufferWriter) -> Unit {
  self.buf = []
  self.pos = 0
}

///| ======================
/// Unified Safe Wrappers for Buffer Reading and Writing
/// 
/// This section provides safe wrapper functions for reading from and writing to buffers.
/// 
/// Each function encapsulates a potentially fallible operation (which may raise `BufferError`)
/// and converts it into a safe result by returning an empty array upon failure.
/// 
/// Features:
/// - Unified API for reading from `Bytes`, `Array[Byte]`, `Array[Int]`, and `String`.
/// - Unified API for writing to buffers with optional clear operation.
/// - Consistent error handling: all errors are safely captured and converted.
/// - Default buffer capacity is set to 128 for writing operations, customizable by parameter.
/// 
/// These wrappers simplify external calls and ensure a stable behavior across different input/output types.
/// ======================
pub fn readBytes(data : Bytes) -> Array[Byte] {
  let reader = new_reader(data)
  match (try? read_bytes(reader)) {
    Ok(res) => res
    Err(_) => []
  }
}
/// Read all bytes from given Bytes input safely///| Read all bytes from a given Array[Byte] safely
pub fn readABytes(arr : Array[Byte]) -> Array[Byte] {
  let reader = read_abytes(arr)
  match (try? read_bytes(reader)) {
    Ok(res) => res
    Err(_) => []
  }
}

///| Convert and read all bytes from an Array[Int] safely
pub fn readInts(data : Array[Int]) -> Array[Byte] {
  let reader = read_ints(data)
  match (try? read_bytes(reader)) {
    Ok(res) => res
    Err(_) => []
  }
}

///| Convert and read all bytes from a String input safely
pub fn readString(s : String) -> Array[Byte] {
  let reader = read_string(s)
  match (try? read_bytes(reader)) {
    Ok(res) => res
    Err(_) => []
  }
}

///| Write Bytes to file (with flush)
pub fn writeBytes(path : String, data : Bytes) -> Unit raise @fs.IOError {
  @fs.write_bytes_to_file(path, data)
}



///| Write Int array to file (converted to Bytes)
pub fn writeInt(
  path : String,
  data : Array[Int],
  encoding~ : String = "utf8",
) -> Unit raise @fs.IOError {
  let mut res = ""
  for i in 0..<data.length() {
    res += data[i].to_string()
  }
  @fs.write_string_to_file(path, res, encoding~)
}


///| Write String to file (flush, UTF-8 by default)
pub fn writeString(
  path : String,
  data : String,
  encoding~ : String = "utf8",
) -> Unit raise @fs.IOError {
  @fs.write_string_to_file(path, data, encoding~)
}


///| Test cases for buffer utility functions
/// These tests cover various scenarios including reading and writing bytes,
test "read and write basic" {
  let original : Array[Byte] = [1, 2, 3, 4, 5]
  let data = readABytes(original)
  let writer = new_writer(128)
  let copied = write_bytes(writer,data)
  writer.clear() // Clear after writing
  assert_eq(copied.length(), 5)
  assert_eq(copied[0], 1)
  assert_eq(copied[4], 5)
}

///|
test "convert int array to byte array" {
  let ints = [10, 20, 30]
  let bytes = readInts(ints)
  assert_eq(bytes.length(), 3)
  assert_eq(bytes[0], 10)
  assert_eq(bytes[2], 30)
}

///|
test "convert string to byte array" {
  let str = "hello"
  let bytes = readString(str)
  let a = str[0].to_byte()
  let b = str[4].to_byte()
  assert_eq(bytes.length(), 5)
  assert_eq(bytes[0], a)
  assert_eq(bytes[4], b)
}

///|
test "read empty buffer" {
  let empty = Bytes::from_array([])
  let reader = new_reader(empty)
  let result = try? read_bytes(reader)
  assert_eq(result.is_err(), true)
}

///|
test "write with invalid capacity" {
  let bytes : Array[Byte] = [1, 2, 3]
  let writer = new_writer(2) // Invalid capacity
  let res = try? write_Abyte(writer,bytes)
  assert_eq(res.is_err(), true)
}

///|
test "write and flush buffer" {
  let int = [1, 2, 3, 4]
  let data = readInts(int)
  let writer = new_writer(128)
  let flushed = write_int(writer,data)
  assert_eq(flushed, data)
}

///|
test "write and recover utf8 string" {
  let s = "MoonBit测试123"
  let data = readString(s)
  let writer = new_writer(128)
  let result = write_string(writer,data)
  assert_eq(result, data)
}

///| Trait-Based Interface Tests
/// These tests focus on verifying generic functions that rely on BufReadable and BufWritable traits.
test "generic read_from trait function" {
  let data = Bytes::from_array([10, 20, 30, 40])
  let reader = new_reader(data)
  let result = read_from(reader)
  assert_eq(result.length(), 4)
  assert_eq(result, [10, 20, 30, 40])
}

///|
test "generic write_to trait function" {
  let writer = new_writer(16)
  let input : Array[Byte] = [100, 101, 102]
  let result = write_to(writer, input)
  assert_eq(result.length(), 3)
  assert_eq(result, [100, 101, 102])
}


