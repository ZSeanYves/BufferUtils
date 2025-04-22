/// Core wrapper functions
/// These functions encapsulate buffered reading and writing logic.
/// They simplify usage by abstracting away direct buffer manipulation.
/// All write operations support an optional `cap` parameter to specify buffer capacity (default: 128).
/// Errors are automatically caught and handled.


/// Read all content from the given Bytes buffer and return as Array[Byte].
/// Raises BufferError::Underflow if input is empty.
pub fn read_bytes(data: Bytes) -> Array[Byte]!BufferError {
  if data.length() == 0 {
    raise BufferError::Underflow("读取失败：到达缓冲区末尾")
  }

  let reader = new_reader(data)
  let result = []

  while not(reader.is_empty()) {
    let b = reader.read_byte!()
    result.push(b)
  }
  result
}

/// Convert an Array[Byte] to Bytes and read using read_bytes
pub fn read_bytes_array(arr: Array[Byte]) -> Array[Byte]!BufferError {
  let bytes = Bytes::from_array(arr)
  read_bytes!(bytes)
}
/// Convert an Array[Int] to Byte array and read using read_bytes
pub fn read_ints(data: Array[Int]) -> Array[Byte]!BufferError {
  let bytes: Array[Byte] = data.map(fn(x) { x.to_byte() })
  read_bytes!(Bytes::from_array(bytes))
}

/// Convert a String to Bytes and read using read_bytes
pub fn read_string(s: String) -> Array[Byte]!BufferError {
  let  byte_array: Array[Byte] = []
  for i in 0..<s.length() {
    let b = s.charcode_at(i).to_byte()
    byte_array.push(b)
  }
  read_bytes!(Bytes::from_array(byte_array))
}


/// Write bytes to buffer and flush (does not clear buffer)
pub fn write_process(data: Array[Byte], cap: Int) -> Array[Byte]! BufferError {
    let writer = new_writer!(cap)
    writer.write_all!(data)
    writer.flush!()
}

/// Write bytes to buffer, flush and clear it
pub fn write_process_and_clear(data: Array[Byte], cap~: Int) -> Array[Byte]!BufferError {
  let writer = new_writer!(cap)
  writer.write_all!(data)
  let result = writer.flush!()
  writer.clear()
  result
}



 
/// Full pipeline: read from Bytes and write back to buffer
pub fn write_bytes(data: Bytes, cap~: Int = 128) -> Array[Byte]!BufferError {
  let bytes = read_bytes!(data)
  write_process!(bytes, cap)
}

/// Full pipeline + clear: read from Bytes and write+flush+clear
pub fn write_bytes_and_clear(data: Bytes, cap~: Int = 128) -> Array[Byte]!BufferError {
  let bytes = read_bytes!(data)
  write_process_and_clear!(bytes, cap~)
}

/// Read from Int array and write with flush
pub fn write_int(data: Array[Int], cap~: Int = 128) -> Array[Int]!BufferError {
  let bytes = read_ints!(data)
  write_process!(bytes, cap).map(fn(b) { b.to_int() })
}

/// Read from Int array and write+flush+clear
pub fn write_int_and_clear(data: Array[Int], cap~: Int = 128) -> Array[Int]!BufferError {
  let bytes = read_ints!(data)
  write_process_and_clear!(bytes,cap~).map(fn(b) { b.to_int() })
}

/// Read from String and write with flush
/// 目前无法实现将 Byte 重新转换成 String 类型输出，需等待后续开发
pub fn write_string(data: String, cap~: Int = 128) -> Array[Byte]!BufferError {
  let bytes = read_string!(data)
  write_process!(bytes, cap)
}

/// Read from String and write+flush+clear
pub fn write_string_and_clear(data: String, cap~: Int = 128) -> Array[Byte]!BufferError {
  let bytes = read_string!(data)
  write_process_and_clear!(bytes,cap~)
}



/// Final wrapped utility functions with safe error handling
/// These functions provide user-friendly interfaces that automatically handle errors
/// and return fallback values when operations fail.

