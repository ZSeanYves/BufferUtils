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
/// Return the number of reads issued to the wrapped reader.
///
/// This is a diagnostic counter used by contract tests and benchmarks.
pub fn[R] BufReader::underlying_read_calls(self : BufReader[R]) -> Int {
  self.underlying_reads
}

///|
/// Return the number of reads that bypassed the internal buffer.
///
/// This is a diagnostic counter used by contract tests and benchmarks.
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
/// Create a lazy UTF-8 line cursor.
pub fn[R] BufReader::lines(self : BufReader[R]) -> Lines[R] {
  Lines::new(self)
}

///|
/// Create a lazy delimiter-splitting cursor.
pub fn[R] BufReader::split(self : BufReader[R], delimiter : Byte) -> Split[R] {
  Split::new(self, delimiter)
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
#inline
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
  let resident = self.end - self.position
  if resident > 0 {
    let count = Int::min(length, resident)
    FixedArray::unsafe_blit(dst, offset, self.buffer, self.position, count)
    self.position += count
    return count
  }
  if length >= self.buffer.length() {
    self.underlying_reads += 1
    self.bypass_reads += 1
    let count = Read::read(self.inner, dst, offset, length)
    validate_progress("BufReader::read", count, length)
    self.eof = count == 0
    return count
  }
  let available = BufRead::fill_buf(self)
  let count = Int::min(length, available.length())
  FixedArray::unsafe_blit(dst, offset, self.buffer, self.position, count)
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
