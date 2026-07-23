///|
/// A generic buffered reader over any `Read` implementation.
struct BufReader[R] {
  inner : R
  buffer : FixedArray[Byte]
  mut position : Int
  mut end : Int
  mut eof : Bool
  mut underlying_reads : Int
  mut bypass_reads : Int
}

///|
/// Create a buffered reader with a positive capacity.
pub fn[R] BufReader::new(
  inner : R,
  capacity? : Int = 8192,
) -> BufReader[R] raise IoError {
  if capacity <= 0 {
    raise io_error(
      InvalidInput,
      "BufReader::new",
      message="capacity must be positive",
    )
  }
  {
    inner,
    buffer: FixedArray::make(capacity, (0).to_byte()),
    position: 0,
    end: 0,
    eof: false,
    underlying_reads: 0,
    bypass_reads: 0,
  }
}

///|
pub fn[R] BufReader::capacity(self : BufReader[R]) -> Int {
  self.buffer.length()
}

///|
pub fn[R] BufReader::buffered_len(self : BufReader[R]) -> Int {
  self.end - self.position
}

///|
pub fn[R] BufReader::underlying_read_calls(self : BufReader[R]) -> Int {
  self.underlying_reads
}

///|
pub fn[R] BufReader::bypass_read_calls(self : BufReader[R]) -> Int {
  self.bypass_reads
}

///|
/// Return the unread portion currently resident in the fixed buffer.
pub fn[R] BufReader::buffer(self : BufReader[R]) -> ArrayView[Byte] {
  self.buffer[self.position:self.end]
}

///|
/// Ensure up to `count` bytes are buffered and return the available prefix.
pub fn[R : Read] BufReader::peek(
  self : BufReader[R],
  count : Int,
) -> ArrayView[Byte] raise IoError {
  if count < 0 {
    raise io_error(
      InvalidInput,
      "BufReader::peek",
      message="count must be non-negative",
    )
  }
  let available = BufRead::fill_buf(self)
  available[0:Int::min(count, available.length())]
}

///|
/// Seek relative to the logical position without discarding prefetched bytes.
pub fn[R : Seek] BufReader::seek_relative(
  self : BufReader[R],
  offset : Int64,
) -> Unit raise IoError {
  ignore(Seek::seek(self, Current(offset)))
}

///|
/// Read and decode all UTF-8 lines until EOF.
pub fn[R : Read] BufReader::lines(
  self : BufReader[R],
) -> Array[String] raise IoError {
  let result : Array[String] = []
  while true {
    let line = StringBuilder()
    let count = BufRead::read_line(self, line)
    if count == 0 {
      break
    }
    result.push(line.to_string())
  }
  result
}

///|
/// Split the remaining input at a delimiter, retaining byte segments.
pub fn[R : Read] BufReader::split(
  self : BufReader[R],
  delimiter : Byte,
) -> Array[Array[Byte]] raise IoError {
  let result : Array[Array[Byte]] = []
  while true {
    let segment : Array[Byte] = []
    let count = BufRead::read_until(self, delimiter, segment)
    if count == 0 {
      break
    }
    if segment[segment.length() - 1] == delimiter {
      segment.truncate(segment.length() - 1)
    }
    result.push(segment)
  }
  result
}

///|
pub fn[R] BufReader::get_ref(self : BufReader[R]) -> R {
  self.inner
}

///|
pub fn[R] BufReader::get_mut(self : BufReader[R]) -> R {
  self.inner
}

///|
pub impl[R : Read] Read for BufReader[R] with fn read(self, dst, offset, length) {
  if offset < 0 || length < 0 || offset > dst.length() - length {
    raise io_error(
      InvalidInput,
      "BufReader::read",
      message="destination range is invalid",
    )
  }
  if length == 0 {
    return 0
  }
  if self.buffered_len() > 0 {
    let count = Int::min(length, self.buffered_len())
    for i in 0..<count {
      dst[offset + i] = self.buffer[self.position + i]
    }
    self.position += count
    return count
  }
  if length >= self.capacity() {
    self.underlying_reads += 1
    self.bypass_reads += 1
    let count = Read::read(self.inner, dst, offset, length)
    validate_progress("BufReader::read", count, length)
    self.eof = count == 0
    return count
  }
  let available = BufRead::fill_buf(self)
  let count = Int::min(length, available.length())
  for i in 0..<count {
    dst[offset + i] = available[i]
  }
  self.position += count
  count
}

///|
pub impl[R : Read] BufRead for BufReader[R] with fn fill_buf(self) {
  if self.buffered_len() > 0 {
    return self.buffer[self.position:self.end]
  }
  if self.eof {
    return self.buffer[0:0]
  }
  self.position = 0
  self.end = 0
  self.underlying_reads += 1
  let count = Read::read_fixed(self.inner, self.buffer, 0, self.buffer.length())
  validate_progress("BufReader::fill_buf", count, self.buffer.length())
  self.end = count
  self.eof = count == 0
  self.buffer[0:count]
}

///|
pub impl[R : Read] BufRead for BufReader[R] with fn consume(self, count) {
  if count < 0 {
    raise io_error(
      InvalidInput,
      "BufReader::consume",
      message="count must be non-negative",
    )
  }
  if count > self.buffered_len() {
    raise io_error(
      ContractViolation,
      "BufReader::consume",
      message="cannot consume beyond the current buffer",
    )
  }
  self.position += count
}

///|
/// Seek after accounting for bytes already prefetched into the reader buffer.
pub impl[R : Seek] Seek for BufReader[R] with fn seek(self, from) {
  let adjusted = match from {
    Current(offset) => Current(offset - self.buffered_len().to_int64())
    other => other
  }
  let position = Seek::seek(self.inner, adjusted)
  self.position = 0
  self.end = 0
  self.eof = false
  position
}

///|
pub impl[R : Seek] Seek for BufReader[R] with fn stream_position(self) {
  Seek::stream_position(self.inner) - self.buffered_len().to_int64()
}

///|
/// Return the wrapped reader and discard unread buffered data.
pub fn[R] BufReader::into_inner(self : BufReader[R]) -> R {
  self.inner
}

///|
/// Return the wrapped reader and a copy of unread buffered bytes.
pub fn[R] BufReader::into_parts(self : BufReader[R]) -> (R, Bytes) {
  (self.inner, Bytes::from_array(self.buffer[self.position:self.end]))
}
