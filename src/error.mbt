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
/// UTF-8 decoding error wrapper used by BufferUtils conversion helpers.
pub suberror Utf8DecodeError {
  Utf8DecodeError(String)
}
