///|
/// A mutable read position over immutable shared bytes.
///
/// Cursors created from the same `SharedBytes` advance independently and never
/// modify the shared value or its backing allocation.
pub struct BytesCursor {
  bytes : SharedBytes
  mut position : Int
}

///|
/// Create a cursor positioned at the start of `bytes`.
pub fn BytesCursor::new(bytes : SharedBytes) -> BytesCursor {
  { bytes, position: 0 }
}

///|
/// Return the number of bytes consumed by this cursor.
pub fn BytesCursor::position(self : BytesCursor) -> Int {
  self.position
}

///|
/// Return the number of unread bytes.
#inline
pub fn BytesCursor::remaining(self : BytesCursor) -> Int {
  self.bytes.len() - self.position
}

///|
/// Test whether the cursor has reached the end.
pub fn BytesCursor::is_empty(self : BytesCursor) -> Bool {
  self.remaining() == 0
}

///|
/// Return the unread range without advancing the cursor.
#inline
pub fn BytesCursor::remaining_bytes(self : BytesCursor) -> SharedBytes {
  {
    storage: self.bytes.storage,
    start: self.bytes.start + self.position,
    end: self.bytes.end,
  }
}

///|
/// Consume the cursor and return its unread range.
pub fn BytesCursor::into_remaining(self : BytesCursor) -> SharedBytes {
  self.remaining_bytes()
}

///|
/// Advance by `count` bytes.
pub fn BytesCursor::advance(
  self : BytesCursor,
  count : Int,
) -> Unit raise BufferError {
  let remaining = self.remaining()
  if count < 0 || count > remaining {
    raise BufferError::Underflow(count, remaining)
  }
  self.position += count
}

///|
/// Return the next `count` bytes and advance the cursor.
pub fn BytesCursor::split_to(
  self : BytesCursor,
  count : Int,
) -> SharedBytes raise BufferError {
  let remaining = self.remaining()
  if count < 0 || count > remaining {
    raise BufferError::Underflow(count, remaining)
  }
  let start = self.bytes.start + self.position
  self.position += count
  { storage: self.bytes.storage, start, end: start + count }
}

///|
/// Copy unread bytes into an array view and advance by the copied count.
pub fn BytesCursor::copy_to(
  self : BytesCursor,
  dst : MutArrayView[Byte],
) -> Int {
  let count = Int::min(self.remaining(), dst.length())
  let source = self.remaining_bytes().view()
  for i in 0..<count {
    dst[i] = source[i]
  }
  self.position += count
  count
}

///|
/// Copy unread bytes into a fixed-array range with one bulk operation.
pub fn BytesCursor::copy_to_fixed(
  self : BytesCursor,
  destination : FixedArray[Byte],
  offset : Int,
  length : Int,
) -> Int raise BufferError {
  if offset < 0 || length < 0 || offset > destination.length() - length {
    raise BufferError::InvalidRange("fixed-array destination range is invalid")
  }
  let count = Int::min(self.remaining(), length)
  FixedArray::unsafe_blit(
    destination,
    offset,
    self.bytes.storage.data,
    self.bytes.start + self.position,
    count,
  )
  self.position += count
  count
}

///|
/// Read one unsigned byte and advance the cursor.
pub fn BytesCursor::get_u8(self : BytesCursor) -> Byte raise BufferError {
  if self.is_empty() {
    raise BufferError::Underflow(1, 0)
  }
  let result = self.bytes.storage.data[self.bytes.start + self.position]
  self.position += 1
  result
}

///|
/// Read one signed byte and advance the cursor.
pub fn BytesCursor::get_i8(self : BytesCursor) -> Int raise BufferError {
  let value = self.get_u8().to_int()
  if value < 128 {
    value
  } else {
    value - 256
  }
}

///|
fn BytesCursor::take_bytes_view(
  self : BytesCursor,
  width : Int,
) -> BytesView raise BufferError {
  let remaining = self.remaining()
  if width < 0 || width > remaining {
    raise BufferError::Underflow(width, remaining)
  }
  let start = self.bytes.start + self.position
  self.position += width
  self.bytes.storage.data.unsafe_reinterpret_as_bytes()[start:start + width]
}

///|
pub fn BytesCursor::get_u16_be(self : BytesCursor) -> UInt16 raise BufferError {
  self.take_bytes_view(2).unsafe_read_uint16_be(0)
}

///|
pub fn BytesCursor::get_u16_le(self : BytesCursor) -> UInt16 raise BufferError {
  self.take_bytes_view(2).unsafe_read_uint16_le(0)
}

///|
pub fn BytesCursor::get_u32_be(self : BytesCursor) -> UInt raise BufferError {
  self.take_bytes_view(4).unsafe_read_uint32_be(0)
}

///|
pub fn BytesCursor::get_u32_le(self : BytesCursor) -> UInt raise BufferError {
  self.take_bytes_view(4).unsafe_read_uint32_le(0)
}

///|
pub fn BytesCursor::get_u64_be(self : BytesCursor) -> UInt64 raise BufferError {
  self.take_bytes_view(8).unsafe_read_uint64_be(0)
}

///|
pub fn BytesCursor::get_u64_le(self : BytesCursor) -> UInt64 raise BufferError {
  self.take_bytes_view(8).unsafe_read_uint64_le(0)
}

///|
pub fn BytesCursor::get_i16_be(self : BytesCursor) -> Int16 raise BufferError {
  Int16::reinterpret_from_uint16(self.get_u16_be())
}

///|
pub fn BytesCursor::get_i16_le(self : BytesCursor) -> Int16 raise BufferError {
  Int16::reinterpret_from_uint16(self.get_u16_le())
}

///|
pub fn BytesCursor::get_i32_be(self : BytesCursor) -> Int raise BufferError {
  self.get_u32_be().reinterpret_as_int()
}

///|
pub fn BytesCursor::get_i32_le(self : BytesCursor) -> Int raise BufferError {
  self.get_u32_le().reinterpret_as_int()
}

///|
pub fn BytesCursor::get_i64_be(self : BytesCursor) -> Int64 raise BufferError {
  self.get_u64_be().reinterpret_as_int64()
}

///|
pub fn BytesCursor::get_i64_le(self : BytesCursor) -> Int64 raise BufferError {
  self.get_u64_le().reinterpret_as_int64()
}

///|
pub fn BytesCursor::get_f32_be(self : BytesCursor) -> Float raise BufferError {
  Float::reinterpret_from_uint(self.get_u32_be())
}

///|
pub fn BytesCursor::get_f32_le(self : BytesCursor) -> Float raise BufferError {
  Float::reinterpret_from_uint(self.get_u32_le())
}

///|
pub fn BytesCursor::get_f64_be(self : BytesCursor) -> Double raise BufferError {
  self.get_u64_be().reinterpret_as_double()
}

///|
pub fn BytesCursor::get_f64_le(self : BytesCursor) -> Double raise BufferError {
  self.get_u64_le().reinterpret_as_double()
}

///|
/// Decode the next `count` bytes as UTF-8 and advance on success.
pub fn BytesCursor::get_utf8(
  self : BytesCursor,
  count : Int,
) -> String raise BufferError {
  let remaining = self.remaining()
  if count < 0 || count > remaining {
    raise BufferError::Underflow(count, remaining)
  }
  let bytes = self.remaining_bytes().as_bytes_view()[0:count]
  let decoded = @utf8.decode(bytes) catch {
    _ => raise BufferError::InvalidUtf8
  }
  self.position += count
  decoded
}
