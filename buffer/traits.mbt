///|
/// In-memory cursor operations shared by immutable byte values.
pub(open) trait Buf {
  fn remaining(Self) -> Int
  fn chunk(Self) -> SharedBytes
  fn advance(Self, Int) -> Unit raise BufferError
  fn copy_to(Self, MutArrayView[Byte]) -> Int
  fn get_u8(Self) -> Byte raise BufferError
  fn get_u16_be(Self) -> UInt16 raise BufferError
  fn get_u16_le(Self) -> UInt16 raise BufferError
  fn get_u32_be(Self) -> UInt raise BufferError
  fn get_u32_le(Self) -> UInt raise BufferError
  fn get_u64_be(Self) -> UInt64 raise BufferError
  fn get_u64_le(Self) -> UInt64 raise BufferError
}

///|
pub impl Buf for SharedBytes with fn remaining(self) {
  self.remaining()
}

///|
pub impl Buf for SharedBytes with fn chunk(self) {
  self.chunk()
}

///|
pub impl Buf for SharedBytes with fn advance(self, count) {
  self.advance(count)
}

///|
pub impl Buf for SharedBytes with fn copy_to(self, dst) {
  self.copy_to(dst)
}

///|
pub impl Buf for SharedBytes with fn get_u8(self) {
  self.get_u8()
}

///|
pub impl Buf for SharedBytes with fn get_u16_be(self) {
  self.get_u16_be()
}

///|
pub impl Buf for SharedBytes with fn get_u16_le(self) {
  self.get_u16_le()
}

///|
pub impl Buf for SharedBytes with fn get_u32_be(self) {
  self.get_u32_be()
}

///|
pub impl Buf for SharedBytes with fn get_u32_le(self) {
  self.get_u32_le()
}

///|
pub impl Buf for SharedBytes with fn get_u64_be(self) {
  self.get_u64_be()
}

///|
pub impl Buf for SharedBytes with fn get_u64_le(self) {
  self.get_u64_le()
}

///|
/// Mutable byte construction operations.
pub(open) trait BufMut {
  fn remaining_mut(Self) -> Int
  fn reserve(Self, Int) -> Unit raise BufferError
  fn put_byte(Self, Byte) -> Unit raise BufferError
  fn put_slice(Self, ArrayView[Byte]) -> Unit raise BufferError
  fn put_bytes(Self, SharedBytes) -> Unit raise BufferError
  fn freeze(Self) -> SharedBytes
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
pub impl BufMut for BytesMut with fn put_bytes(self, source) {
  self.put_bytes(source)
}

///|
pub impl BufMut for BytesMut with fn freeze(self) {
  self.freeze()
}
