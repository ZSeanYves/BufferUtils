///| The `BufferReader` struct
/// A utility for sequentially reading bytes from a `Bytes` object.
pub struct BufferReader {
  /// Original byte buffer (immutable)
  /// Current read position (byte offset)
  buf : Bytes
  mut pos : Int
}

///| Create a new `BufferReader`
/// Initializes the reader from a given byte sequence.
pub fn new_reader(buf : Bytes) -> BufferReader {
  let reader : BufferReader = { buf, pos: 0 }
  reader
}

///| Read the next byte from the buffer, advancing the position by 1.
/// Raises `BufferError::Underflow` if the current position is out of bounds.
pub fn read_byte(self : BufferReader) -> Byte raise BufferError {
  if self.pos >= self.buf.length() {
    raise BufferError::Underflow("读取失败：到达缓冲区的末尾")
  }
  let byte : Byte = self.buf[self.pos]
  self.pos += 1
  byte
}

///| Peek at the byte at the current position without advancing it.
/// Raises `BufferError::Underflow` if the buffer is empty or position is invalid.
pub fn peek(self : BufferReader) -> Byte raise BufferError {
  if self.pos >= self.buf.length() {
    raise BufferError::Underflow("读取失败：空缓冲区")
  }
  self.buf[self.pos]
}

///| Skip forward by `n` bytes in the buffer.
/// Note: This does not perform bounds checking.
pub fn skip(self : BufferReader, n : Int) -> Unit {
  self.pos += n
}

///| Check whether the buffer has been fully read (i.e., no remaining bytes).
pub fn is_empty(self : BufferReader) -> Bool {
  self.pos >= self.buf.length()
}

///| Return the number of remaining unread bytes in the buffer.
pub fn reader_remaining(self : BufferReader) -> Int {
  self.buf.length() - self.pos
}

///| Reset the read position back to the beginning of the buffer.
pub fn reader_rewind(self : BufferReader) -> Unit {
  self.pos = 0
}

