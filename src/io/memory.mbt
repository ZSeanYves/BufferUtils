///|
/// An in-memory `Read` implementation with optional short-read behavior.
priv enum MemoryReaderData {
  Core(Bytes)
  Shared(@buffer.SharedBytes)
}

///|
fn MemoryReaderData::len(self : MemoryReaderData) -> Int {
  match self {
    Core(data) => data.length()
    Shared(data) => data.len()
  }
}

///|
fn MemoryReaderData::copy_to(
  self : MemoryReaderData,
  destination : FixedArray[Byte],
  destination_offset : Int,
  source_offset : Int,
  length : Int,
) -> Unit {
  match self {
    Core(data) =>
      destination.blit_from_bytes(
        destination_offset, data, source_offset, length,
      )
    Shared(data) =>
      destination.blit_from_bytesview(
        destination_offset,
        data.as_bytes_view()[source_offset:source_offset + length],
      )
  }
}

///|
struct MemoryReader {
  data : MemoryReaderData
  mut position : Int
  max_chunk : Int
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
  { data: Core(data), position: 0, max_chunk }
}

///|
/// Create a reader over immutable shared storage without materializing it.
pub fn MemoryReader::from_shared(
  data : @buffer.SharedBytes,
  max_chunk? : Int = 2147483647,
) -> MemoryReader raise IoError {
  if max_chunk <= 0 {
    raise io_error(
      InvalidInput,
      "MemoryReader::from_shared",
      message="max_chunk must be positive",
    )
  }
  { data: Shared(data), position: 0, max_chunk }
}

///|
/// Return the number of bytes still available to the reader.
pub fn MemoryReader::remaining(self : MemoryReader) -> Int {
  self.data.len() - self.position
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
  let count = Int::min(Int::min(length, self.remaining()), self.max_chunk)
  self.data.copy_to(dst, offset, self.position, count)
  self.position += count
  count
}

///|
/// An in-memory `Write` implementation with optional short-write behavior.
struct MemoryWriter {
  data : @buffer.BytesMut
  max_chunk : Int
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
  { data, max_chunk }
}

///|
/// Return the bytes accepted by the writer as an owned value.
pub fn MemoryWriter::to_bytes(self : MemoryWriter) -> Bytes {
  self.to_shared_bytes().to_bytes()
}

///|
/// Return a shared snapshot of bytes accepted by the writer without
/// materializing them. Later writes detach through copy-on-write.
pub fn MemoryWriter::to_shared_bytes(
  self : MemoryWriter,
) -> @buffer.SharedBytes {
  self.data.freeze()
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
pub impl Write for MemoryWriter with fn flush(_self) {
  ()
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
