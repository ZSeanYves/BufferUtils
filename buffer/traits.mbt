///|
/// In-memory cursor operations over immutable byte values.
pub(open) trait Buf {
  fn remaining(Self) -> Int
  fn chunk(Self) -> SharedBytes
  fn advance(Self, Int) -> Unit raise BufferError
  fn copy_to(Self, MutArrayView[Byte]) -> Int
  fn get_u8(Self) -> Byte raise BufferError = _
  fn get_i8(Self) -> Int raise BufferError = _
  fn get_u16_be(Self) -> UInt16 raise BufferError = _
  fn get_u16_le(Self) -> UInt16 raise BufferError = _
  fn get_i16_be(Self) -> Int16 raise BufferError = _
  fn get_i16_le(Self) -> Int16 raise BufferError = _
  fn get_u32_be(Self) -> UInt raise BufferError = _
  fn get_u32_le(Self) -> UInt raise BufferError = _
  fn get_i32_be(Self) -> Int raise BufferError = _
  fn get_i32_le(Self) -> Int raise BufferError = _
  fn get_f32_be(Self) -> Float raise BufferError = _
  fn get_f32_le(Self) -> Float raise BufferError = _
  fn get_u64_be(Self) -> UInt64 raise BufferError = _
  fn get_u64_le(Self) -> UInt64 raise BufferError = _
  fn get_i64_be(Self) -> Int64 raise BufferError = _
  fn get_i64_le(Self) -> Int64 raise BufferError = _
  fn get_f64_be(Self) -> Double raise BufferError = _
  fn get_f64_le(Self) -> Double raise BufferError = _
}

///|
impl Buf with fn get_u8(self) {
  let chunk = Buf::chunk(self)
  if chunk.is_empty() {
    raise BufferError::Underflow(1, Buf::remaining(self))
  }
  let byte = chunk.view()[0]
  Buf::advance(self, 1)
  byte
}

///|
impl Buf with fn get_i8(self) {
  let value = Buf::get_u8(self).to_int()
  if value < 128 {
    value
  } else {
    value - 256
  }
}

///|
impl Buf with fn get_u16_be(self) {
  if Buf::remaining(self) < 2 {
    raise BufferError::Underflow(2, Buf::remaining(self))
  }
  ((Buf::get_u8(self).to_int() << 8) | Buf::get_u8(self).to_int()).to_uint16()
}

///|
impl Buf with fn get_u16_le(self) {
  if Buf::remaining(self) < 2 {
    raise BufferError::Underflow(2, Buf::remaining(self))
  }
  (Buf::get_u8(self).to_int() | (Buf::get_u8(self).to_int() << 8)).to_uint16()
}

///|
impl Buf with fn get_i16_be(self) {
  Int16::reinterpret_from_uint16(Buf::get_u16_be(self))
}

///|
impl Buf with fn get_i16_le(self) {
  Int16::reinterpret_from_uint16(Buf::get_u16_le(self))
}

///|
impl Buf with fn get_u32_be(self) {
  if Buf::remaining(self) < 4 {
    raise BufferError::Underflow(4, Buf::remaining(self))
  }
  let mut value = 0U
  for _ in 0..<4 {
    value = (value << 8) | Buf::get_u8(self).to_uint()
  }
  value
}

///|
impl Buf with fn get_u32_le(self) {
  if Buf::remaining(self) < 4 {
    raise BufferError::Underflow(4, Buf::remaining(self))
  }
  let mut value = 0U
  for shift in [0, 8, 16, 24] {
    value = value | (Buf::get_u8(self).to_uint() << shift)
  }
  value
}

///|
impl Buf with fn get_i32_be(self) {
  Buf::get_u32_be(self).reinterpret_as_int()
}

///|
impl Buf with fn get_i32_le(self) {
  Buf::get_u32_le(self).reinterpret_as_int()
}

///|
impl Buf with fn get_f32_be(self) {
  Float::reinterpret_from_uint(Buf::get_u32_be(self))
}

///|
impl Buf with fn get_f32_le(self) {
  Float::reinterpret_from_uint(Buf::get_u32_le(self))
}

