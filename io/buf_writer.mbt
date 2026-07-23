///|
/// A generic buffered writer over any `Write` implementation.
struct BufWriter[W] {
  inner : W
  buffer : FixedArray[Byte]
  capacity : Int
  mut start : Int
  mut end : Int
  mut underlying_writes : Int
  mut bypass_writes : Int
}

///|
/// A failed `finish` operation retaining the recoverable buffered writer.
pub struct BufWriterFinishError[W] {
  writer : BufWriter[W]
  error : IoError
}

///|
pub fn[W] BufWriterFinishError::error(
  self : BufWriterFinishError[W],
) -> IoError {
  self.error
}

///|
pub fn[W] BufWriterFinishError::into_inner(
  self : BufWriterFinishError[W],
) -> BufWriter[W] {
  self.writer
}

///|
/// Create a buffered writer with a positive capacity.
pub fn[W] BufWriter::new(
  inner : W,
  capacity? : Int = 8192,
) -> BufWriter[W] raise IoError {
  if capacity <= 0 {
    raise io_error(
      InvalidInput,
      "BufWriter::new",
      message="capacity must be positive",
    )
  }
  {
    inner,
    buffer: FixedArray::make(capacity, (0).to_byte()),
    capacity,
    start: 0,
    end: 0,
    underlying_writes: 0,
    bypass_writes: 0,
  }
}

///|
pub fn[W] BufWriter::capacity(self : BufWriter[W]) -> Int {
  self.capacity
}

///|
pub fn[W] BufWriter::buffered_len(self : BufWriter[W]) -> Int {
  self.end - self.start
}

///|
pub fn[W] BufWriter::underlying_write_calls(self : BufWriter[W]) -> Int {
  self.underlying_writes
}

///|
pub fn[W] BufWriter::bypass_write_calls(self : BufWriter[W]) -> Int {
  self.bypass_writes
}

///|
pub fn[W] BufWriter::get_ref(self : BufWriter[W]) -> W {
  self.inner
}

///|
pub fn[W] BufWriter::get_mut(self : BufWriter[W]) -> W {
  self.inner
}

///|
fn[W] BufWriter::compact(self : BufWriter[W]) -> Unit {
  if self.start == 0 {
    return
  }
  let remaining = self.end - self.start
  for i in 0..<remaining {
    self.buffer[i] = self.buffer[self.start + i]
  }
  self.start = 0
  self.end = remaining
}

///|
fn[W : Write] BufWriter::flush_pending(
  self : BufWriter[W],
) -> Unit raise IoError {
  let mut completed = 0
  while self.start < self.end {
    self.underlying_writes += 1
    let bytes = self.buffer.unsafe_reinterpret_as_bytes()
    let pending = self.end - self.start
    let count = Write::write(self.inner, bytes, self.start, pending) catch {
      error => {
        let progress = error.progress()
        validate_progress("BufWriter::flush", progress, pending)
        if progress != 0 {
          raise io_error(
            ContractViolation,
            "BufWriter::flush",
            progress=completed,
            message="a failed write reported committed bytes",
          )
        }
        raise error.add_progress(completed)
      }
    }
    validate_progress("BufWriter::flush", count, pending)
    if count == 0 {
      raise io_error(
        WriteZero,
        "BufWriter::flush",
        message="destination accepted zero buffered bytes",
      )
    }
    self.start += count
    completed += count
  }
  self.start = 0
  self.end = 0
}

///|
pub impl[W : Write] Write for BufWriter[W] with fn write(
  self,
  src,
  offset,
  length,
) {
  if offset < 0 || length < 0 || offset > src.length() - length {
    raise io_error(
      InvalidInput,
      "BufWriter::write",
      message="source range is invalid",
    )
  }
  if length == 0 {
    return 0
  }
  if self.buffered_len() > 0 && length > self.capacity - self.end {
    self.flush_pending()
  }
  if self.buffered_len() == 0 && length >= self.capacity {
    self.underlying_writes += 1
    self.bypass_writes += 1
    let count = Write::write(self.inner, src, offset, length)
    validate_progress("BufWriter::write", count, length)
    return count
  }
  if self.end + length > self.capacity {
    self.compact()
  }
  let count = Int::min(length, self.capacity - self.end)
  for i in 0..<count {
    self.buffer[self.end + i] = src[offset + i]
  }
  self.end += count
  count
}

///|
pub impl[W : Write] Write for BufWriter[W] with fn flush(self) {
  self.flush_pending()
  Write::flush(self.inner)
}

///|
/// Flush and return the wrapped writer.
pub fn[W : Write] BufWriter::finish(
  self : BufWriter[W],
) -> Result[W, BufWriterFinishError[W]] {
  try Write::flush(self) catch {
    error => Err({ writer: self, error })
  } noraise {
    _ => Ok(self.inner)
  }
}

///|
pub impl[W : Write + Seek] Seek for BufWriter[W] with fn seek(self, from) {
  Write::flush(self)
  Seek::seek(self.inner, from)
}

///|
pub impl[W : Write + Seek] Seek for BufWriter[W] with fn stream_position(self) {
  Write::flush(self)
  Seek::stream_position(self.inner)
}

///|
/// Return the wrapped writer and a copy of bytes still pending in the buffer.
/// This method performs no I/O and therefore cannot lose recovery state.
pub fn[W] BufWriter::into_parts(
  self : BufWriter[W],
) -> (W, @buffer.SharedBytes) {
  (
    self.inner,
    @buffer.SharedBytes::from_fixed_array(self.buffer, self.start, self.end),
  )
}
