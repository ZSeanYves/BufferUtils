/// Unified buffer error type for read/write operations
type! BufferError {
  /// Buffer write failed: attempt to write beyond the maximum capacity
  Overflow(String)

  /// Buffer read failed: position has reached the end or buffer is empty
  Underflow(String)

  /// Initialization failed: specified buffer capacity is invalid or negative
  InvalidCapacity(String)

  /// Flush failed: error occurred while trying to output buffered data
  Flush(String)
}
