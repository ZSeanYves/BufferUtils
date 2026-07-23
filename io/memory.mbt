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
pub impl Read for MemoryReader with fn read(self, dst) {
  self.read_calls += 1
  let count = Int::min(Int::min(dst.length(), self.remaining()), self.max_chunk)
  for i in 0..<count {
    dst[i] = self.data[self.position + i]
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
pub impl Write for MemoryWriter with fn write(self, src) {
  self.write_calls += 1
  let count = Int::min(src.length(), self.max_chunk)
  append_bytes(self.data, src[0:count])
  count
}

///|
pub impl Write for MemoryWriter with fn flush(self) {
  self.flush_calls += 1
}