/// Read all bytes from given Bytes input safely
pub fn readBytes(data: Bytes) -> Array[Byte] {
  match read_bytes?(data) {
    Ok(res) => res
    Err(_) => []
  }
}

/// Read all bytes from a given Array[Byte] safely
pub fn readBytesArray(arr: Array[Byte]) -> Array[Byte] {
  match read_bytes_array?(arr) {
    Ok(res) => res
    Err(_) => []
  }
}

/// Convert and read all bytes from an Array[Int] safely
pub fn readInts(data: Array[Int]) -> Array[Byte] {
  match read_ints?(data) {
    Ok(res) => res
    Err(_) => []
  }
}

/// Convert and read all bytes from a String input safely
pub fn readString(s: String) -> Array[Byte] {
  match read_string?(s) {
    Ok(res) => res
    Err(_) => []
  }
}

/// Write given Bytes to buffer and flush, return result or empty array
pub fn writeBytes(data: Bytes, cap~: Int = 128) -> Array[Byte] {
  match write_bytes?(data, cap~) {
    Ok(res) => res
    Err(_) => []
  }
}

/// Write given Bytes to buffer and flush+clear, return result or empty array
pub fn writeBytesClear(data: Bytes, cap~: Int = 128) -> Array[Byte] {
  match write_bytes_and_clear?(data, cap~) {
    Ok(res) => res
    Err(_) => []
  }
}

/// Write given Array[Int] to buffer and flush, return result or empty array
pub fn writeInt(data: Array[Int], cap~: Int = 128) -> Array[Int] {
  match write_int?(data, cap~) {
    Ok(res) => res
    Err(_) => []
  }
}

/// Write given Array[Int] to buffer and flush+clear, return result or empty array
pub fn writeIntClear(data: Array[Int], cap~: Int = 128) -> Array[Int] {
  match write_int_and_clear?(data, cap~) {
    Ok(res) => res
    Err(_) => []
  }
}

/// Write given String to buffer and flush, return result or empty array
pub fn writeString(data: String, cap~: Int = 128) -> Array[Byte] {
  match write_string?(data, cap~) {
    Ok(res) => res
    Err(_) => []
  }
}

/// Write given String to buffer and flush+clear, return result or empty array
pub fn writeStringClear(data: String, cap~: Int = 128) -> Array[Byte] {
  match write_string_and_clear?(data, cap~) {
    Ok(res) => res
    Err(_) => []
  }
}

/// Test cases for buffer utility functions
/// These tests cover various scenarios including reading and writing bytes,
test "read and write basic" {
  let original: Bytes = Bytes::from_array([1, 2, 3, 4, 5])
  let copied = write_bytes!(original)

  assert_eq!(copied.length(), 5)
  assert_eq!(copied[0], 1)
  assert_eq!(copied[4], 5)
}

test "convert int array to byte array" {
  let ints = [10, 20, 30]
  let bytes = read_ints!(ints)

  assert_eq!(bytes.length(), 3)
  assert_eq!(bytes[0], 10)
  assert_eq!(bytes[2], 30)
}

test "convert string to byte array" {
  let str = "hello"
  let bytes = read_string!(str)
  let a = str.charcode_at(0).to_byte()
  let b = str.charcode_at(4).to_byte()
  assert_eq!(bytes.length(), 5)
  assert_eq!(bytes[0], a)
  assert_eq!(bytes[4], b)
}


test "read empty buffer" {
  let empty = Bytes::from_array([])
  let result = read_bytes?(empty)
  assert_eq!(result.is_err(), true)
}

test "write with invalid capacity" {
  let bytes: Array[Byte] = [1, 2, 3]
  let res = write_process?(read_bytes_array!(bytes), 2)
  assert_eq!(res.is_err(), true)
}

test "write and flush buffer" {
  let data = [1, 2, 3, 4]
  let flushed = write_int!(data)
  assert_eq!(flushed, data)
}

test "write and recover utf8 string" {
  let s = "MoonBit测试123"
  let result = write_string!(s)
  assert_eq!(result, read_string!(s))
}


