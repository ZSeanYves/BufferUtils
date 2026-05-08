///|
fn validate_file_sink_path(path : String) -> Unit raise BufferError {
  if path == "" {
    raise BufferError::InvalidInput("file path must not be empty")
  }
}

///|
fn validate_file_writer_capacity(capacity : Int) -> Unit raise BufferError {
  if capacity <= 0 {
    raise BufferError::InvalidCapacity(
      "buffer capacity must be greater than zero",
    )
  }
}

///|
fn append_bytes(dst : Array[Byte], src : Array[Byte]) -> Unit {
  if src.length() == 0 {
    return
  }
  let start = dst.length()
  dst.resize(start + src.length(), (0).to_byte())
  src[:].blit_to(dst, dst_offset=start)
}

///|
/// A file-backed sink that accumulates bytes in memory and writes on flush.
pub struct FileSink {
  path : String
  data : Array[Byte]
  mut flushed_len : Int
}

///|
/// A buffered writer that flushes to a `FileSink`.
pub struct FileBufWriter {
  sink : FileSink
  buf : Array[Byte]
  mut pos : Int
  capacity : Int
}

///|
/// Create a new file sink for the given output path.
pub fn new_file_sink(path : String) -> FileSink raise BufferError {
  validate_file_sink_path(path)
  let sink : FileSink = { path, data: [], flushed_len: 0 }
  sink
}

///|
/// Create a new buffered writer that writes to a file-backed sink.
pub fn new_file_buf_writer(
  path : String,
  capacity : Int,
) -> FileBufWriter raise BufferError {
  validate_file_sink_path(path)
  validate_file_writer_capacity(capacity)
  let writer : FileBufWriter = {
    sink: new_file_sink(path),
    buf: [],
    pos: 0,
    capacity,
  }
  writer
}

///|
/// Append bytes to the in-memory file sink buffer.
pub fn FileSink::write(self : FileSink, src : Array[Byte]) -> Unit {
  append_bytes(self.data, src)
}

///|
/// Flush the accumulated bytes to the target file path using overwrite semantics.
/// Flushing an empty sink creates or overwrites the target file as an empty file.
pub fn FileSink::flush(self : FileSink) -> Unit raise BufferError {
  try @fs.write_bytes_to_file(self.path, array_to_bytes(self.data)) catch {
    _ => raise BufferError::Flush("failed to write buffered bytes to file")
  } noraise {
    _ => ()
  }
  self.flushed_len = self.data.length()
}

///|
/// Return the number of bytes pending flush to disk.
pub fn FileSink::pending_len(self : FileSink) -> Int {
  let pending = self.data.length() - self.flushed_len
  if pending < 0 {
    0
  } else {
    pending
  }
}

///|
/// Clear all accumulated sink data.
pub fn FileSink::clear(self : FileSink) -> Unit {
  self.data.clear()
  self.flushed_len = 0
}

///|
/// Return the target output path.
pub fn FileSink::path(self : FileSink) -> String {
  self.path
}

///|
/// Return a snapshot of all accumulated sink bytes.
pub fn FileSink::to_bytes(self : FileSink) -> Array[Byte] {
  self.data.copy()
}

///|
/// Return the buffered byte count that still lives in the writer's local buffer.
pub fn FileBufWriter::buffered_len(self : FileBufWriter) -> Int {
  self.buf.length()
}

///|
/// Return the configured writer capacity.
pub fn FileBufWriter::capacity(self : FileBufWriter) -> Int {
  self.capacity
}

///|
/// Return the total number of bytes not yet persisted to disk.
pub fn FileBufWriter::pending_len(self : FileBufWriter) -> Int {
  self.buffered_len() + self.sink.pending_len()
}

///|
/// Return the target output path.
pub fn FileBufWriter::path(self : FileBufWriter) -> String {
  self.sink.path()
}

///|
/// Write a single byte into the file writer buffer.
pub fn FileBufWriter::write_byte(
  self : FileBufWriter,
  b : Byte,
) -> Unit raise BufferError {
  if self.buffered_len() == self.capacity {
    self.flush()
  }
  self.buf.push(b)
  self.pos = self.buf.length()
}

///|
/// Write all bytes while preserving order and buffered semantics.
pub fn FileBufWriter::write_all(
  self : FileBufWriter,
  src : Array[Byte],
) -> Unit raise BufferError {
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
/// Flush the local buffer into the sink and then persist the sink to disk.
pub fn FileBufWriter::flush(self : FileBufWriter) -> Unit raise BufferError {
  if self.buffered_len() > 0 {
    self.sink.write(self.buf)
    self.buf.clear()
    self.pos = 0
  }
  self.sink.flush()
}
