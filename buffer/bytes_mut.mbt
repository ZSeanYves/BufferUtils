///|
/// Mutable shared storage. Mutating a value whose storage is shared detaches
/// the current range before writing, preserving all immutable siblings.
pub struct BytesMut {
  mut storage : SharedStorage
  mut start : Int
  mut end : Int
  max_capacity : Int
}

///|
pub fn BytesMut::new(
  capacity? : Int = 0,
  max_capacity? : Int = 2147483647,
) -> BytesMut raise BufferError {
  if capacity < 0 || max_capacity < 0 || capacity > max_capacity {
    raise BufferError::InvalidRange("invalid buffer capacity")
  }
  {
    storage: {
      data: FixedArray::make(capacity, (0).to_byte()),
      immutable: false,
      copied_bytes: 0,
    },
    start: 0,
    end: 0,
    max_capacity,
  }
}

///|
pub fn BytesMut::from_array(
  data : ArrayView[Byte],
  max_capacity? : Int = 2147483647,
) -> BytesMut raise BufferError {
  let result = BytesMut::new(capacity=data.length(), max_capacity~)
  result.put_slice(data)
  result
}

///|
pub fn BytesMut::len(self : BytesMut) -> Int {
  self.end - self.start
}

///|
pub fn BytesMut::is_empty(self : BytesMut) -> Bool {
  self.len() == 0
}

///|
pub fn BytesMut::capacity(self : BytesMut) -> Int {
  self.storage.data.length() - self.start
}

///|
pub fn BytesMut::remaining_mut(self : BytesMut) -> Int {
  self.max_capacity - self.len()
}

///|
pub fn BytesMut::view(self : BytesMut) -> ArrayView[Byte] {
  self.storage.data.view(start=self.start, end=self.end)
}

///|
fn BytesMut::ensure_unique(self : BytesMut) -> Unit {
  if self.storage.immutable {
    let copied = self.len()
    let data = FixedArray::make(copied, (0).to_byte())
    self.storage.data.blit_to(
      data,
      src_offset=self.start,
      dst_offset=0,
      len=copied,
    )
    self.storage = {
      data,
      immutable: false,
      copied_bytes: self.storage.copied_bytes + copied,
    }
    self.start = 0
    self.end = copied
  }
}

///|
pub fn BytesMut::reserve(
  self : BytesMut,
  additional : Int,
) -> Unit raise BufferError {
  if additional < 0 || additional > self.remaining_mut() {
    raise BufferError::CapacityOverflow(self.len(), additional)
  }
  let required_len = self.len() + additional
  if !self.storage.immutable &&
    self.end + additional <= self.storage.data.length() {
    return
  }
  let current = self.storage.data.length()
  let doubled = if current > 1073741823 {
    2147483647
  } else {
    Int::max(1, current * 2)
  }
  let target = Int::min(self.max_capacity, Int::max(required_len, doubled))
  let data = FixedArray::make(target, (0).to_byte())
  let length = self.len()
  self.storage.data.blit_to(
    data,
    src_offset=self.start,
    dst_offset=0,
    len=length,
  )
  self.storage = {
    data,
    immutable: false,
    copied_bytes: self.storage.copied_bytes + length,
  }
  self.start = 0
  self.end = length
}

///|
pub fn BytesMut::clear(self : BytesMut) -> Unit {
  self.start = 0
  self.end = 0
}

///|
pub fn BytesMut::truncate(
  self : BytesMut,
  length : Int,
) -> Unit raise BufferError {
  if length < 0 || length > self.len() {
    raise BufferError::InvalidRange("truncate length is outside the buffer")
  }
  self.end = self.start + length
}

///|
/// Resize the initialized range, zero-filling newly initialized bytes.
pub fn BytesMut::resize(
  self : BytesMut,
  length : Int,
  value? : Byte = (0).to_byte(),
) -> Unit raise BufferError {
  if length < 0 {
    raise BufferError::InvalidRange("resize length must be non-negative")
  }
  if length <= self.len() {
    self.truncate(length)
    return
  }
  let additional = length - self.len()
  self.reserve(additional)
  for i in self.end..<(self.end + additional) {
    self.storage.data[i] = value
  }
  self.end += additional
}

