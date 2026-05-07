///|
/// Growth mode for `BufferWriter`.
enum GrowthPolicy {
  Fixed
  AutoGrow
}

///|
/// The `BufferWriter` struct
/// A utility for writing bytes into a dynamically tracked buffer.
pub struct BufferWriter {
  /// Internal byte buffer
  /// Current write position (offset)
  /// Maximum buffer capacity
  buf : Array[Byte]
  mut pos : Int
  mut capacity : Int
  growth : GrowthPolicy
}

///|
fn validate_writer_capacity(capacity : Int) -> Unit raise BufferError {
  if capacity <= 0 {
    raise BufferError::InvalidCapacity(
      "buffer capacity must be greater than zero",
    )
  }
}

///|
/// Create a fixed-capacity writer.
pub fn new_fixed_writer(capacity : Int) -> BufferWriter raise BufferError {
  validate_writer_capacity(capacity)
  let writer : BufferWriter = { buf: [], pos: 0, capacity, growth: Fixed }
  writer
}

///|
/// Create an automatically growing writer.
pub fn new_growing_writer(
  initial_capacity : Int,
) -> BufferWriter raise BufferError {
  validate_writer_capacity(initial_capacity)
  let writer : BufferWriter = {
    buf: [],
    pos: 0,
    capacity: initial_capacity,
    growth: AutoGrow,
  }
  writer
}

///|
/// Compatibility constructor that keeps the v0.3.0 fixed-capacity behavior.
pub fn new_writer(capacity : Int) -> BufferWriter raise BufferError {
  new_fixed_writer(capacity)
}

///|
fn next_capacity(current : Int, required : Int) -> Int {
  let base = if current > 0 { current } else { 1 }
  let doubled = base * 2
  if doubled >= required {
    doubled
  } else {
    required
  }
}

///|
fn BufferWriter::grow_to(self : BufferWriter, required : Int) -> Unit {
  if required > self.capacity {
    self.capacity = next_capacity(self.capacity, required)
  }
}

///|
/// Ensure the writer can accept at least `additional` more bytes.
pub fn BufferWriter::reserve(
  self : BufferWriter,
  additional : Int,
) -> Unit raise BufferError {
  if additional < 0 {
    raise BufferError::InvalidInput("requested byte count must be non-negative")
  }
  let required = self.len() + additional
  match self.growth {
    Fixed =>
      if required > self.capacity {
        raise BufferError::Overflow("write would exceed buffer capacity")
      }
    AutoGrow => self.grow_to(required)
  }
}

///|
/// Ensure the writer has at least `required_capacity` total capacity.
pub fn BufferWriter::ensure_capacity(
  self : BufferWriter,
  required_capacity : Int,
) -> Unit raise BufferError {
  if required_capacity < 0 {
    raise BufferError::InvalidInput("required capacity must be non-negative")
  }
  match self.growth {
    Fixed =>
      if required_capacity > self.capacity {
        raise BufferError::Overflow("write would exceed buffer capacity")
      }
    AutoGrow => self.grow_to(required_capacity)
  }
}

///|
/// Write a single byte into the buffer.
/// Raises `BufferError::Overflow` if the buffer is full.
pub fn BufferWriter::write_byte(
  self : BufferWriter,
  b : Byte,
) -> Unit raise BufferError {
  self.reserve(1)
  self.buf.push(b)
  self.pos = self.buf.length()
}

///|
/// Write multiple bytes to the buffer in batch.
/// Raises `BufferError::Overflow` if total size exceeds capacity.
pub fn BufferWriter::write_all(
  self : BufferWriter,
  data : Array[Byte],
) -> Unit raise BufferError {
  self.reserve(data.length())
  for byte in data {
    self.buf.push(byte)
  }
  self.pos = self.buf.length()
}

///|
/// Return a copy of the currently buffered bytes.
/// This does not clear the internal buffer.
pub fn BufferWriter::flush_to_bytes(self : BufferWriter) -> Array[Byte] {
  self.buf.copy()
}

///|
/// Return the number of bytes currently stored in the writer.
pub fn BufferWriter::len(self : BufferWriter) -> Int {
  self.buf.length()
}

///|
/// Return the configured writer capacity.
pub fn BufferWriter::capacity(self : BufferWriter) -> Int {
  self.capacity
}

///|
/// Return the number of bytes that can still be written.
pub fn BufferWriter::remaining_capacity(self : BufferWriter) -> Int {
  let remaining = self.capacity - self.len()
  if remaining < 0 {
    0
  } else {
    remaining
  }
}

///|
/// Return whether the writer is currently empty.
pub fn BufferWriter::is_empty(self : BufferWriter) -> Bool {
  self.len() == 0
}

///|
/// Clear the internal buffer and reset the write position.
pub fn BufferWriter::clear(self : BufferWriter) -> Unit {
  self.buf.clear()
  self.pos = 0
}
