/// 缓冲读取器结构体
/// 用于从 Bytes 中顺序读取字节
pub struct BufferReader {
  buf: Bytes        /// 原始字节数据
  mut pos: Int      /// 当前读取位置（偏移量）
}


/// 创建一个新的 BufferReader
/// 从给定的字节序列 Bytes 初始化
pub fn new_reader(buf: Bytes) -> BufferReader {
  let reader: BufferReader= {
    buf: buf,
    pos: 0
  }
  reader
}

pub fn to_bytes(arr: Array[Int]) -> Array[Byte] {
  arr.map(fn(x) { x.to_byte() })
}

/// 从缓冲区中读取下一个字节，并将位置前移
/// 若读取位置已到结尾，抛出 BufferUnderflowError
pub fn read_byte(self: BufferReader) -> Byte!BufferError {
  if self.pos >= self.buf.length() {
    raise BufferError::Underflow("读取失败：到达缓冲区末尾")
  }
  let byte: Byte = self.buf[self.pos]
  self.pos += 1
  byte
}

/// 预览当前位置的字节，不推进位置
/// 若读取位置无效，则抛出 BufferUnderflowError
pub fn peek(self: BufferReader) -> Byte!BufferError {
  if self.pos >= self.buf.length() {
    raise BufferError::Underflow("读取失败：无法预览空字节")
  }
  self.buf[self.pos]
}

/// 跳过 n 个字节
/// 注意：当前不检查是否越界
pub fn skip(self: BufferReader, n: Int) -> Unit {
  self.pos += n
}

/// 判断是否已经读取至末尾（是否为空）
pub fn is_empty(self: BufferReader) -> Bool {
  self.pos >= self.buf.length()
}

/// 返回剩余未读取的字节数量
pub fn reader_remaining(self: BufferReader) -> Int {
  self.buf.length() - self.pos
}

/// 重置读取位置为起始位置
pub fn reader_rewind(self: BufferReader) -> Unit {
  self.pos = 0
}

/// 返回剩余未读的字节内容（当前未支持）
/// TODO: 等 MoonBit Bytes 支持切片后补充实现
pub fn buffer(_self: BufferReader) -> Array[Byte] {
  []
}