///|
pub fn BytesMut::put_byte(
  self : BytesMut,
  value : Byte,
) -> Unit raise BufferError {
  self.reserve(1)
  self.storage.data[self.end] = value
  self.end += 1
}

///|
pub fn BytesMut::put_slice(
  self : BytesMut,
  source : ArrayView[Byte],
) -> Unit raise BufferError {
  self.reserve(source.length())
  for i, byte in source {
    self.storage.data[self.end + i] = byte
  }
  self.end += source.length()
}

///|
pub fn BytesMut::put_bytes(
  self : BytesMut,
  source : SharedBytes,
) -> Unit raise BufferError {
  self.put_slice(source.view())
}

///|
pub fn BytesMut::put_u16_be(
  self : BytesMut,
  value : UInt16,
) -> Unit raise BufferError {
  self.reserve(2)
  self.put_byte((value.to_int() >> 8).to_byte())
  self.put_byte(value.to_byte())
}

///|
pub fn BytesMut::put_i8(self : BytesMut, value : Int) -> Unit raise BufferError {
  if value < -128 || value > 127 {
    raise BufferError::InvalidRange("i8 value is outside [-128, 127]")
  }
  self.put_byte((value & 0xFF).to_byte())
}

///|
pub fn BytesMut::put_u16_le(
  self : BytesMut,
  value : UInt16,
) -> Unit raise BufferError {
  self.reserve(2)
  self.put_byte(value.to_byte())
  self.put_byte((value.to_int() >> 8).to_byte())
}

///|
pub fn BytesMut::put_u32_be(
  self : BytesMut,
  value : UInt,
) -> Unit raise BufferError {
  self.reserve(4)
  for shift in [24, 16, 8, 0] {
    self.put_byte((value >> shift).to_byte())
  }
}

///|
pub fn BytesMut::put_u32_le(
  self : BytesMut,
  value : UInt,
) -> Unit raise BufferError {
  self.reserve(4)
  for shift in [0, 8, 16, 24] {
    self.put_byte((value >> shift).to_byte())
  }
}

///|
pub fn BytesMut::put_u64_be(
  self : BytesMut,
  value : UInt64,
) -> Unit raise BufferError {
  self.reserve(8)
  for shift in [56, 48, 40, 32, 24, 16, 8, 0] {
    self.put_byte((value >> shift).to_byte())
  }
}

///|
pub fn BytesMut::put_u64_le(
  self : BytesMut,
  value : UInt64,
) -> Unit raise BufferError {
  self.reserve(8)
  for shift in [0, 8, 16, 24, 32, 40, 48, 56] {
    self.put_byte((value >> shift).to_byte())
  }
}

///|
pub fn BytesMut::put_i16_be(
  self : BytesMut,
  value : Int16,
) -> Unit raise BufferError {
  self.put_u16_be(value.reinterpret_as_uint16())
}

///|
pub fn BytesMut::put_i16_le(
  self : BytesMut,
  value : Int16,
) -> Unit raise BufferError {
  self.put_u16_le(value.reinterpret_as_uint16())
}

///|
pub fn BytesMut::put_i32_be(
  self : BytesMut,
  value : Int,
) -> Unit raise BufferError {
  self.put_u32_be(value.reinterpret_as_uint())
}

///|
pub fn BytesMut::put_i32_le(
  self : BytesMut,
  value : Int,
) -> Unit raise BufferError {
  self.put_u32_le(value.reinterpret_as_uint())
}

///|
pub fn BytesMut::put_i64_be(
  self : BytesMut,
  value : Int64,
) -> Unit raise BufferError {
  self.put_u64_be(value.reinterpret_as_uint64())
}

///|
pub fn BytesMut::put_i64_le(
  self : BytesMut,
  value : Int64,
) -> Unit raise BufferError {
  self.put_u64_le(value.reinterpret_as_uint64())
}

///|
pub fn BytesMut::put_f32_be(
  self : BytesMut,
  value : Float,
) -> Unit raise BufferError {
  self.put_u32_be(value.reinterpret_as_uint())
}

///|
pub fn BytesMut::put_f32_le(
  self : BytesMut,
  value : Float,
) -> Unit raise BufferError {
  self.put_u32_le(value.reinterpret_as_uint())
}

