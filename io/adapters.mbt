///|
/// An in-memory read/write cursor with seek support.
pub struct Cursor {
  data : Array[Byte]
  mut position : Int
}

///|
pub fn Cursor::new(data : ArrayView[Byte]) -> Cursor {
  { data: data.to_owned(), position: 0 }
}

///|
pub fn Cursor::position(self : Cursor) -> Int64 {
  self.position.to_int64()
}

///|
pub fn Cursor::len(self : Cursor) -> Int {
  self.data.length()
}

///|
pub fn Cursor::to_bytes(self : Cursor) -> Bytes {
  Bytes::from_array(self.data[:])
}

///|
pub impl Read for Cursor with fn read(self, dst, offset, length) {
  if offset < 0 || length < 0 || offset > dst.length() - length {
    raise io_error(
      InvalidInput,
      "Cursor::read",
      message="destination range is invalid",
    )
  }
  let count = Int::min(length, self.data.length() - self.position)
  for i in 0..<count {
    dst[offset + i] = self.data[self.position + i]
  }
  self.position += count
  count
}

///|
pub impl Write for Cursor with fn write(self, src, offset, length) {
  if offset < 0 || length < 0 || offset > src.length() - length {
    raise io_error(
      InvalidInput,
      "Cursor::write",
      message="source range is invalid",
    )
  }
  if length > 2147483647 - self.position {
    raise io_error(
      InvalidInput,
      "Cursor::write",
      message="cursor length overflow",
    )
  }
  let end = self.position + length
  if end > self.data.length() {
    self.data.resize(end, (0).to_byte())
  }
  for i in 0..<length {
    self.data[self.position + i] = src[offset + i]
  }
  self.position = end
  length
}

///|
pub impl Write for Cursor with fn flush(_self) {
  ()
}

///|
pub impl BufRead for Cursor with fn fill_buf(self) {
  self.data[self.position:]
}

///|
pub impl BufRead for Cursor with fn consume(self, count) {
  if count < 0 || count > self.data.length() - self.position {
    raise io_error(
      InvalidInput,
      "Cursor::consume",
      message="consume is outside the cursor",
    )
  }
  self.position += count
}

///|
fn cursor_seek_target(
  length : Int,
  position : Int,
  from : SeekFrom,
) -> Int raise IoError {
  let target = match from {
    Start(offset) => offset
    Current(offset) => position.to_int64() + offset
    End(offset) => length.to_int64() + offset
  }
  if target < 0L || target > 2147483647L {
    raise io_error(
      InvalidInput,
      "seek",
      message="seek target is outside supported range",
    )
  }
  target.to_int()
}

///|
pub impl Seek for Cursor with fn seek(self, from) {
  self.position = cursor_seek_target(self.data.length(), self.position, from)
  self.position.to_int64()
}

///|
pub impl Seek for Cursor with fn stream_position(self) {
  self.position.to_int64()
}

///|
/// A reader that is always at EOF.
pub struct Empty {
  storage : Array[Byte]
}

///|
pub fn Empty::new() -> Empty {
  { storage: [] }
}

///|
pub impl Read for Empty with fn read(_self, _dst, _offset, _length) {
  0
}

///|
pub impl BufRead for Empty with fn fill_buf(self) {
  self.storage[:]
}

///|
pub impl BufRead for Empty with fn consume(_self, count) {
  if count != 0 {
    raise io_error(
      InvalidInput,
      "Empty::consume",
      message="empty reader has no bytes",
    )
  }
}

///|
/// An infinite reader that repeats one byte.
pub struct Repeat {
  byte : Byte
}

///|
pub fn Repeat::new(byte : Byte) -> Repeat {
  { byte, }
}

///|
pub impl Read for Repeat with fn read(self, dst, offset, length) {
  if offset < 0 || length < 0 || offset > dst.length() - length {
    raise io_error(
      InvalidInput,
      "Repeat::read",
      message="destination range is invalid",
    )
  }
  for i in 0..<length {
    dst[offset + i] = self.byte
  }
  length
}

///|
/// Limit reads from an underlying reader to a fixed number of bytes.
pub struct Take[R] {
  inner : R
  mut remaining : Int64
}

///|
pub fn[R] Take::new(inner : R, limit : Int64) -> Take[R] raise IoError {
  if limit < 0L {
    raise io_error(
      InvalidInput,
      "Take::new",
      message="limit must be non-negative",
    )
  }
  { inner, remaining: limit }
}

///|
pub fn[R] Take::remaining(self : Take[R]) -> Int64 {
  self.remaining
}

///|
pub fn[R] Take::into_inner(self : Take[R]) -> R {
  self.inner
}

///|
pub impl[R : Read] Read for Take[R] with fn read(self, dst, offset, length) {
  if offset < 0 || length < 0 || offset > dst.length() - length {
    raise io_error(
      InvalidInput,
      "Take::read",
      message="destination range is invalid",
    )
  }
  if self.remaining == 0L || length == 0 {
    return 0
  }
  let count = if self.remaining < length.to_int64() {
    self.remaining.to_int()
  } else {
    dst.length()
  }
  let progress = Read::read(self.inner, dst, offset, count)
  validate_progress("Take::read", progress, count)
  self.remaining -= progress.to_int64()
  progress
}

