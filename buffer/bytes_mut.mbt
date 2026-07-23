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
      data: Array::new(capacity~),
      capacity,
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
  self.storage.capacity - self.start
}

///|
pub fn BytesMut::remaining_mut(self : BytesMut) -> Int {
  self.max_capacity - self.len()
}

///|
pub fn BytesMut::view(self : BytesMut) -> ArrayView[Byte] {
  self.storage.data[self.start:self.end]
}

///|
fn BytesMut::ensure_unique(self : BytesMut) -> Unit {
  if self.storage.immutable {
    let data = self.view().to_owned()
    let copied = data.length()
    self.storage = {
      data,
      capacity: copied,
      immutable: false,
      copied_bytes: copied,
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
  self.ensure_unique()
  let required = self.end + additional
  if required <= self.storage.capacity {
    return
  }
  let current = self.storage.capacity
  let doubled = if current > 1073741823 {
    2147483647
  } else {
    Int::max(1, current * 2)
  }
  let target = Int::min(self.max_capacity, Int::max(required, doubled))
  self.storage.data.reserve_capacity(target)
  self.storage.capacity = target
}

///|
pub fn BytesMut::clear(self : BytesMut) -> Unit {
  self.ensure_unique()
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
  self.ensure_unique()
  self.end = self.start + length
}

///|
pub fn BytesMut::put_byte(
  self : BytesMut,
  value : Byte,
) -> Unit raise BufferError {
  self.reserve(1)
  if self.end < self.storage.data.length() {
    self.storage.data[self.end] = value
  } else {
    self.storage.data.push(value)
  }
  self.end += 1
}

///|
pub fn BytesMut::put_slice(
  self : BytesMut,
  source : ArrayView[Byte],
) -> Unit raise BufferError {
  self.reserve(source.length())
  let required = self.end + source.length()
  if required > self.storage.data.length() {
    self.storage.data.resize(required, (0).to_byte())
  }
  source.blit_to(self.storage.data, dst_offset=self.end)
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
pub fn BytesMut::copied_bytes(self : BytesMut) -> Int {
  self.storage.copied_bytes
}