///|
impl Buf with fn get_u64_be(self) {
  if Buf::remaining(self) < 8 {
    raise BufferError::Underflow(8, Buf::remaining(self))
  }
  let mut value = 0UL
  for _ in 0..<8 {
    value = (value << 8) | Buf::get_u8(self).to_uint64()
  }
  value
}

///|
impl Buf with fn get_u64_le(self) {
  if Buf::remaining(self) < 8 {
    raise BufferError::Underflow(8, Buf::remaining(self))
  }
  let mut value = 0UL
  for shift in [0, 8, 16, 24, 32, 40, 48, 56] {
    value = value | (Buf::get_u8(self).to_uint64() << shift)
  }
  value
}

///|
impl Buf with fn get_i64_be(self) {
  Buf::get_u64_be(self).reinterpret_as_int64()
}

///|
impl Buf with fn get_i64_le(self) {
  Buf::get_u64_le(self).reinterpret_as_int64()
}

///|
impl Buf with fn get_f64_be(self) {
  Buf::get_u64_be(self).reinterpret_as_double()
}

///|
impl Buf with fn get_f64_le(self) {
  Buf::get_u64_le(self).reinterpret_as_double()
}

///|
pub impl Buf for BytesCursor with fn remaining(self) {
  self.remaining()
}

///|
pub impl Buf for BytesCursor with fn chunk(self) {
  self.remaining_bytes()
}

///|
pub impl Buf for BytesCursor with fn advance(self, count) {
  self.advance(count)
}

///|
pub impl Buf for BytesCursor with fn copy_to(self, dst) {
  self.copy_to(dst)
}

///|
pub impl Buf for BytesCursor with fn get_u8(self) {
  self.get_u8()
}

///|
pub impl Buf for BytesCursor with fn get_u16_be(self) {
  self.get_u16_be()
}

///|
pub impl Buf for BytesCursor with fn get_u16_le(self) {
  self.get_u16_le()
}

///|
pub impl Buf for BytesCursor with fn get_u32_be(self) {
  self.get_u32_be()
}

///|
pub impl Buf for BytesCursor with fn get_u32_le(self) {
  self.get_u32_le()
}

///|
pub impl Buf for BytesCursor with fn get_u64_be(self) {
  self.get_u64_be()
}

///|
pub impl Buf for BytesCursor with fn get_u64_le(self) {
  self.get_u64_le()
}

///|
/// Mutable byte construction operations.
pub(open) trait BufMut {
  fn remaining_mut(Self) -> Int
  fn has_remaining_mut(Self) -> Bool = _
  fn reserve(Self, Int) -> Unit raise BufferError
  fn put_byte(Self, Byte) -> Unit raise BufferError
  fn put_slice(Self, ArrayView[Byte]) -> Unit raise BufferError
  fn put_bytes_view(Self, BytesView) -> Unit raise BufferError = _
  fn put_bytes(Self, SharedBytes) -> Unit raise BufferError
  fn put_i8(Self, Int) -> Unit raise BufferError = _
  fn put_u16_be(Self, UInt16) -> Unit raise BufferError = _
  fn put_u16_le(Self, UInt16) -> Unit raise BufferError = _
  fn put_i16_be(Self, Int16) -> Unit raise BufferError = _
  fn put_i16_le(Self, Int16) -> Unit raise BufferError = _
  fn put_u32_be(Self, UInt) -> Unit raise BufferError = _
  fn put_u32_le(Self, UInt) -> Unit raise BufferError = _
  fn put_i32_be(Self, Int) -> Unit raise BufferError = _
  fn put_i32_le(Self, Int) -> Unit raise BufferError = _
  fn put_f32_be(Self, Float) -> Unit raise BufferError = _
  fn put_f32_le(Self, Float) -> Unit raise BufferError = _
  fn put_u64_be(Self, UInt64) -> Unit raise BufferError = _
  fn put_u64_le(Self, UInt64) -> Unit raise BufferError = _
  fn put_i64_be(Self, Int64) -> Unit raise BufferError = _
  fn put_i64_le(Self, Int64) -> Unit raise BufferError = _
  fn put_f64_be(Self, Double) -> Unit raise BufferError = _
  fn put_f64_le(Self, Double) -> Unit raise BufferError = _
  fn freeze(Self) -> SharedBytes
}

