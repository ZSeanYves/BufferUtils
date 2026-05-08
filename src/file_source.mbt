///|
fn validate_file_source_path(path : String) -> Unit raise BufferError {
  if path == "" {
    raise BufferError::InvalidInput("file path must not be empty")
  }
}

///|
/// A memory-backed snapshot of a file's bytes.
pub struct FileSource {
  path : String
  data : Bytes
  mut pos : Int
}

///|
/// Create a new file source by reading the file into memory.
pub fn new_file_source(path : String) -> FileSource raise BufferError {
  validate_file_source_path(path)
  let data = try @fs.read_file_to_bytes(path) catch {
    _ => raise BufferError::Io("failed to read bytes from file source")
  } noraise {
    value => value
  }
  let source : FileSource = { path, data, pos: 0 }
  source
}

///|
/// Read up to `dst.length()` bytes from the current position.
pub fn FileSource::read(self : FileSource, dst : Array[Byte]) -> Int {
  let available = self.remaining()
  if available == 0 || dst.length() == 0 {
    return 0
  }

  let count = if available < dst.length() { available } else { dst.length() }
  for i in 0..<count {
    dst[i] = self.data[self.pos + i]
  }
  self.pos += count
  count
}

///|
/// Read all remaining bytes and advance to EOF.
pub fn FileSource::read_to_end(self : FileSource) -> Array[Byte] {
  let remaining = self.remaining()
  let start = self.pos
  let result = self.data[start:start + remaining].to_array()
  self.pos += remaining
  result
}

///|
/// Experimental: return the remaining unread bytes from the in-memory snapshot
/// as a read-only `BytesView` without advancing the position.
pub fn FileSource::peek_remaining(self : FileSource) -> BytesView {
  let remaining = self.remaining()
  let start = self.pos
  self.data[start:start + remaining]
}

///|
/// Return the number of remaining unread bytes.
pub fn FileSource::remaining(self : FileSource) -> Int {
  if self.pos >= self.data.length() {
    0
  } else {
    self.data.length() - self.pos
  }
}

///|
/// Return the current read position.
pub fn FileSource::position(self : FileSource) -> Int {
  self.pos
}

///|
/// Reset the source position to the beginning of the in-memory snapshot.
pub fn FileSource::rewind(self : FileSource) -> Unit {
  self.pos = 0
}

///|
/// Return the total byte length of the source snapshot.
pub fn FileSource::len(self : FileSource) -> Int {
  self.data.length()
}

///|
/// Return whether the source snapshot is empty or fully consumed.
pub fn FileSource::is_empty(self : FileSource) -> Bool {
  self.remaining() == 0
}

///|
/// Return the original file path used to create the source snapshot.
pub fn FileSource::path(self : FileSource) -> String {
  self.path
}

///|
/// Convert a file source snapshot into a `MemorySource`.
fn file_source_to_memory(source : FileSource) -> MemorySource {
  let memory = new_memory_source(source.data)
  source.rewind()
  memory
}
