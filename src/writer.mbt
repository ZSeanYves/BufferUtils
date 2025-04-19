pub struct BufferWriter {
  mut buf: Array[Byte]
  mut pos: Int
  capacity: Int
}
/// 创建一个新的 BufferWriter
/// cap 表示缓冲区容量，必须为正数，否则返回错误
pub fn new_writer(cap: Int) -> BufferWriter!BufferError {
  if cap <= 0 {
    raise BufferError::InvalidCapacity("无效容量：缓冲区大小必须为正数")
  }

  let writer: BufferWriter = {
    buf: [],
    pos: 0,
    capacity: cap
  }
  writer
}

/// 写入一个字节到缓冲区
/// 如果已满则抛出 BufferOverflowError
pub fn write_byte(self: BufferWriter, b: Byte) -> Unit!BufferError {
  if self.pos >= self.capacity {
    raise BufferError::Overflow("写入失败：超出缓冲区容量")
  }
  self.buf.push(b)
  self.pos += 1
}

/// 批量写入多个字节
/// 如果超出容量，则抛出 BufferOverflowError
pub fn write_all(self: BufferWriter, data: Array[Byte]) -> Unit!BufferError {
  if self.pos + data.length() > self.capacity {
    raise BufferError::Overflow("写入失败：数据长度超出缓冲区容量")
  }
  for byte in data {
    self.buf.push(byte)
    self.pos += 1
  }
}

/// 刷新缓冲区：返回当前已写入的内容
/// 注意：刷新后不会清空缓冲，用户需自行调用 clear()
pub fn flush(self: BufferWriter) -> Array[Byte]!BufferError {
  // 模拟条件：空缓冲时抛出刷新失败（作为占位演示）
  if self.pos == 0 {
    raise BufferError::Flush("刷新失败：缓冲区为空，无法输出")
  }

  // 正常情况下返回一个副本（复制而非引用，便于调用方消费）
  let result = []
  for i in self.buf {
    result.push(i)
  }
  result
}

/// 清空缓冲区，重置位置
pub fn clear(self: BufferWriter) -> Unit {
  self.buf = []
  self.pos = 0
}

/// 重置指针到开头，不清空内容（用于覆盖）
pub fn writer_rewind(self: BufferWriter) -> Unit {
  self.pos = 0
}

/// 获取剩余可写入空间
pub fn writer_remaining(self: BufferWriter) -> Int {
  self.capacity - self.pos
}
