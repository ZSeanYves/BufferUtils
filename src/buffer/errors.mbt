///|
/// Errors raised by in-memory buffer operations.
pub suberror BufferError {
  InvalidRange(String)
  Underflow(Int, Int)
  CapacityOverflow(Int, Int)
  InvalidUtf8
} derive(Eq, @debug.Debug)
