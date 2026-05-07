///|
/// A memory-backed sink that stores all written bytes.
pub struct MemorySink {
  data : Array[Byte]
}

///|
/// Create an empty memory sink.
pub fn new_memory_sink() -> MemorySink {
  let sink : MemorySink = { data: [] }
  sink
}

///|
/// Append all bytes into the sink.
pub fn MemorySink::write(self : MemorySink, src : Array[Byte]) -> Unit {
  for byte in src {
    self.data.push(byte)
  }
}

///|
/// Flush the sink. Memory-backed sinks do not need explicit flushing.
pub fn MemorySink::flush(self : MemorySink) -> Unit {
  ignore(self)
}

///|
/// Return a snapshot of the sink contents.
pub fn MemorySink::to_bytes(self : MemorySink) -> Array[Byte] {
  self.data.copy()
}

///|
/// Return the number of bytes stored in the sink.
pub fn MemorySink::len(self : MemorySink) -> Int {
  self.data.length()
}

///|
/// Return whether the sink is empty.
pub fn MemorySink::is_empty(self : MemorySink) -> Bool {
  self.len() == 0
}

///|
/// Clear all stored bytes from the sink.
pub fn MemorySink::clear(self : MemorySink) -> Unit {
  self.data.clear()
}