///|
impl BufMut with fn has_remaining_mut(self) {
  BufMut::remaining_mut(self) > 0
}

///|
impl BufMut with fn put_bytes_view(self, source) {
  BufMut::reserve(self, source.length())
  for byte in source {
    BufMut::put_byte(self, byte)
  }
}

///|
impl BufMut with fn put_i8(self, value) {
  if value < -128 || value > 127 {
    raise BufferError::InvalidRange("i8 value is outside [-128, 127]")
  }
  BufMut::reserve(self, 1)
  BufMut::put_byte(self, (value & 0xFF).to_byte())
}

///|
impl BufMut with fn put_u16_be(self, value) {
  BufMut::reserve(self, 2)
  BufMut::put_byte(self, (value.to_int() >> 8).to_byte())
  BufMut::put_byte(self, value.to_byte())
}

///|
impl BufMut with fn put_u16_le(self, value) {
  BufMut::reserve(self, 2)
  BufMut::put_byte(self, value.to_byte())
  BufMut::put_byte(self, (value.to_int() >> 8).to_byte())
}

///|
impl BufMut with fn put_i16_be(self, value) {
  BufMut::put_u16_be(self, value.reinterpret_as_uint16())
}

///|
impl BufMut with fn put_i16_le(self, value) {
  BufMut::put_u16_le(self, value.reinterpret_as_uint16())
}

///|
impl BufMut with fn put_u32_be(self, value) {
  BufMut::reserve(self, 4)
  for shift in [24, 16, 8, 0] {
    BufMut::put_byte(self, (value >> shift).to_byte())
  }
}

///|
impl BufMut with fn put_u32_le(self, value) {
  BufMut::reserve(self, 4)
  for shift in [0, 8, 16, 24] {
    BufMut::put_byte(self, (value >> shift).to_byte())
  }
}

///|
impl BufMut with fn put_i32_be(self, value) {
  BufMut::put_u32_be(self, value.reinterpret_as_uint())
}

///|
impl BufMut with fn put_i32_le(self, value) {
  BufMut::put_u32_le(self, value.reinterpret_as_uint())
}

///|
impl BufMut with fn put_f32_be(self, value) {
  BufMut::put_u32_be(self, value.reinterpret_as_uint())
}

///|
impl BufMut with fn put_f32_le(self, value) {
  BufMut::put_u32_le(self, value.reinterpret_as_uint())
}

///|
impl BufMut with fn put_u64_be(self, value) {
  BufMut::reserve(self, 8)
  for shift in [56, 48, 40, 32, 24, 16, 8, 0] {
    BufMut::put_byte(self, (value >> shift).to_byte())
  }
}

///|
impl BufMut with fn put_u64_le(self, value) {
  BufMut::reserve(self, 8)
  for shift in [0, 8, 16, 24, 32, 40, 48, 56] {
    BufMut::put_byte(self, (value >> shift).to_byte())
  }
}

///|
impl BufMut with fn put_i64_be(self, value) {
  BufMut::put_u64_be(self, value.reinterpret_as_uint64())
}

///|
impl BufMut with fn put_i64_le(self, value) {
  BufMut::put_u64_le(self, value.reinterpret_as_uint64())
}

///|
impl BufMut with fn put_f64_be(self, value) {
  BufMut::put_u64_be(self, value.reinterpret_as_uint64())
}

///|
impl BufMut with fn put_f64_le(self, value) {
  BufMut::put_u64_le(self, value.reinterpret_as_uint64())
}

///|
pub impl BufMut for BytesMut with fn remaining_mut(self) {
  self.remaining_mut()
}

///|
pub impl BufMut for BytesMut with fn reserve(self, count) {
  self.reserve(count)
}

///|
pub impl BufMut for BytesMut with fn put_byte(self, byte) {
  self.put_byte(byte)
}

///|
pub impl BufMut for BytesMut with fn put_slice(self, source) {
  self.put_slice(source)
}

///|
pub impl BufMut for BytesMut with fn put_bytes_view(self, source) {
  self.put_bytes_view(source)
}

///|
pub impl BufMut for BytesMut with fn put_bytes(self, source) {
  self.put_bytes(source)
}

///|
pub impl BufMut for BytesMut with fn freeze(self) {
  self.freeze()
}
