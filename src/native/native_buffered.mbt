///|
fn validate_native_stream_capacity(
  capacity : Int,
) -> Unit raise @bufferutils.BufferError {
  if capacity <= 0 {
    @bufferutils.raise_buffer_invalid_capacity(
      "buffer capacity must be greater than zero",
    )
  }
}

///|
fn append_native_view(dst : Array[Byte], src : ArrayView[Byte]) -> Unit {
  if src.length() == 0 {
    return
  }
  let start = dst.length()
  dst.resize(start + src.length(), (0).to_byte())
  src.blit_to(dst, dst_offset=start)
}

///|
fn ensure_native_buf_reader_open(
  reader : NativeBufReader,
) -> Unit raise @bufferutils.BufferError {
  if reader.closed {
    @bufferutils.raise_buffer_io("native buffered reader is closed")
  }
}

///|
fn ensure_native_buf_writer_open(
  writer : NativeBufWriter,
) -> Unit raise @bufferutils.BufferError {
  if writer.closed {
    @bufferutils.raise_buffer_io("native buffered writer is closed")
  }
}

///|
/// Experimental native buffered reader over `NativeFileSource`.
pub struct NativeBufReader {
  source : NativeFileSource
  buf : Array[Byte]
  mut pos : Int
  mut end : Int
  capacity : Int
  mut reached_eof : Bool
  mut closed : Bool
}

///|
/// Experimental native buffered writer over `NativeFileSink`.
pub struct NativeBufWriter {
  sink : NativeFileSink
  buf : Array[Byte]
  mut pos : Int
  capacity : Int
  mut closed : Bool
}

///|
/// Open a native buffered reader without snapshotting the whole file.
pub fn new_native_buf_reader(
  path : String,
  capacity : Int,
) -> NativeBufReader raise @bufferutils.BufferError {
  validate_native_stream_capacity(capacity)
  let source = new_native_file_source(path)
  let buf : Array[Byte] = Array::makei(capacity, fn(_i) { (0).to_byte() })
  { source, buf, pos: 0, end: 0, capacity, reached_eof: false, closed: false }
}

///|
/// Open a native buffered writer over `NativeFileSink`.
pub fn new_native_buf_writer(
  path : String,
  capacity : Int,
  mode : NativeFileMode,
) -> NativeBufWriter raise @bufferutils.BufferError {
  validate_native_stream_capacity(capacity)
  let sink = new_native_file_sink(path, mode)
  { sink, buf: [], pos: 0, capacity, closed: false }
}

///|
/// Fill the internal reader buffer when it has been fully consumed.
pub fn NativeBufReader::fill_buf(
  self : NativeBufReader,
) -> Int raise @bufferutils.BufferError {
  ensure_native_buf_reader_open(self)
  let buffered = self.buffered_len()
  if buffered > 0 {
    return buffered
  }
  if self.reached_eof {
    return 0
  }

  self.pos = 0
  self.end = 0
  let chunk = self.source.read_chunk(self.capacity)
  let count = chunk.length()
  if count > 0 {
    chunk[:].blit_to(self.buf)
  }
  self.end = count
  self.reached_eof = count == 0
  count
}

///|
/// Read a single byte from the native buffered reader.
pub fn NativeBufReader::read_byte(
  self : NativeBufReader,
) -> Byte raise @bufferutils.BufferError {
  ensure_native_buf_reader_open(self)
  if self.fill_buf() == 0 {
    @bufferutils.raise_buffer_underflow("not enough bytes remaining in buffer")
  }
  let byte = self.buf[self.pos]
  self.pos += 1
  byte
}

///|
/// Read exactly `n` bytes from the native buffered reader.
/// This is a streaming-style operation, so an eventual `Underflow` may occur
/// after partial consumption if EOF is reached mid-read.
pub fn NativeBufReader::read_exact(
  self : NativeBufReader,
  n : Int,
) -> Array[Byte] raise @bufferutils.BufferError {
  validate_native_chunk_size(n)
  ensure_native_buf_reader_open(self)
  let result : Array[Byte] = Array::new(capacity=n)
  while result.length() < n {
    if self.buffered_len() == 0 && self.fill_buf() == 0 {
      @bufferutils.raise_buffer_underflow(
        "not enough bytes remaining in buffer",
      )
    }

    let needed = n - result.length()
    let available = self.buffered_len()
    let count = if available < needed { available } else { needed }
    append_native_view(result, self.buf[self.pos:self.pos + count])
    self.pos += count
  }
  result
}

