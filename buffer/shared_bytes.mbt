///|
/// Internal storage shared by immutable and mutable handles.
///
/// `immutable` is a conservative copy-on-write marker. Once a storage is
/// exposed through `SharedBytes` or split into siblings, a later mutable operation
/// detaches before writing.
struct SharedStorage {
  data : FixedArray[Byte]
  mut immutable : Bool
  copied_bytes : Int
}

///|
/// Immutable shared byte storage with an independent cursor.
pub struct SharedBytes {
  data : FixedArray[Byte]
  mut start : Int
  mut end : Int
  copied_bytes : Int
}

///|
/// Create immutable storage by copying an array view.
pub fn SharedBytes::from_array(data : ArrayView[Byte]) -> SharedBytes {
  {
    data: FixedArray::from_array(data),
    start: 0,
    end: data.length(),
    copied_bytes: 0,
  }
}

///|
/// Create immutable storage by copying a fixed-array range.
///
/// Subsequent mutations to `data` cannot affect the returned value.
pub fn SharedBytes::from_fixed_array(
  data : FixedArray[Byte],
  start : Int,
  end : Int,
) -> SharedBytes raise BufferError {
  if start < 0 || end < start || end > data.length() {
    raise BufferError::InvalidRange(
      "fixed-array range is outside the backing storage",
    )
  }
  SharedBytes::from_array(data.view(start~, end~))
}

///|
/// Adopt a fixed-array range without copying.
///
/// # Safety
///
/// The caller must ensure that `data` is never mutated while the returned value
/// or any slice derived from it is reachable. Use `from_fixed_array` unless the
/// backing allocation is exclusively owned by the library.
pub fn SharedBytes::unsafe_adopt_fixed_array(
  data : FixedArray[Byte],
  start : Int,
  end : Int,
) -> SharedBytes raise BufferError {
  if start < 0 || end < start || end > data.length() {
    raise BufferError::InvalidRange(
      "fixed-array range is outside the backing storage",
    )
  }
  { data, start, end, copied_bytes: 0 }
}

///|
/// Create an empty immutable value.
pub fn SharedBytes::new() -> SharedBytes {
  SharedBytes::from_array([][:])
}

///|
/// Number of unread bytes.
#inline
pub fn SharedBytes::remaining(self : SharedBytes) -> Int {
  self.end - self.start
}

///|
/// Alias for `remaining` when the value is used as a byte sequence.
pub fn SharedBytes::len(self : SharedBytes) -> Int {
  self.remaining()
}

///|
/// Test whether the visible range is empty.
pub fn SharedBytes::is_empty(self : SharedBytes) -> Bool {
  self.remaining() == 0
}

///|
/// Remove all visible bytes while retaining the shared allocation.
pub fn SharedBytes::clear(self : SharedBytes) -> Unit {
  self.start = self.end
}

///|
/// Shorten the visible range to `length` bytes.
pub fn SharedBytes::truncate(
  self : SharedBytes,
  length : Int,
) -> Unit raise BufferError {
  if length < 0 || length > self.remaining() {
    raise BufferError::InvalidRange("truncate length is outside the bytes")
  }
  self.end = self.start + length
}

///|
/// Split at an index relative to the current cursor, returning the suffix.
pub fn SharedBytes::split_off(
  self : SharedBytes,
  at : Int,
) -> SharedBytes raise BufferError {
  if at < 0 || at > self.remaining() {
    raise BufferError::InvalidRange("split index is outside the bytes")
  }
  let suffix = {
    data: self.data,
    start: self.start + at,
    end: self.end,
    copied_bytes: self.copied_bytes,
  }
  self.end = self.start + at
  suffix
}

///|
/// Return a read-only view over the current range without copying.
pub fn SharedBytes::view(self : SharedBytes) -> ArrayView[Byte] {
  self.data.view(start=self.start, end=self.end)
}

///|
/// Return a zero-copy Core Bytes view over the current shared range.
///
/// The backing storage is immutable for as long as this handle is reachable;
/// mutable siblings detach through copy-on-write before modifying it.
pub fn SharedBytes::as_bytes_view(self : SharedBytes) -> BytesView {
  self.data.unsafe_reinterpret_as_bytes()[self.start:self.end]
}

///|
/// Return a shared cursor over the current range.
#inline
pub fn SharedBytes::chunk(self : SharedBytes) -> SharedBytes {
  {
    data: self.data,
    start: self.start,
    end: self.end,
    copied_bytes: self.copied_bytes,
  }
}

///|
/// Clone the current range in O(1) with an independent cursor.
#inline
pub fn SharedBytes::clone(self : SharedBytes) -> SharedBytes {
  self.chunk()
}

