///|
/// The `BufferReader` struct
/// A utility for sequentially reading bytes from a `Bytes` object.
pub struct BufferReader {
  /// Original byte buffer (immutable)
  /// Current read position (byte offset)
  buf : Bytes
  mut pos : Int
}

///|
/// Create a new `BufferReader`
/// Initializes the reader from a given byte sequence.
pub fn new_reader(buf : Bytes) -> BufferReader {
  let reader : BufferReader = { buf, pos: 0 }
  reader
}

///|
fn validate_non_negative_length(n : Int) -> Unit raise BufferError {
  if n < 0 {
    raise BufferError::InvalidInput("requested byte count must be non-negative")
  }
}

///|
fn BufferReader::ensure_available(
  self : BufferReader,
  n : Int,
) -> Unit raise BufferError {
  validate_non_negative_length(n)
  if self.remaining() < n {
    raise BufferError::Underflow("not enough bytes remaining in buffer")
  }
}

///|
/// Read the next byte from the buffer, advancing the position by 1.
/// Raises `BufferError::Underflow` if the current position is out of bounds.
pub fn BufferReader::read_byte(self : BufferReader) -> Byte raise BufferError {
  self.ensure_available(1)
  let byte : Byte = self.buf[self.pos]
  self.pos += 1
  byte
}

///|
/// Peek at the byte at the current position without advancing it.
/// Raises `BufferError::Underflow` if the buffer is empty or position is invalid.
pub fn BufferReader::peek_byte(self : BufferReader) -> Byte raise BufferError {
  self.ensure_available(1)
  self.buf[self.pos]
}

///|
/// Read exactly `n` bytes and advance the current position.
pub fn BufferReader::read_exact(
  self : BufferReader,
  n : Int,
) -> Array[Byte] raise BufferError {
  self.ensure_available(n)
  let result : Array[Byte] = []
  for _ in 0..<n {
    result.push(self.buf[self.pos])
    self.pos += 1
  }
  result
}

///|
/// Read all remaining bytes and advance the current position to the end.
pub fn BufferReader::read_remaining(self : BufferReader) -> Array[Byte] {
  let remaining = self.remaining()
  let result : Array[Byte] = []
  for _ in 0..<remaining {
    result.push(self.buf[self.pos])
    self.pos += 1
  }
  result
}

///|
/// Skip forward by `n` bytes in the buffer.
pub fn BufferReader::skip(
  self : BufferReader,
  n : Int,
) -> Unit raise BufferError {
  self.ensure_available(n)
  self.pos += n
}

///|
/// Check whether the buffer has been fully read (i.e., no remaining bytes).
pub fn BufferReader::is_empty(self : BufferReader) -> Bool {
  self.remaining() == 0
}

///|
/// Return the number of remaining unread bytes in the buffer.
pub fn BufferReader::remaining(self : BufferReader) -> Int {
  if self.pos >= self.buf.length() {
    0
  } else {
    self.buf.length() - self.pos
  }
}

///|
/// Reset the read position back to the beginning of the buffer.
pub fn BufferReader::rewind(self : BufferReader) -> Unit {
  self.pos = 0
}

///|
/// Return the current read position.
pub fn BufferReader::position(self : BufferReader) -> Int {
  self.pos
}

///|
/// Return the total buffer length in bytes.
pub fn BufferReader::len(self : BufferReader) -> Int {
  self.buf.length()
}
