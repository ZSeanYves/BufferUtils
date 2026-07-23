///|
/// Internal storage shared by immutable and mutable handles.
///
/// `immutable` is a conservative copy-on-write marker. Once a storage is
/// exposed through `SharedBytes` or split into siblings, a later mutable operation
/// detaches before writing.
struct SharedStorage {
  data : Array[Byte]
  mut capacity : Int
  mut immutable : Bool
  mut copied_bytes : Int
}

///|
/// Immutable shared byte storage with an independent cursor.
pub struct SharedBytes {
  storage : SharedStorage
  mut start : Int
  end : Int
}

///|
/// Create immutable storage by copying an array view.
pub fn SharedBytes::from_array(data : ArrayView[Byte]) -> SharedBytes {
  {
    storage: {
      data: data.to_owned(),
      capacity: data.length(),
      immutable: true,
      copied_bytes: 0,
    },
    start: 0,
    end: data.length(),
  }
}

///|
/// Create an empty immutable value.
pub fn SharedBytes::new() -> SharedBytes {
  SharedBytes::from_array([][:])
}

///|
/// Number of unread bytes.
pub fn SharedBytes::remaining(self : SharedBytes) -> Int {
  self.end - self.start
}

///|
/// Alias for `remaining` when the value is used as a byte sequence.
pub fn SharedBytes::len(self : SharedBytes) -> Int {
  self.remaining()
}

///|
pub fn SharedBytes::is_empty(self : SharedBytes) -> Bool {
  self.remaining() == 0
}

///|
/// Return a read-only view over the current range without copying.
pub fn SharedBytes::view(self : SharedBytes) -> ArrayView[Byte] {
  self.storage.data[self.start:self.end]
}

///|
/// Return a shared cursor over the current range.
pub fn SharedBytes::chunk(self : SharedBytes) -> SharedBytes {
  { storage: self.storage, start: self.start, end: self.end }
}

///|
/// Clone the current range in O(1) with an independent cursor.
pub fn SharedBytes::clone(self : SharedBytes) -> SharedBytes {
  self.chunk()
}

///|
/// Return a shared sub-range. The range is relative to the current cursor.
pub fn SharedBytes::slice(
  self : SharedBytes,
  start : Int,
  end : Int,
) -> SharedBytes raise BufferError {
  if start < 0 || end < start || end > self.remaining() {
    raise BufferError::InvalidRange("bytes slice is outside the current range")
  }
  { storage: self.storage, start: self.start + start, end: self.start + end }
}

///|
/// Return the next `count` bytes and advance this cursor.
pub fn SharedBytes::split_to(
  self : SharedBytes,
  count : Int,
) -> SharedBytes raise BufferError {
  if count < 0 || count > self.remaining() {
    raise BufferError::Underflow(count, self.remaining())
  }
  let result = {
    storage: self.storage,
    start: self.start,
    end: self.start + count,
  }
  self.start += count
  result
}

///|
pub fn SharedBytes::advance(
  self : SharedBytes,
  count : Int,
) -> Unit raise BufferError {
  if count < 0 || count > self.remaining() {
    raise BufferError::Underflow(count, self.remaining())
  }
  self.start += count
}

///|
/// Copy unread bytes into caller-owned storage and advance by the copied count.
pub fn SharedBytes::copy_to(
  self : SharedBytes,
  dst : MutArrayView[Byte],
) -> Int {
  let count = Int::min(self.remaining(), dst.length())
  let source = self.view()
  for i in 0..<count {
    dst[i] = source[i]
  }
  self.start += count
  count
}

///|
/// Explicit copy boundary to a mutable MoonBit array.
pub fn SharedBytes::to_array(self : SharedBytes) -> Array[Byte] {
  self.view().to_owned()
}

///|
/// Read one byte.
pub fn SharedBytes::get_u8(self : SharedBytes) -> Byte raise BufferError {
  if self.is_empty() {
    raise BufferError::Underflow(1, 0)
  }
  let result = self.storage.data[self.start]
  self.start += 1
  result
}

///|
pub fn SharedBytes::get_u16_be(self : SharedBytes) -> UInt16 raise BufferError {
  let view = self.split_to(2).view()
  ((view[0].to_int() << 8) | view[1].to_int()).to_uint16()
}

///|
pub fn SharedBytes::get_u16_le(self : SharedBytes) -> UInt16 raise BufferError {
  let view = self.split_to(2).view()
  (view[0].to_int() | (view[1].to_int() << 8)).to_uint16()
}

///|
pub fn SharedBytes::get_u32_be(self : SharedBytes) -> UInt raise BufferError {
  let view = self.split_to(4).view()
  (view[0].to_uint() << 24) |
  (view[1].to_uint() << 16) |
  (view[2].to_uint() << 8) |
  view[3].to_uint()
}

///|
pub fn SharedBytes::get_u32_le(self : SharedBytes) -> UInt raise BufferError {
  let view = self.split_to(4).view()
  view[0].to_uint() |
  (view[1].to_uint() << 8) |
  (view[2].to_uint() << 16) |
  (view[3].to_uint() << 24)
}

///|
pub fn SharedBytes::get_u64_be(self : SharedBytes) -> UInt64 raise BufferError {
  let view = self.split_to(8).view()
  (view[0].to_uint64() << 56) |
  (view[1].to_uint64() << 48) |
  (view[2].to_uint64() << 40) |
  (view[3].to_uint64() << 32) |
  (view[4].to_uint64() << 24) |
  (view[5].to_uint64() << 16) |
  (view[6].to_uint64() << 8) |
  view[7].to_uint64()
}

///|
pub fn SharedBytes::get_u64_le(self : SharedBytes) -> UInt64 raise BufferError {
  let view = self.split_to(8).view()
  view[0].to_uint64() |
  (view[1].to_uint64() << 8) |
  (view[2].to_uint64() << 16) |
  (view[3].to_uint64() << 24) |
  (view[4].to_uint64() << 32) |
  (view[5].to_uint64() << 40) |
  (view[6].to_uint64() << 48) |
  (view[7].to_uint64() << 56)
}

///|
pub fn SharedBytes::get_utf8(
  self : SharedBytes,
  count : Int,
) -> String raise BufferError {
  if count < 0 || count > self.remaining() {
    raise BufferError::Underflow(count, self.remaining())
  }
  let view = self.storage.data[self.start:self.start + count]
  let core_bytes = FixedArray::from_array(view).unsafe_reinterpret_as_bytes()
  let decoded = @utf8.decode(core_bytes[:]) catch {
    _ => raise BufferError::InvalidUtf8
  }
  self.start += count
  decoded
}

///|
/// Number of bytes copied by copy-on-write for this storage.
pub fn SharedBytes::copied_bytes(self : SharedBytes) -> Int {
  self.storage.copied_bytes
}
