///|
/// A buffered writer that flushes batched writes into a sink.
pub struct BufWriter {
  sink : MemorySink
  buf : Array[Byte]
  mut pos : Int
  capacity : Int
}

///|
/// Create a new buffered writer from a memory sink.
pub fn new_buf_writer(
  sink : MemorySink,
  capacity : Int,
) -> BufWriter raise BufferError {
  validate_stream_capacity(capacity)
  let writer : BufWriter = { sink, buf: [], pos: 0, capacity }
  writer
}

///|
/// Write a single byte into the internal buffer.
pub fn BufWriter::write_byte(self : BufWriter, b : Byte) -> Unit {
  if self.buffered_len() == self.capacity {
    self.flush()
  }
  self.buf.push(b)
  self.pos = self.buf.length()
}

///|
/// Write all bytes, flushing or bypassing the buffer when appropriate.
pub fn BufWriter::write_all(self : BufWriter, src : Array[Byte]) -> Unit {
  if src.length() == 0 {
    return
  }

  if self.buffered_len() > 0 &&
    self.buffered_len() + src.length() > self.capacity {
    self.flush()
  }

  if self.buffered_len() == 0 && src.length() >= self.capacity {
    self.sink.write(src)
    return
  }

  self.buf.append(src[:])
  self.pos = self.buf.length()
}

///|
/// Flush the buffered bytes into the sink.
pub fn BufWriter::flush(self : BufWriter) -> Unit {
  if self.buffered_len() > 0 {
    self.sink.write(self.buf)
    self.buf.clear()
    self.pos = 0
  }
  self.sink.flush()
}

///|
/// Return the current number of buffered bytes.
pub fn BufWriter::buffered_len(self : BufWriter) -> Int {
  self.buf.length()
}

///|
/// Return the configured buffer capacity.
pub fn BufWriter::capacity(self : BufWriter) -> Int {
  self.capacity
}

///|
/// Flush buffered bytes and return the wrapped memory sink.
pub fn BufWriter::into_inner(self : BufWriter) -> MemorySink {
  self.flush()
  self.sink
}