///|
pub fn BytesMut::put_f64_be(
  self : BytesMut,
  value : Double,
) -> Unit raise BufferError {
  self.put_u64_be(value.reinterpret_as_uint64())
}

///|
pub fn BytesMut::put_f64_le(
  self : BytesMut,
  value : Double,
) -> Unit raise BufferError {
  self.put_u64_le(value.reinterpret_as_uint64())
}

///|
pub fn BytesMut::put_utf8(
  self : BytesMut,
  text : StringView,
) -> Unit raise BufferError {
  let encoded = @utf8.encode(text)
  self.reserve(encoded.length())
  for byte in encoded {
    self.put_byte(byte)
  }
}

///|
pub fn BytesMut::split_to(
  self : BytesMut,
  count : Int,
) -> BytesMut raise BufferError {
  if count < 0 || count > self.len() {
    raise BufferError::Underflow(count, self.len())
  }
  self.storage.immutable = true
  let result = {
    storage: self.storage,
    start: self.start,
    end: self.start + count,
    max_capacity: self.max_capacity,
  }
  self.start += count
  result
}

///|
pub fn BytesMut::split_off(
  self : BytesMut,
  at : Int,
) -> BytesMut raise BufferError {
  if at < 0 || at > self.len() {
    raise BufferError::InvalidRange("split index is outside the buffer")
  }
  self.storage.immutable = true
  let result = {
    storage: self.storage,
    start: self.start + at,
    end: self.end,
    max_capacity: self.max_capacity,
  }
  self.end = self.start + at
  result
}

///|
/// Split off the complete initialized range, leaving this buffer empty.
pub fn BytesMut::split(self : BytesMut) -> BytesMut raise BufferError {
  self.split_to(self.len())
}

///|
/// Reclaim unused prefix capacity without allocating when storage is unique.
pub fn BytesMut::try_reclaim(
  self : BytesMut,
  additional : Int,
) -> Bool raise BufferError {
  if additional < 0 || additional > self.remaining_mut() {
    raise BufferError::CapacityOverflow(self.len(), additional)
  }
  if self.end + additional <= self.storage.data.length() {
    return true
  }
  if self.storage.immutable ||
    self.len() + additional > self.storage.data.length() {
    return false
  }
  let length = self.len()
  self.storage.data.blit_to(
    self.storage.data,
    src_offset=self.start,
    dst_offset=0,
    len=length,
  )
  self.start = 0
  self.end = length
  true
}

///|
/// Join adjacent ranges sharing the same allocation without copying.
pub fn BytesMut::try_unsplit(self : BytesMut, other : BytesMut) -> Bool {
  if !physical_equal(self.storage, other.storage) || self.end != other.start {
    return false
  }
  self.end = other.end
  self.storage.immutable = true
  true
}

///|
/// Join another buffer, copying only when the ranges cannot be rejoined.
pub fn BytesMut::unsplit(
  self : BytesMut,
  other : BytesMut,
) -> Unit raise BufferError {
  if !self.try_unsplit(other) {
    self.put_slice(other.view())
  }
}

///|
/// Freeze without copying. Future mutable writes detach through COW.
pub fn BytesMut::freeze(self : BytesMut) -> SharedBytes {
  self.storage.immutable = true
  { storage: self.storage, start: self.start, end: self.end }
}

///|
/// Execute a bounded mutation against the currently initialized range.
pub fn[T] BytesMut::with_writable(
  self : BytesMut,
  f : (MutArrayView[Byte]) -> T,
) -> T {
  self.ensure_unique()
  f(self.storage.data.mut_view(start=self.start, end=self.end))
}

///|
/// Reserve writable spare capacity and commit the count returned by `f`.
pub fn[T] BytesMut::with_spare_capacity(
  self : BytesMut,
  minimum : Int,
  f : (MutArrayView[Byte]) -> (Int, T),
) -> T raise BufferError {
  self.reserve(minimum)
  let spare = self.storage.data.mut_view(start=self.end)
  let (initialized, result) = f(spare)
  if initialized < 0 || initialized > spare.length() {
    raise BufferError::InvalidRange("initialized spare length is invalid")
  }
  self.end += initialized
  result
}

///|
pub fn BytesMut::copied_bytes(self : BytesMut) -> Int {
  self.storage.copied_bytes
}
