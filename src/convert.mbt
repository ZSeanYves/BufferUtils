///|
/// Convert immutable `Bytes` into a copied `Array[Byte]`.
pub fn bytes_to_array(data : Bytes) -> Array[Byte] {
  data.to_array()
}

///|
/// Convert `Array[Byte]` into `Bytes`.
pub fn array_to_bytes(data : Array[Byte]) -> Bytes {
  Bytes::from_array(data)
}

///|
fn int_to_byte_checked(value : Int) -> Byte raise BufferError {
  if value < 0 || value > 255 {
    raise BufferError::InvalidInput(
      "integer value is outside byte range 0..255",
    )
  }
  value.to_byte()
}

///|
/// Convert `Array[Int]` into `Array[Byte]` with explicit range validation.
pub fn ints_to_bytes(data : Array[Int]) -> Array[Byte] raise BufferError {
  let result : Array[Byte] = []
  for value in data {
    result.push(int_to_byte_checked(value))
  }
  result
}

///|
/// Encode a string into UTF-8 bytes using MoonBit's standard library.
pub fn string_to_utf8_bytes(s : String) -> Bytes {
  @utf8.encode(s)
}

///|
/// Decode UTF-8 bytes into a string.
pub fn utf8_bytes_to_string(b : Bytes) -> String raise Utf8DecodeError {
  try @utf8.decode(b) catch {
    _ => raise Utf8DecodeError("invalid utf-8 byte sequence")
  } noraise {
    value => value
  }
}
