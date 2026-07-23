///|
pub fn shared_buffer_example() -> @buffer.SharedBytes raise @buffer.BufferError {
  let mutable = @buffer.BytesMut::new(capacity=32)
  mutable.put_u32_be(0xBADC0FFEU)
  mutable.put_utf8("payload")
  let shared = mutable.freeze()
  let prefix = shared.slice(0, 4)
  ignore(prefix.as_bytes_view())
  shared
}
