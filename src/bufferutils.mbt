///基本封装函数
/// 
/// 
/// 
/// 
/// 
/// 
/// 
/// 
/// 
/// 
/// 
/// 
/// 
/// 
/// 
/// 
/// 
/// 
/// 
/// 从给定 Bytes 中读取所有内容，返回 Array[Byte]
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

/// 将Bytes数组转为字节数组并读取
pub fn read_bytes_array(arr: Array[Byte]) -> Array[Byte]!BufferError {
  let bytes = Bytes::from_array(arr)
  read_bytes!(bytes)
}

/// 将整形数组转为字节数组并读取
pub fn read_ints(data: Array[Int]) -> Array[Byte]!BufferError {
  let bytes: Array[Byte] = data.map(fn(x) { x.to_byte() })
  read_bytes!(Bytes::from_array(bytes))
}

/// 将字符串转为字节数组并读取
pub fn read_string(s: String) -> Array[Byte]!BufferError {
  let  byte_array: Array[Byte] = []
  for i in 0..<s.length() {
    // 获取每个字符的 ASCII / UTF-8 编码值，并转换成 Byte
    let b = s.charcode_at(i).to_byte()
    byte_array.push(b)
  }

  // 封装为 Bytes 类型并调用主读取逻辑
  read_bytes!(Bytes::from_array(byte_array))
}


/// 将字节数组写入缓冲区并 flush，返回写入结果
pub fn write_process(data: Array[Byte], cap: Int) -> Array[Byte]! BufferError {
    let writer = new_writer!(cap)
    writer.write_all!(data)
    writer.flush!()
}

/// 将字节数组写入缓冲区并 flush，返回写入结果,并清空缓冲
pub fn write_process_and_clear(data: Array[Byte], cap~: Int = 128) -> Array[Byte]!BufferError {
  let writer = new_writer!(cap)
  writer.write_all!(data)
  let result = writer.flush!()
  writer.clear()
  result
}



 
/// 从输入 Bytes 中读取所有字节并写入，返回输出内容
pub fn write_bytes(data: Bytes, cap~: Int = 128) -> Array[Byte]!BufferError {
  let bytes = read_bytes!(data)
  write_process!(bytes, cap)
}

//// 从输入 Bytes 中读取所有字节并写入，返回输出内容,并清空缓冲
pub fn write_bytes_and_clear(data: Bytes, _cap~: Int = 128) -> Array[Byte]!BufferError {
  let bytes = read_bytes!(data)
  write_process_and_clear!(bytes)
}

/// 从输入 Int数组 中读取所有字节并写入，返回输出内容
pub fn write_int(data: Array[Int], cap~: Int = 128) -> Array[Int]!BufferError {
  let bytes = read_ints!(data)
  write_process!(bytes, cap).map(fn(b) { b.to_int() })
}

/// 从输入 Int数组 中读取所有字节并写入，返回输出内容,并清空缓冲
pub fn write_int_and_clear(data: Array[Int], _cap~: Int = 128) -> Array[Int]!BufferError {
  let bytes = read_ints!(data)
  write_process_and_clear!(bytes).map(fn(b) { b.to_int() })
}

/// 从输入 String字符串 中读取所有字节并写入，返回输出内容
/// 目前无法实现将 Byte 重新转换成 String 类型输出，需等待后续开发
pub fn write_string(data: String, cap~: Int = 128) -> Array[Byte]!BufferError {
  let bytes = read_string!(data)
  write_process!(bytes, cap)
}

/// 从输入 String字符串 中读取所有字节并写入，返回输出内容,并清空缓冲
pub fn write_string_and_clear(data: String, _cap~: Int = 128) -> Array[Byte]!BufferError {
  let bytes = read_string!(data)
  write_process_and_clear!(bytes)
}
///处理错误后的最终实现函数
///
/// 
/// 
/// 
/// 
/// 
/// 
/// 
/// 
/// 
/// 
/// 
/// 
/// 
/// 
/// 
/// 
/// 
/// 
/// 
/// 
/// 
/// 
pub fn readBytes(data: Bytes) -> Array[Byte] {
  match read_bytes?(data) {
    Ok(res) => res
    Err(_) => []
  }
}

pub fn readBytesArray(arr: Array[Byte]) -> Array[Byte] {
  match read_bytes_array?(arr) {
    Ok(res) => res
    Err(_) => []
  }
}

pub fn readInts(data: Array[Int]) -> Array[Byte] {
  match read_ints?(data) {
    Ok(res) => res
    Err(_) => []
  }
}

pub fn readString(s: String) -> Array[Byte] {
  match read_string?(s) {
    Ok(res) => res
    Err(_) => []
  }
}

pub fn writeBytes(data: Bytes, _cap~: Int = 128) -> Array[Byte] {
  match write_bytes?(data) {
    Ok(res) => res
    Err(_) => []
  }
}

pub fn writeBytesClear(data: Bytes, _cap~: Int = 128) -> Array[Byte] {
  match write_bytes_and_clear?(data) {
    Ok(res) => res
    Err(_) => []
  }
}

pub fn writeInt(data: Array[Int], _cap~: Int = 128) -> Array[Int] {
  match write_int?(data) {
    Ok(res) => res
    Err(_) => []
  }
}

pub fn writeIntClear(data: Array[Int], _cap~: Int = 128) -> Array[Int] {
  match write_int_and_clear?(data) {
    Ok(res) => res
    Err(_) => []
  }
}

pub fn writeString(data: String, _cap~: Int = 128) -> Array[Byte] {
  match write_string?(data) {
    Ok(res) => res
    Err(_) => []
  }
}

pub fn writeStringClear(data: String, _cap~: Int = 128) -> Array[Byte] {
  match write_string_and_clear?(data) {
    Ok(res) => res
    Err(_) => []
  }
}
///测试用例
/// 
/// 
/// 
/// 
/// 
/// 
/// 
/// 
/// 
/// 
/// 
/// 
/// 
/// 
/// 
/// 
/// 
/// 


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


