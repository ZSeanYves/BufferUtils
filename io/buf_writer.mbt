///|
/// A generic buffered writer over any `Write` implementation.
struct BufWriter[W] {
  inner : W
  buffer : Array[Byte]
  capacity : Int
  mut underlying_writes : Int
  mut bypass_writes : Int
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
    buffer: Array::new(capacity~),
    capacity,
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
  self.buffer.length()
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
fn[W] BufWriter::discard_prefix(self : BufWriter[W], count : Int) -> Unit {
  let remaining = self.buffer.length() - count
  for i in 0..<remaining {
    self.buffer[i] = self.buffer[count + i]
  }
  self.buffer.resize(remaining, (0).to_byte())
}

///|
fn[W : Write] BufWriter::flush_pending(
  self : BufWriter[W],
) -> Unit raise IoError {
  let mut completed = 0
  while !self.buffer.is_empty() {
    self.underlying_writes += 1
    let count = Write::write(self.inner, self.buffer[:]) catch {
      error => {
        let progress = error.progress()
        validate_progress("BufWriter::flush", progress, self.buffer.length())
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
    validate_progress("BufWriter::flush", count, self.buffer.length())
    if count == 0 {
      raise io_error(
        WriteZero,
        "BufWriter::flush",
        message="destination accepted zero buffered bytes",
      )
    }
    self.discard_prefix(count)
    completed += count
  }
}

///|
pub impl[W : Write] Write for BufWriter[W] with fn write(self, src) {
  if src.is_empty() {
    return 0
  }
  if !self.buffer.is_empty() &&
    src.length() > self.capacity - self.buffer.length() {
    self.flush_pending()
  }
  if self.buffer.is_empty() && src.length() >= self.capacity {
    self.underlying_writes += 1
    self.bypass_writes += 1
    let count = Write::write(self.inner, src)
    validate_progress("BufWriter::write", count, src.length())
    return count
  }
  let count = Int::min(src.length(), self.capacity - self.buffer.length())
  append_bytes(self.buffer, src[0:count])
  count
}

///|
pub impl[W : Write] Write for BufWriter[W] with fn flush(self) {
  self.flush_pending()
  Write::flush(self.inner)
}

///|
/// Flush and return the wrapped writer.
pub fn[W : Write] BufWriter::finish(self : BufWriter[W]) -> W raise IoError {
  Write::flush(self)
  self.inner
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
pub fn[W] BufWriter::into_parts(self : BufWriter[W]) -> (W, Bytes) {
  (self.inner, Bytes::from_array(self.buffer[:]))
}