///|
/// Return a shared sub-range. The range is relative to the current cursor.
#inline
pub fn SharedBytes::slice(
  self : SharedBytes,
  start : Int,
  end : Int,
) -> SharedBytes raise BufferError {
  if start < 0 || end < start || end > self.remaining() {
    raise BufferError::InvalidRange("bytes slice is outside the current range")
  }
  if start == 0 && end == self.remaining() {
    return self.chunk()
  }
  {
    data: self.data,
    start: self.start + start,
    end: self.start + end,
    copied_bytes: self.copied_bytes,
  }
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
    data: self.data,
    start: self.start,
    end: self.start + count,
    copied_bytes: self.copied_bytes,
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
/// Materialize the current range as an owned Core Bytes value.
pub fn SharedBytes::to_bytes(self : SharedBytes) -> Bytes {
  self.as_bytes_view().to_owned()
}

///|
/// Read one byte.
pub fn SharedBytes::get_u8(self : SharedBytes) -> Byte raise BufferError {
  if self.is_empty() {
    raise BufferError::Underflow(1, 0)
  }
  let result = self.data[self.start]
  self.start += 1
  result
}

///|
/// Read a signed 8-bit integer and advance the cursor.
pub fn SharedBytes::get_i8(self : SharedBytes) -> Int raise BufferError {
  let value = self.get_u8().to_int()
  if value < 128 {
    value
  } else {
    value - 256
  }
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
pub fn SharedBytes::get_i16_be(self : SharedBytes) -> Int16 raise BufferError {
  Int16::reinterpret_from_uint16(self.get_u16_be())
}

///|
pub fn SharedBytes::get_i16_le(self : SharedBytes) -> Int16 raise BufferError {
  Int16::reinterpret_from_uint16(self.get_u16_le())
}

///|
pub fn SharedBytes::get_i32_be(self : SharedBytes) -> Int raise BufferError {
  self.get_u32_be().reinterpret_as_int()
}

///|
pub fn SharedBytes::get_i32_le(self : SharedBytes) -> Int raise BufferError {
  self.get_u32_le().reinterpret_as_int()
}

///|
pub fn SharedBytes::get_i64_be(self : SharedBytes) -> Int64 raise BufferError {
  self.get_u64_be().reinterpret_as_int64()
}

///|
pub fn SharedBytes::get_i64_le(self : SharedBytes) -> Int64 raise BufferError {
  self.get_u64_le().reinterpret_as_int64()
}

///|
pub fn SharedBytes::get_f32_be(self : SharedBytes) -> Float raise BufferError {
  Float::reinterpret_from_uint(self.get_u32_be())
}

///|
pub fn SharedBytes::get_f32_le(self : SharedBytes) -> Float raise BufferError {
  Float::reinterpret_from_uint(self.get_u32_le())
}

///|
pub fn SharedBytes::get_f64_be(self : SharedBytes) -> Double raise BufferError {
  self.get_u64_be().reinterpret_as_double()
}

///|
pub fn SharedBytes::get_f64_le(self : SharedBytes) -> Double raise BufferError {
  self.get_u64_le().reinterpret_as_double()
}

///|
pub fn SharedBytes::get_utf8(
  self : SharedBytes,
  count : Int,
) -> String raise BufferError {
  if count < 0 || count > self.remaining() {
    raise BufferError::Underflow(count, self.remaining())
  }
  let bytes = self.as_bytes_view()[0:count]
  let decoded = @utf8.decode(bytes) catch {
    _ => raise BufferError::InvalidUtf8
  }
  self.start += count
  decoded
}

///|
/// Number of bytes copied by copy-on-write for this storage.
pub fn SharedBytes::copied_bytes(self : SharedBytes) -> Int {
  self.copied_bytes
}

///|
pub impl Eq for SharedBytes with fn equal(self, other) {
  self.as_bytes_view().equal(other.as_bytes_view())
}

///|
pub impl Compare for SharedBytes with fn compare(self, other) {
  let order = self.as_bytes_view().lexical_compare(other.as_bytes_view())
  if order < 0 {
    -1
  } else if order > 0 {
    1
  } else {
    0
  }
}

///|
pub impl Hash for SharedBytes with fn hash_combine(self, hasher) {
  hasher.combine(self.as_bytes_view().hash())
}

///|
pub impl @debug.Debug for SharedBytes with fn to_repr(self) {
  @debug.Repr::opaque_(
    "SharedBytes",
    @debug.Repr::array(self.view().map(byte => Repr(byte))),
  )
}
