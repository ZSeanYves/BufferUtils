///|
/// An in-memory `Read` implementation with optional short-read behavior.
struct MemoryReader {
  data : Bytes
  mut position : Int
  max_chunk : Int
  mut read_calls : Int
}

///|
/// Create a reader over immutable bytes.
pub fn MemoryReader::new(
  data : Bytes,
  max_chunk? : Int = 2147483647,
) -> MemoryReader raise IoError {
  if max_chunk <= 0 {
    raise io_error(
      InvalidInput,
      "MemoryReader::new",
      message="max_chunk must be positive",
    )
  }
  { data, position: 0, max_chunk, read_calls: 0 }
}

///|
/// Return the number of bytes still available to the reader.
pub fn MemoryReader::remaining(self : MemoryReader) -> Int {
  self.data.length() - self.position
}

///|
/// Return the number of calls made to the underlying memory reader.
///
/// This is a diagnostic counter for tests and benchmarks, not correctness
/// state.
pub fn MemoryReader::read_calls(self : MemoryReader) -> Int {
  self.read_calls
}

///|
pub impl Read for MemoryReader with fn read(self, dst, offset, length) {
  if offset < 0 || length < 0 || offset > dst.length() - length {
    raise io_error(
      InvalidInput,
      "MemoryReader::read",
      message="destination range is invalid",
    )
  }
  self.read_calls += 1
  let count = Int::min(Int::min(length, self.remaining()), self.max_chunk)
  dst.blit_from_bytes(offset, self.data, self.position, count)
  self.position += count
  count
}

///|
/// An in-memory `Write` implementation with optional short-write behavior.
struct MemoryWriter {
  data : @buffer.BytesMut
  max_chunk : Int
  mut write_calls : Int
  mut flush_calls : Int
}

///|
/// Create an empty memory writer.
pub fn MemoryWriter::new(
  max_chunk? : Int = 2147483647,
) -> MemoryWriter raise IoError {
  if max_chunk <= 0 {
    raise io_error(
      InvalidInput,
      "MemoryWriter::new",
      message="max_chunk must be positive",
    )
  }
  let data = @buffer.BytesMut::new() catch {
    _ => abort("zero-capacity MemoryWriter construction failed")
  }
  { data, max_chunk, write_calls: 0, flush_calls: 0 }
}

///|
/// Return the bytes accepted by the writer as an owned value.
pub fn MemoryWriter::to_bytes(self : MemoryWriter) -> Bytes {
  self.data.freeze().to_bytes()
}

///|
/// Return the number of write calls observed by the memory writer.
pub fn MemoryWriter::write_calls(self : MemoryWriter) -> Int {
  self.write_calls
}

///|
/// Return the number of flush calls observed by the memory writer.
pub fn MemoryWriter::flush_calls(self : MemoryWriter) -> Int {
  self.flush_calls
}

///|
pub impl Write for MemoryWriter with fn write(self, src, offset, length) {
  if offset < 0 || length < 0 || offset > src.length() - length {
    raise io_error(
      InvalidInput,
      "MemoryWriter::write",
      message="source range is invalid",
    )
  }
  self.write_calls += 1
  let count = Int::min(length, self.max_chunk)
  self.data.put_bytes_view(src[offset:offset + count]) catch {
    error =>
      raise io_error(
        Backend,
        "MemoryWriter::write",
        message=@debug.render(Repr(error)),
      )
  }
  count
}

///|
pub impl Write for MemoryWriter with fn flush(self) {
  self.flush_calls += 1
}

///|
/// Internal state backing an in-memory byte pipe.
priv struct MemoryPipeState {
  data : Array[Byte]
  mut position : Int
  mut writer_closed : Bool
  mut reader_closed : Bool
}

///|
/// Opaque readable endpoint of an in-memory byte pipe.
struct MemoryPipeReader {
  state : MemoryPipeState
}

///|
/// Opaque writable endpoint of an in-memory byte pipe.
struct MemoryPipeWriter {
  state : MemoryPipeState
}

///|
/// Namespace used to construct connected in-memory pipe endpoints.
struct MemoryPipe {}

///|
/// Create connected in-memory reader and writer endpoints.
pub fn MemoryPipe::new() -> (MemoryPipeReader, MemoryPipeWriter) {
  let _marker : MemoryPipe = MemoryPipe::{  }
  let state : MemoryPipeState = {
    data: [],
    position: 0,
    writer_closed: false,
    reader_closed: false,
  }
  (MemoryPipeReader::{ state, }, MemoryPipeWriter::{ state, })
}

///|
pub impl Read for MemoryPipeReader with fn read(
  self,
  destination,
  offset,
  length,
) {
  if offset < 0 || length < 0 || offset > destination.length() - length {
    raise io_error(
      InvalidInput,
      "MemoryPipeReader::read",
      message="destination range is invalid",
    )
  }
  let available = self.state.data.length() - self.state.position
  if available == 0 {
    return 0
  }
  let count = Int::min(length, available)
  for i in 0..<count {
    destination[offset + i] = self.state.data[self.state.position + i]
  }
  self.state.position += count
  count
}

///|
pub impl BufRead for MemoryPipeReader with fn fill_buf(self) {
  self.state.data[self.state.position:]
}

///|
pub impl BufRead for MemoryPipeReader with fn consume(self, count) {
  if count < 0 || count > self.state.data.length() - self.state.position {
    raise io_error(InvalidInput, "MemoryPipeReader::consume")
  }
  self.state.position += count
}

///|
pub impl Write for MemoryPipeWriter with fn write(self, source, offset, length) {
  if self.state.reader_closed {
    raise io_error(BrokenPipe, "MemoryPipeWriter::write")
  }
  if offset < 0 || length < 0 || offset > source.length() - length {
    raise io_error(
      InvalidInput,
      "MemoryPipeWriter::write",
      message="source range is invalid",
    )
  }
  for i in 0..<length {
    self.state.data.push(source[offset + i])
  }
  length
}

///|
pub impl Write for MemoryPipeWriter with fn flush(_self) {
  ()
}

///|
pub impl Close for MemoryPipeReader with fn close(self) {
  self.state.reader_closed = true
}

///|
pub impl Close for MemoryPipeReader with fn is_closed(self) {
  self.state.reader_closed
}

///|
pub impl Close for MemoryPipeWriter with fn close(self) {
  self.state.writer_closed = true
}

///|
pub impl Close for MemoryPipeWriter with fn is_closed(self) {
  self.state.writer_closed
}