///|
/// Read all remaining bytes until EOF.
pub fn NativeBufReader::read_to_end(
  self : NativeBufReader,
) -> Array[Byte] raise @bufferutils.BufferError {
  ensure_native_buf_reader_open(self)
  let result : Array[Byte] = []
  result.reserve_capacity(self.buffered_len())
  while true {
    if self.buffered_len() == 0 && self.fill_buf() == 0 {
      break
    }
    let available = self.buffered_len()
    append_native_view(result, self.buf[self.pos:self.pos + available])
    self.pos += available
  }
  result
}

///|
/// Consume bytes that are already buffered.
pub fn NativeBufReader::consume(
  self : NativeBufReader,
  n : Int,
) -> Unit raise @bufferutils.BufferError {
  validate_native_chunk_size(n)
  ensure_native_buf_reader_open(self)
  if n > self.buffered_len() {
    @bufferutils.raise_buffer_underflow("not enough bytes remaining in buffer")
  }
  self.pos += n
}

///|
pub fn NativeBufReader::buffered_len(self : NativeBufReader) -> Int {
  let available = self.end - self.pos
  if available < 0 {
    0
  } else {
    available
  }
}

///|
pub fn NativeBufReader::capacity(self : NativeBufReader) -> Int {
  self.capacity
}

///|
pub fn NativeBufReader::is_eof(self : NativeBufReader) -> Bool {
  self.buffered_len() == 0 && self.reached_eof
}

///|
pub fn NativeBufReader::close(
  self : NativeBufReader,
) -> Unit raise @bufferutils.BufferError {
  if self.closed {
    return
  }
  self.closed = true
  self.pos = 0
  self.end = 0
  self.reached_eof = true
  self.source.close()
}

///|
pub fn NativeBufReader::is_closed(self : NativeBufReader) -> Bool {
  self.closed
}

///|
fn flush_native_buf_writer_inner(
  writer : NativeBufWriter,
) -> Unit raise @bufferutils.BufferError {
  if writer.buffered_len() > 0 {
    writer.sink.write_all(writer.buf)
    writer.buf.clear()
    writer.pos = 0
  }
  writer.sink.flush()
}

///|
pub fn NativeBufWriter::write_byte(
  self : NativeBufWriter,
  b : Byte,
) -> Unit raise @bufferutils.BufferError {
  ensure_native_buf_writer_open(self)
  if self.buffered_len() == self.capacity {
    flush_native_buf_writer_inner(self)
  }
  self.buf.push(b)
  self.pos = self.buf.length()
}

///|
pub fn NativeBufWriter::write_all(
  self : NativeBufWriter,
  data : Array[Byte],
) -> Unit raise @bufferutils.BufferError {
  ensure_native_buf_writer_open(self)
  if data.length() == 0 {
    return
  }

  if self.buffered_len() > 0 &&
    self.buffered_len() + data.length() > self.capacity {
    flush_native_buf_writer_inner(self)
  }

  if self.buffered_len() == 0 && data.length() >= self.capacity {
    self.sink.write_all(data)
    return
  }

  self.buf.append(data[:])
  self.pos = self.buf.length()
}

///|
pub fn NativeBufWriter::flush(
  self : NativeBufWriter,
) -> Unit raise @bufferutils.BufferError {
  ensure_native_buf_writer_open(self)
  flush_native_buf_writer_inner(self)
}

///|
pub fn NativeBufWriter::buffered_len(self : NativeBufWriter) -> Int {
  self.buf.length()
}

///|
pub fn NativeBufWriter::capacity(self : NativeBufWriter) -> Int {
  self.capacity
}

///|
pub fn NativeBufWriter::close(
  self : NativeBufWriter,
) -> Unit raise @bufferutils.BufferError {
  if self.closed {
    return
  }
  flush_native_buf_writer_inner(self)
  self.closed = true
  self.sink.close()
}

///|
pub fn NativeBufWriter::is_closed(self : NativeBufWriter) -> Bool {
  self.closed
}
