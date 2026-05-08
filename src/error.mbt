///|
/// Unified buffer error type for read/write operations
suberror BufferError {
  /// Buffer write failed: attempt to write beyond the maximum capacity
  Overflow(String)
  /// Buffer read failed: position has reached the end or buffer is empty
  Underflow(String)
  /// Initialization failed: specified buffer capacity is invalid or negative
  InvalidCapacity(String)
  /// Input value failed validation before the operation could proceed
  InvalidInput(String)
  /// File or runtime I/O failed while reading or writing external data
  Io(String)
  /// Flush failed: error occurred while trying to output buffered data
  Flush(String)
}

///|
/// Internal bridge for subpackages that need to raise `BufferError::InvalidInput`
/// without widening the stable API docs.
#doc(hidden)
pub fn raise_buffer_invalid_input(message : String) -> Unit raise BufferError {
  raise BufferError::InvalidInput(message)
}

///|
/// Internal bridge for subpackages that need to raise `BufferError::InvalidCapacity`.
#doc(hidden)
pub fn raise_buffer_invalid_capacity(
  message : String,
) -> Unit raise BufferError {
  raise BufferError::InvalidCapacity(message)
}

///|
/// Internal bridge for subpackages that need to raise `BufferError::Underflow`.
#doc(hidden)
pub fn raise_buffer_underflow(message : String) -> Unit raise BufferError {
  raise BufferError::Underflow(message)
}

///|
/// Internal bridge for subpackages that need to raise `BufferError::Io`.
#doc(hidden)
pub fn raise_buffer_io(message : String) -> Unit raise BufferError {
  raise BufferError::Io(message)
}

///|
/// Internal bridge for subpackages that need to raise `BufferError::Flush`.
#doc(hidden)
pub fn raise_buffer_flush(message : String) -> Unit raise BufferError {
  raise BufferError::Flush(message)
}

///|
/// UTF-8 decoding error wrapper used by BufferUtils conversion helpers.
pub suberror Utf8DecodeError {
  Utf8DecodeError(String)
}
