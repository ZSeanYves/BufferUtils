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
pub fn MemoryReader::remaining(self : MemoryReader) -> Int {
  self.data.length() - self.position
}

///|
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
  for i in 0..<count {
    dst[offset + i] = self.data[self.position + i]
  }
  self.position += count
  count
}

///|
/// An in-memory `Write` implementation with optional short-write behavior.
struct MemoryWriter {
  data : Array[Byte]
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
  { data: [], max_chunk, write_calls: 0, flush_calls: 0 }
}

///|
pub fn MemoryWriter::to_bytes(self : MemoryWriter) -> Bytes {
  Bytes::from_array(self.data[:])
}

///|
pub fn MemoryWriter::write_calls(self : MemoryWriter) -> Int {
  self.write_calls
}

///|
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
  for i in 0..<count {
    self.data.push(src[offset + i])
  }
  count
}

///|
pub impl Write for MemoryWriter with fn flush(self) {
  self.flush_calls += 1
}

///|
/// Shared state backing an in-memory byte pipe.
pub struct MemoryPipeState {
  data : Array[Byte]
  mut position : Int
  mut writer_closed : Bool
  mut reader_closed : Bool
}

///|
pub struct MemoryPipeReader {
  state : MemoryPipeState
}

///|
pub struct MemoryPipeWriter {
  state : MemoryPipeState
}

///|
pub struct MemoryPipe {}

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