///|
/// Read one reader to EOF and then continue with another.
pub struct Chain[A, B] {
  first : A
  second : B
  mut first_done : Bool
}

///|
pub fn[A, B] Chain::new(first : A, second : B) -> Chain[A, B] {
  { first, second, first_done: false }
}

///|
pub impl[A : Read, B : Read] Read for Chain[A, B] with fn read(
  self,
  dst,
  offset,
  length,
) {
  if !self.first_done {
    let count = Read::read(self.first, dst, offset, length)
    if count != 0 {
      return count
    }
    self.first_done = true
  }
  Read::read(self.second, dst, offset, length)
}

///|
/// A writer that flushes complete lines while retaining an incomplete tail.
pub struct LineWriter[W] {
  inner : W
  buffer : Array[Byte]
  mut pending_error : IoError?
}

///|
pub fn[W] LineWriter::new(inner : W) -> LineWriter[W] {
  { inner, buffer: [], pending_error: None }
}

///|
fn[W] LineWriter::discard_prefix(self : LineWriter[W], count : Int) -> Unit {
  let remaining = self.buffer.length() - count
  for i in 0..<remaining {
    self.buffer[i] = self.buffer[count + i]
  }
  self.buffer.resize(remaining, (0).to_byte())
}

///|
pub impl[W : Write] Write for LineWriter[W] with fn write(
  self,
  src,
  offset,
  length,
) {
  if offset < 0 || length < 0 || offset > src.length() - length {
    raise io_error(
      InvalidInput,
      "LineWriter::write",
      message="source range is invalid",
    )
  }
  match self.pending_error {
    Some(error) => raise error
    None => ()
  }
  for i in 0..<length {
    self.buffer.push(src[offset + i])
  }
  let mut complete = 0
  for i, byte in self.buffer {
    if byte == b'\n' {
      complete = i + 1
    }
  }
  if complete > 0 {
    try Write::write_all(self.inner, self.buffer[0:complete]) catch {
      error => {
        let progress = error.progress()
        validate_progress("LineWriter::write", progress, complete)
        self.discard_prefix(progress)
        self.pending_error = Some(error)
      }
    } noraise {
      _ => self.discard_prefix(complete)
    }
  }
  length
}

///|
pub impl[W : Write] Write for LineWriter[W] with fn flush(self) {
  match self.pending_error {
    Some(error) => raise error
    None => ()
  }
  if !self.buffer.is_empty() {
    Write::write_all(self.inner, self.buffer[:]) catch {
      error => {
        let progress = error.progress()
        validate_progress("LineWriter::flush", progress, self.buffer.length())
        self.discard_prefix(progress)
        raise error
      }
    }
    self.buffer.clear()
  }
  Write::flush(self.inner)
}

///|
pub fn[W] LineWriter::into_parts(self : LineWriter[W]) -> (W, Bytes) {
  (self.inner, Bytes::from_array(self.buffer[:]))
}

///|
/// A paired buffered reader and writer for full-duplex transports.
pub struct BufStream[R, W] {
  reader : BufReader[R]
  writer : BufWriter[W]
}

///|
pub fn[R, W] BufStream::new(
  reader : R,
  writer : W,
  capacity? : Int = 8192,
) -> BufStream[R, W] raise IoError {
  {
    reader: BufReader::new(reader, capacity~),
    writer: BufWriter::new(writer, capacity~),
  }
}

///|
pub impl[R : Read, W] Read for BufStream[R, W] with fn read(
  self,
  dst,
  offset,
  length,
) {
  Read::read(self.reader, dst, offset, length)
}

///|
pub impl[R : Read, W : Write] BufRead for BufStream[R, W] with fn fill_buf(self) {
  BufRead::fill_buf(self.reader)
}

///|
pub impl[R : Read, W : Write] BufRead for BufStream[R, W] with fn consume(
  self,
  count,
) {
  BufRead::consume(self.reader, count)
}

///|
pub impl[R, W : Write] Write for BufStream[R, W] with fn write(
  self,
  src,
  offset,
  length,
) {
  Write::write(self.writer, src, offset, length)
}

///|
pub impl[R, W : Write] Write for BufStream[R, W] with fn flush(self) {
  Write::flush(self.writer)
}

///|
/// A write-only sink contract useful for generic producer code.
pub(open) trait Sink {
  fn send(Self, Bytes, Int, Int) -> Unit raise IoError
  fn close(Self) -> Unit raise IoError
}

///|
pub impl[W : Write] Sink for BufWriter[W] with fn send(
  self,
  bytes,
  offset,
  length,
) {
  if offset < 0 || length < 0 || offset > bytes.length() - length {
    raise io_error(
      InvalidInput,
      "Sink::send",
      message="source range is invalid",
    )
  }
  let mut completed = 0
  while completed < length {
    let count = Write::write(
      self,
      bytes,
      offset + completed,
      length - completed,
    )
    validate_progress("Sink::send", count, length - completed)
    if count == 0 {
      raise io_error(WriteZero, "Sink::send")
    }
    completed += count
  }
}

///|
pub impl[W : Write] Sink for BufWriter[W] with fn close(self) {
  Write::flush(self)
}
