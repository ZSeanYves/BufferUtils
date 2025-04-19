/// 从给定 Bytes 中读取所有内容，返回 Array[Byte]
pub fn read(data: Bytes) -> Array[Byte]!BufferError {
  let reader = new_reader(data)
  let result = []

  while not(reader.is_empty()) {
    let b = reader.read_byte!()
    result.push(b)
  }
  result
}


/// 将字节数组写入缓冲区并 flush，返回写入结果
pub fn write(data: Array[Byte], cap: Int) -> Array[Byte]! BufferError {
    let writer = new_writer!(cap)
    writer.write_all!(data)
    writer.flush!()
}

 
/// 从输入 Bytes 中读取所有字节并写入，返回输出内容
pub fn copy_bytes(data: Bytes, cap~: Int = 128) -> Array[Byte]!BufferError {
  let bytes = read!(data)
  write!(bytes, cap)
}

