///|
/// Split a `Bytes` value by a single-byte delimiter.
///
/// The delimiter is not included in the result.
/// Empty segments are preserved, including leading, trailing,
/// and repeated delimiters.
pub fn split_bytes(buf : Bytes, delimiter : Byte) -> Array[Array[Byte]] {
  let result : Array[Array[Byte]] = []
  let current : Array[Byte] = []

  for byte in buf {
    if byte == delimiter {
      result.push(current.copy())
      current.clear()
    } else {
      current.push(byte)
    }
  }

  result.push(current.copy())
  result
}

///|
/// Split an `Array[Byte]` by a single-byte delimiter.
pub fn split_array_bytes(
  arr : Array[Byte],
  delimiter : Byte,
) -> Array[Array[Byte]] {
  split_bytes(Bytes::from_array(arr), delimiter)
}
