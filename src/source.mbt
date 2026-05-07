///|
/// A memory-backed source of bytes.
pub struct MemorySource {
  data : Bytes
  mut pos : Int
}

///|
/// Create a memory source from `Bytes`.
pub fn new_memory_source(data : Bytes) -> MemorySource {
  let source : MemorySource = { data, pos: 0 }
  source
}

///|
/// Create a memory source from `Array[Byte]`.
pub fn new_memory_source_from_array(data : Array[Byte]) -> MemorySource {
  new_memory_source(array_to_bytes(data))
}

///|
/// Read up to `dst.length()` bytes from the current position.
pub fn MemorySource::read(self : MemorySource, dst : Array[Byte]) -> Int {
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
/// Read all remaining bytes and advance the source to EOF.
pub fn MemorySource::read_to_end(self : MemorySource) -> Array[Byte] {
  let remaining = self.remaining()
  let result : Array[Byte] = []
  for _ in 0..<remaining {
    result.push(self.data[self.pos])
    self.pos += 1
  }
  result
}

///|
/// Return the current source position.
pub fn MemorySource::position(self : MemorySource) -> Int {
  self.pos
}

///|
/// Return the total length of the source.
pub fn MemorySource::len(self : MemorySource) -> Int {
  self.data.length()
}

///|
/// Return the remaining number of unread bytes.
pub fn MemorySource::remaining(self : MemorySource) -> Int {
  if self.pos >= self.data.length() {
    0
  } else {
    self.data.length() - self.pos
  }
}

///|
/// Return whether the source is empty or fully consumed.
pub fn MemorySource::is_empty(self : MemorySource) -> Bool {
  self.remaining() == 0
}

///|
/// Reset the source position to the beginning.
pub fn MemorySource::rewind(self : MemorySource) -> Unit {
  self.pos = 0
}
