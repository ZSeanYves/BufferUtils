/// The `BufferWriter` struct
/// A utility for writing bytes into a dynamically tracked buffer.
pub struct BufferWriter {
  mut buf: Array[Byte]   /// Internal byte buffer
  mut pos: Int           /// Current write position (offset)
  capacity: Int          /// Maximum buffer capacity
}

/// Create a new `BufferWriter`
/// `cap` specifies the capacity; must be a positive integer.
/// Raises `BufferError::InvalidCapacity` if cap ≤ 0.
fn new_writer(cap: Int) -> BufferWriter!BufferError {
  if cap <= 0 {
    raise BufferError::InvalidCapacity("无效的容量：缓冲区大小必须为正")
  }

  let writer: BufferWriter = {
    buf: [],
    pos: 0,
    capacity: cap
  }
  writer
}

/// Write a single byte into the buffer.
/// Raises `BufferError::Overflow` if the buffer is full.
impl BufWritable for BufferWriter with write_byte(self: BufferWriter, b: Byte) -> Unit!BufferError {
  if self.pos >= self.capacity {
    raise BufferError::Overflow("写入失败:缓冲区溢出w")
  }
  self.buf.push(b)
  self.pos += 1
}

/// Write multiple bytes to the buffer in batch.
/// Raises `BufferError::Overflow` if total size exceeds capacity.
impl BufWritable for BufferWriter with write_all(self: BufferWriter, data: Array[Byte]) -> Unit!BufferError {
  if self.pos + data.length() > self.capacity {
    raise BufferError::Overflow("写入失败：数据超过缓冲区容量")
  }
  for byte in data {
    self.buf.push(byte)
    self.pos += 1
  }
}

/// Flush the buffer and return a copy of the current written content.
/// Note: Does not clear the buffer — you must call `clear()` explicitly.
/// Simulates an error if buffer is empty.
impl BufWritable for BufferWriter with flush(self: BufferWriter) -> Array[Byte]!BufferError {
  if self.pos == 0 {
    raise BufferError::Flush("缓冲刷新失败：缓冲区是空的")
  }

  let result = []
  for i in self.buf {
    result.push(i)
  }
  result
}

/// Clear the buffer and reset the write position to 0.
impl BufWritable for BufferWriter with clear(self: BufferWriter) -> Unit {
  self.buf = []
  self.pos = 0
}

/// Rewind the position to the beginning (without clearing content).
/// This allows for overwriting the buffer content from the start.
impl BufWritable for BufferWriter with writer_rewind(self: BufferWriter) -> Unit {
  self.pos = 0
}

/// Get the number of remaining writable slots in the buffer.
impl BufWritable for BufferWriter with writer_remaining(self: BufferWriter) -> Int {
  self.capacity - self.pos
}
